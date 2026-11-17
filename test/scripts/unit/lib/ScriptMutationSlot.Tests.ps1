#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptMutationSlot
    # Process double: records Kill and WaitForExit; Exits decides whether WaitForExit ends the process.
    $newProcess={param([bool]$HasExited=$false,[int]$ExitCode=0,[bool]$Exits=$true)
        $process=[pscustomobject]@{HasExited=$HasExited;ExitCode=$ExitCode;Exits=$Exits;Killed=@();Waits=0;Disposed=$false}
        $process|Add-Member -MemberType ScriptMethod -Name Kill -Value {param($tree)$this.Killed+=$tree;$this.HasExited=$true}
        $process|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param($milliseconds)$this.Waits++;if($this.Exits){$this.HasExited=$true};$this.HasExited}
        $process|Add-Member -MemberType ScriptMethod -Name Dispose -Value {$this.Disposed=$true}
        $process
    }
    $newSlot={param($Process=(& $newProcess))
        $directory=[IO.Path]::Combine($TestDrive,'slot-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        [pscustomobject]@{Index=0;Directory=$directory;ScriptsRoot='s';Process=$Process;Sequence=0;Jobs=0;Job=$null;Alive=$true}
    }
    $submit={param($Slot,[int]$Timeout=60,[switch]$Bail)Submit-QuietScriptsMutationJob -Slot $Slot -Name 'm1' -UnitTestFiles @('unit/A.Tests.ps1','unit/B.Tests.ps1') -Bail:$Bail -TimeoutSeconds $Timeout}
    $writeResult={param($Slot,[string]$Text)[IO.File]::WriteAllText([IO.Path]::Combine($Slot.Directory,'result-'+$Slot.Job.Sequence+'.json'),$Text)}
    $files={param($Slot)@([IO.Directory]::GetFiles($Slot.Directory)|ForEach-Object {[IO.Path]::GetFileName($_)}|Sort-Object)}
}

Describe 'Submit-QuietScriptsMutationJob' {
    It 'writes the numbered job document and records the deadline' {
        $slot=& $newSlot
        & $submit $slot -Timeout 90 -Bail
        $slot.Sequence|Should -Be 1
        $job=Get-Content -LiteralPath ([IO.Path]::Combine($slot.Directory,'job-1.json')) -Raw|ConvertFrom-Json
        $job.Sequence|Should -Be 1
        $job.Name|Should -BeExactly 'm1'
        @($job.UnitTestFiles)|Should -Be @('unit/A.Tests.ps1','unit/B.Tests.ps1')
        $job.Bail|Should -BeTrue
        ($slot.Job.Deadline-$slot.Job.Started).TotalSeconds|Should -Be 90
        $slot.Job.Sequence|Should -Be 1
    }

    It 'numbers jobs in order and records a run without bail' {
        $slot=& $newSlot
        & $submit $slot
        $slot.Job=$null
        & $submit $slot
        $slot.Sequence|Should -Be 2
        (Get-Content -LiteralPath ([IO.Path]::Combine($slot.Directory,'job-2.json')) -Raw|ConvertFrom-Json).Bail|Should -BeFalse
    }

    It 'records no phase by default and each phase as a list of patterns, in order' {
        $slot=& $newSlot
        & $submit $slot
        $job=Get-Content -LiteralPath ([IO.Path]::Combine($slot.Directory,'job-1.json')) -Raw|ConvertFrom-Json -AsHashtable
        @($job.Phases).Count|Should -Be 0
        $slot.Job=$null
        Submit-QuietScriptsMutationJob -Slot $slot -Name 'm2' -UnitTestFiles @('unit/A.Tests.ps1') -Bail -Phases @(@('Get-A'),@('Get-B','c `[x`]')) -TimeoutSeconds 60
        $job=Get-Content -LiteralPath ([IO.Path]::Combine($slot.Directory,'job-2.json')) -Raw|ConvertFrom-Json -AsHashtable
        @($job.Phases).Count|Should -Be 2
        @($job.Phases[0])|Should -Be @('Get-A')
        @($job.Phases[1])|Should -Be @('Get-B','c `[x`]')
    }

    It 'drops blank patterns and rejects a phase with none left, which would run every test' -ForEach @(
        @{Case='empty';Phase=@()}
        @{Case='blank';Phase=@('',' ')}
    ) {
        $slot=& $newSlot
        {Submit-QuietScriptsMutationJob -Slot $slot -Name 'm' -UnitTestFiles @('unit/A.Tests.ps1') -Phases @(@('Get-A'),$Phase) -TimeoutSeconds 60}|Should -Throw -ExpectedMessage 'ScriptMutationSlotPhaseEmpty'
        $slot.Sequence|Should -Be 0
        & $files $slot|Should -BeNullOrEmpty
        Submit-QuietScriptsMutationJob -Slot $slot -Name 'm' -UnitTestFiles @('unit/A.Tests.ps1') -Phases @(,@('Get-A',' ')) -TimeoutSeconds 60
        @((Get-Content -LiteralPath ([IO.Path]::Combine($slot.Directory,'job-1.json')) -Raw|ConvertFrom-Json -AsHashtable).Phases[0])|Should -Be @('Get-A')
    }

    It 'rejects a busy slot without writing a job' {
        $slot=& $newSlot
        & $submit $slot
        {& $submit $slot}|Should -Throw -ExpectedMessage 'ScriptMutationSlotBusy'
        $slot.Sequence|Should -Be 1
        & $files $slot|Should -Be @('job-1.json')
    }

    It 'rejects a dead slot' {
        $slot=& $newSlot;$slot.Alive=$false
        {& $submit $slot}|Should -Throw -ExpectedMessage 'ScriptMutationSlotDead'
        $slot.Sequence|Should -Be 0
    }

    It 'rejects the timeout <Value>' -ForEach @(@{Value=0},@{Value=86401}) {
        {& $submit (& $newSlot) -Timeout $Value}|Should -Throw
    }
}

Describe 'Receive-QuietScriptsMutationJob' {
    It 'rejects an idle slot' {
        {Receive-QuietScriptsMutationJob -Slot (& $newSlot)}|Should -Throw -ExpectedMessage 'ScriptMutationSlotIdle'
    }

    It 'returns nothing while the job runs and keeps the slot busy' {
        $slot=& $newSlot
        & $submit $slot
        Receive-QuietScriptsMutationJob -Slot $slot -Now $slot.Job.Started.AddSeconds(59)|Should -BeNullOrEmpty
        $slot.Job|Should -Not -BeNullOrEmpty
        $slot.Jobs|Should -Be 0
        $slot.Process.Killed.Count|Should -Be 0
    }

    It 'returns the saved result, frees the slot and deletes the job files' {
        $slot=& $newSlot
        & $submit $slot
        & $writeResult $slot '{"Sequence":1,"State":"Failed","Passed":4,"Failed":1,"Seconds":2.5,"Error":null}'
        $outcome=Receive-QuietScriptsMutationJob -Slot $slot
        $outcome.State|Should -BeExactly 'Failed'
        $outcome.Passed|Should -Be 4
        $outcome.Failed|Should -Be 1
        $outcome.Seconds|Should -Be 2.5
        $outcome.TimedOut|Should -BeFalse
        $slot.Job|Should -BeNullOrEmpty
        $slot.Jobs|Should -Be 1
        $slot.Alive|Should -BeTrue
        @(& $files $slot).Count|Should -Be 0
    }

    It 'prefers a saved result over an exited worker and a passed deadline' {
        $slot=& $newSlot (& $newProcess -HasExited $true -ExitCode 3)
        & $submit $slot
        & $writeResult $slot '{"Sequence":1,"State":"Success","Passed":2,"Failed":0,"Seconds":1,"Error":null}'
        $outcome=Receive-QuietScriptsMutationJob -Slot $slot -Now $slot.Job.Deadline.AddSeconds(5)
        $outcome.State|Should -BeExactly 'Success'
        $slot.Process.Killed.Count|Should -Be 0
        $slot.Alive|Should -BeTrue
    }

    It 'reports a crash and kills the slot on <Case>' -ForEach @(
        @{Case='another sequence';Text='{"Sequence":2,"State":"Success","Passed":2,"Failed":0,"Seconds":1}'}
        @{Case='invalid JSON';Text='{"Sequence":'}
        @{Case='a JSON null';Text='null'}
    ) {
        $slot=& $newSlot
        & $submit $slot
        & $writeResult $slot $Text
        $outcome=Receive-QuietScriptsMutationJob -Slot $slot
        $outcome.State|Should -BeExactly 'Crash'
        $outcome.Error|Should -BeExactly 'ScriptMutationSlotResultInvalid'
        $outcome.TimedOut|Should -BeFalse
        $slot.Alive|Should -BeFalse
        $slot.Job|Should -BeNullOrEmpty
        @(& $files $slot).Count|Should -Be 0
    }

    It 'rejects a result that is not valid UTF-8' {
        $slot=& $newSlot
        & $submit $slot
        $bytes=[Text.Encoding]::UTF8.GetBytes('{"Sequence":1,"State":"Success","Passed":2,"Failed":0,"Seconds":1,"Error":"#"}')
        $bytes[[Array]::IndexOf($bytes,[byte][char]'#')]=0xFF
        [IO.File]::WriteAllBytes([IO.Path]::Combine($slot.Directory,'result-1.json'),$bytes)
        (Receive-QuietScriptsMutationJob -Slot $slot).Error|Should -BeExactly 'ScriptMutationSlotResultInvalid'
        $slot.Alive|Should -BeFalse
    }

    It 'reports a crash without failing when the slot directory is gone' {
        $slot=& $newSlot (& $newProcess -HasExited $true -ExitCode 2)
        & $submit $slot
        [IO.Directory]::Delete($slot.Directory,$true)
        (Receive-QuietScriptsMutationJob -Slot $slot).Error|Should -BeExactly 'ScriptMutationSlotExited: 2'
        $slot.Job|Should -BeNullOrEmpty
    }

    It 'reports a crash with the exit code when the worker exited without a result' {
        $slot=& $newSlot (& $newProcess -HasExited $true -ExitCode 7)
        & $submit $slot
        $outcome=Receive-QuietScriptsMutationJob -Slot $slot -Now $slot.Job.Started.AddSeconds(3)
        $outcome.State|Should -BeExactly 'Crash'
        $outcome.Error|Should -BeExactly 'ScriptMutationSlotExited: 7'
        $outcome.Seconds|Should -Be 3
        $outcome.TimedOut|Should -BeFalse
        $slot.Alive|Should -BeFalse
        $slot.Jobs|Should -Be 1
    }

    It 'kills the worker tree at the deadline and reports a timeout' {
        $slot=& $newSlot
        & $submit $slot -Timeout 30
        $outcome=Receive-QuietScriptsMutationJob -Slot $slot -Now $slot.Job.Deadline
        $outcome.State|Should -BeExactly 'Timeout'
        $outcome.TimedOut|Should -BeTrue
        $outcome.Error|Should -BeExactly 'ScriptMutationSlotTimeout'
        $outcome.Seconds|Should -Be 30
        $slot.Process.Killed|Should -Be @($true)
        $slot.Process.Waits|Should -Be 1
        $slot.Alive|Should -BeFalse
        & $files $slot|Should -Not -Contain 'job-1.json'
    }
}

Describe 'Wait-QuietScriptsMutationJob' {
    It 'returns the outcome once it is available' {
        $slot=& $newSlot
        & $submit $slot
        & $writeResult $slot '{"Sequence":1,"State":"Success","Passed":1,"Failed":0,"Seconds":0.1}'
        (Wait-QuietScriptsMutationJob -Slot $slot -PollMilliseconds 1).State|Should -BeExactly 'Success'
    }

    It 'keeps polling while the job runs' {
        # The worker reports running on the first check and exited on the next.
        $process=[pscustomobject]@{Reads=0;ExitCode=4}
        $process|Add-Member -MemberType ScriptProperty -Name HasExited -Value {$this.Reads++;$this.Reads -ge 2}
        $slot=& $newSlot $process
        & $submit $slot
        (Wait-QuietScriptsMutationJob -Slot $slot -PollMilliseconds 1).Error|Should -BeExactly 'ScriptMutationSlotExited: 4'
        $process.Reads|Should -Be 2
    }

    It 'returns a crash once the worker exits' {
        $slot=& $newSlot (& $newProcess -HasExited $true -ExitCode 1)
        & $submit $slot
        (Wait-QuietScriptsMutationJob -Slot $slot -PollMilliseconds 1).State|Should -BeExactly 'Crash'
    }
}

Describe 'Stop-QuietScriptsMutationSlot' {
    It 'asks a running worker to stop and does not kill it when it exits in time' {
        $slot=& $newSlot
        Stop-QuietScriptsMutationSlot -Slot $slot -GraceMilliseconds 10
        [IO.File]::Exists([IO.Path]::Combine($slot.Directory,'stop'))|Should -BeTrue
        $slot.Process.Killed.Count|Should -Be 0
        $slot.Alive|Should -BeFalse
        $slot.Process.Disposed|Should -BeTrue
    }

    It 'kills a worker that ignores the stop request' {
        $slot=& $newSlot (& $newProcess -Exits $false)
        Stop-QuietScriptsMutationSlot -Slot $slot -GraceMilliseconds 10
        $slot.Process.Killed|Should -Be @($true)
        $slot.Alive|Should -BeFalse
    }

    It 'only releases an exited worker' {
        $slot=& $newSlot (& $newProcess -HasExited $true)
        Stop-QuietScriptsMutationSlot -Slot $slot
        [IO.File]::Exists([IO.Path]::Combine($slot.Directory,'stop'))|Should -BeFalse
        $slot.Process.Waits|Should -Be 0
        $slot.Process.Disposed|Should -BeTrue
    }

    It 'tolerates a deleted control directory' {
        $slot=& $newSlot
        [IO.Directory]::Delete($slot.Directory,$true)
        Stop-QuietScriptsMutationSlot -Slot $slot -GraceMilliseconds 10
        $slot.Alive|Should -BeFalse
    }
}

Describe 'Start-QuietScriptsMutationSlot' {
    It 'refuses an existing control directory' {
        $directory=[IO.Path]::Combine($TestDrive,'existing');[void][IO.Directory]::CreateDirectory($directory)
        {Start-QuietScriptsMutationSlot -Index 0 -Directory $directory -ScriptsRoot 's' -TestsRoot 't' -WorkspaceRoot 'w' -PesterModulePath 'p'}|Should -Throw -ExpectedMessage 'ScriptMutationSlotDirectoryExists'
        @([IO.Directory]::GetFileSystemEntries($directory)).Count|Should -Be 0
    }
}

Describe 'Get-QuietScriptsMutationSlotState and Restore-QuietScriptsMutationSlotState' {
    BeforeEach {
        $location=(Get-Location).ProviderPath
        $environmentBefore=[Environment]::GetEnvironmentVariable('QUIETCLI_SLOT_TEST_CHANGED')
        [Environment]::SetEnvironmentVariable('QUIETCLI_SLOT_TEST_CHANGED','before')
    }
    AfterEach {
        Set-Location -LiteralPath $location
        # [NullString]::Value deletes a variable; $null would leave it set to the empty string.
        [Environment]::SetEnvironmentVariable('QUIETCLI_SLOT_TEST_CHANGED',$(if($null -eq $environmentBefore){[NullString]::Value}else{$environmentBefore}))
        [Environment]::SetEnvironmentVariable('QUIETCLI_SLOT_TEST_ADDED',[NullString]::Value)
        Remove-Variable -Name QuietSlotTestAdded,QuietSlotTestKept -Scope Global -Force -ErrorAction SilentlyContinue
        Get-Module QuietSlotTestUnder,QuietSlotTestOutside -All|Remove-Module -Force
    }

    It 'undoes environment, global variable and location changes, and unloads only the modules under the roots' {
        $root=[IO.Path]::Combine($TestDrive,'roots-'+[guid]::NewGuid().ToString('N'))
        $under=New-QuietTestFile ([IO.Path]::Combine($root,'scripts','lib','QuietSlotTestUnder.psm1')) 'function Get-QuietSlotUnder { 1 }'
        $outside=New-QuietTestFile ([IO.Path]::Combine($root,'other','QuietSlotTestOutside.psm1')) 'function Get-QuietSlotOutside { 1 }'
        $sibling=[IO.Path]::Combine($root,'scripts-copy');[void][IO.Directory]::CreateDirectory($sibling)
        Set-Variable -Name QuietSlotTestKept -Scope Global -Value 1
        $state=Get-QuietScriptsMutationSlotState
        [Environment]::SetEnvironmentVariable('QUIETCLI_SLOT_TEST_ADDED','x')
        [Environment]::SetEnvironmentVariable('QUIETCLI_SLOT_TEST_CHANGED','after')
        Set-Variable -Name QuietSlotTestAdded -Scope Global -Value 2
        Set-Variable -Name QuietSlotTestKept -Scope Global -Value 3
        Set-Location -LiteralPath $sibling
        Import-Module $under -Global -DisableNameChecking -ErrorAction Stop
        Import-Module $outside -Global -DisableNameChecking -ErrorAction Stop
        $removed=Restore-QuietScriptsMutationSlotState -State $state -Roots @([IO.Path]::Combine($root,'scripts'))
        $removed|Should -Be 1
        [Environment]::GetEnvironmentVariables().Contains('QUIETCLI_SLOT_TEST_ADDED')|Should -BeFalse -Because 'an added variable is deleted, not set to the empty string'
        [Environment]::GetEnvironmentVariable('QUIETCLI_SLOT_TEST_CHANGED')|Should -BeExactly 'before'
        Get-Variable -Name QuietSlotTestAdded -Scope Global -ErrorAction SilentlyContinue|Should -BeNullOrEmpty
        (Get-Variable -Name QuietSlotTestKept -Scope Global).Value|Should -Be 3 -Because 'pre-existing globals are kept; tests must not rely on their values'
        (Get-Location).ProviderPath|Should -BeExactly $state.Location
        [Environment]::CurrentDirectory|Should -BeExactly $state.Location
        Get-Module QuietSlotTestUnder -All|Should -BeNullOrEmpty
        Get-Module QuietSlotTestOutside -All|Should -Not -BeNullOrEmpty
    }

    It 'does not treat a sibling directory sharing the root prefix as under the root' {
        $root=[IO.Path]::Combine($TestDrive,'prefix-'+[guid]::NewGuid().ToString('N'))
        $module=New-QuietTestFile ([IO.Path]::Combine($root,'scripts-copy','QuietSlotTestOutside.psm1')) 'function Get-QuietSlotOutside { 1 }'
        $state=Get-QuietScriptsMutationSlotState
        Import-Module $module -Global -DisableNameChecking -ErrorAction Stop
        Restore-QuietScriptsMutationSlotState -State $state -Roots @([IO.Path]::Combine($root,'scripts')+[IO.Path]::DirectorySeparatorChar)|Should -Be 0
        Get-Module QuietSlotTestOutside -All|Should -Not -BeNullOrEmpty
    }

    It 'compares the roots case-insensitively on Windows only' {
        $root=[IO.Path]::Combine($TestDrive,'case-'+[guid]::NewGuid().ToString('N'))
        $module=New-QuietTestFile ([IO.Path]::Combine($root,'scripts','QuietSlotTestUnder.psm1')) 'function Get-QuietSlotUnder { 1 }'
        $state=Get-QuietScriptsMutationSlotState
        Import-Module $module -Global -DisableNameChecking -ErrorAction Stop
        Restore-QuietScriptsMutationSlotState -State $state -Roots @([IO.Path]::Combine($root.ToUpperInvariant(),'SCRIPTS'))|Should -Be $(if($IsWindows){1}else{0})
        [bool](Get-Module QuietSlotTestUnder -All)|Should -Be (!$IsWindows)
    }

    It 'leaves read-only globals in place' {
        $state=Get-QuietScriptsMutationSlotState
        Set-Variable -Name QuietSlotTestAdded -Scope Global -Value 1 -Option ReadOnly
        $null=Restore-QuietScriptsMutationSlotState -State $state -Roots @($TestDrive)
        (Get-Variable -Name QuietSlotTestAdded -Scope Global).Value|Should -Be 1
    }
}

Describe 'Invoke-QuietScriptsMutationSlotJob' {
    # The job exports the run variables into the current process: put them back for the other test files.
    BeforeEach {$saved=@{};foreach($name in 'QUIETCLI_TEST_SEED','QUIETCLI_SCRIPTS_ROOT','QUIETCLI_WORKSPACE_ROOT'){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}}
    AfterEach {foreach($entry in $saved.GetEnumerator()){[Environment]::SetEnvironmentVariable($entry.Key,$(if($null -eq $entry.Value){[NullString]::Value}else{$entry.Value}))}}

    It 'reports a corrupted worker without running anything when Pester is <Case>' -ForEach @(
        @{Case='unloaded';Loaded=@()}
        @{Case='another version';Loaded=@([pscustomobject]@{Name='Pester';Version=[version]'5.7.1'})}
        @{Case='loaded twice';Loaded=@([pscustomobject]@{Name='Pester';Version=[version]'6.2.0'},[pscustomobject]@{Name='Pester';Version=[version]'6.2.0'})}
    ) {
        # No Mock -ModuleName here: inside a slot worker the engine's own ScriptMutationSlot module is loaded too.
        # The tests root does not exist, so a run that planned anything would end as Crash, not Corrupted.
        $root=[IO.Path]::Combine($TestDrive,'job-'+[guid]::NewGuid().ToString('N'))
        $state=Get-QuietScriptsMutationSlotState
        $result=Invoke-QuietScriptsMutationSlotJob -Request @{ScriptsRoot=[IO.Path]::Combine($root,'s');TestsRoot=[IO.Path]::Combine($root,'t');WorkspaceRoot=$root;Directory=$root;Seed=1} -Job @{Sequence=4;UnitTestFiles=@('unit/A.Tests.ps1');Bail=$false} -State $state -Scope (New-Module -ScriptBlock {}) -PesterModules $Loaded
        $result.State|Should -BeExactly 'Corrupted' -Because $result.Error
        $result.Sequence|Should -Be 4
        $result.Passed|Should -Be 0
        $result.Failed|Should -Be 0
        $result.Seconds|Should -Be 0
        $result.Error|Should -BeExactly 'ScriptMutationSlotCorrupted: Pester'
        [IO.Directory]::Exists($root)|Should -BeFalse -Because 'nothing is planned or written for a corrupted worker'
    }

    It 'reads the loaded Pester from the session when none is passed' {
        $root=[IO.Path]::Combine($TestDrive,'job-'+[guid]::NewGuid().ToString('N'))
        $result=Invoke-QuietScriptsMutationSlotJob -Request @{ScriptsRoot=[IO.Path]::Combine($root,'s');TestsRoot=[IO.Path]::Combine($root,'t');WorkspaceRoot=$root;Directory=$root;Seed=1} -Job @{Sequence=5;UnitTestFiles=@('unit/A.Tests.ps1');Bail=$false} -State (Get-QuietScriptsMutationSlotState) -Scope (New-Module -ScriptBlock {})
        $result.State|Should -BeExactly 'Crash' -Because 'this session holds exactly the pinned Pester, so the job goes on to plan the missing tests root'
        $result.Error|Should -Not -Match 'ScriptMutationSlotCorrupted'
    }
}

Describe 'Test-QuietScriptsMutationSlotPester' {
    It 'accepts exactly one pinned Pester and rejects <Case>' -ForEach @(
        @{Case='nothing';Modules=@();Expected=$false}
        @{Case='another version';Modules=@([pscustomobject]@{Version=[version]'5.7.1'});Expected=$false}
        @{Case='a newer version';Modules=@([pscustomobject]@{Version=[version]'6.2.1'});Expected=$false}
        @{Case='two copies';Modules=@([pscustomobject]@{Version=[version]'6.2.0'},[pscustomobject]@{Version=[version]'6.2.0'});Expected=$false}
        @{Case='no rejection for the pinned version';Modules=@([pscustomobject]@{Version=[version]'6.2.0'});Expected=$true}
    ) {
        $actual=Test-QuietScriptsMutationSlotPester -Modules $Modules
        $actual|Should -BeOfType [bool]
        $actual|Should -Be $Expected
    }

    It 'holds for the Pester running this test' {
        Test-QuietScriptsMutationSlotPester -Modules @(Get-Module Pester)|Should -BeTrue
    }
}

Describe 'Test-QuietScriptsMutationSlotParent' {
    BeforeAll {$recorded=[datetime]::new(2026,1,2,3,4,5,[DateTimeKind]::Utc)}

    It 'is <Expected> for <Case>' -ForEach @(
        @{Case='no process';Process=$null;Offset=0;Expected=$false}
        @{Case='an exited parent';Process=@{HasExited=$true};Offset=0;Expected=$false}
        @{Case='the exact start time';Process=@{HasExited=$false};Offset=0;Expected=$true}
        @{Case='a few milliseconds of Linux drift later';Process=@{HasExited=$false};Offset=27464;Expected=$true}
        @{Case='a few milliseconds of Linux drift earlier';Process=@{HasExited=$false};Offset=-27464;Expected=$true}
        @{Case='exactly one second later';Process=@{HasExited=$false};Offset=10000000;Expected=$true}
        @{Case='just over one second later';Process=@{HasExited=$false};Offset=10000001;Expected=$false}
        @{Case='just over one second earlier';Process=@{HasExited=$false};Offset=-10000001;Expected=$false}
    ) {
        $double=if($null -eq $Process){$null}else{[pscustomobject]@{HasExited=$Process.HasExited;StartTime=$recorded.AddTicks($Offset)}}
        $actual=Test-QuietScriptsMutationSlotParent -Process $double -StartTicks $recorded.Ticks
        $actual|Should -BeOfType [bool]
        $actual|Should -Be $Expected
    }

    It 'compares in UTC whatever the kind of the start time' {
        $double=[pscustomobject]@{HasExited=$false;StartTime=$recorded.AddHours(3).ToLocalTime()}
        Test-QuietScriptsMutationSlotParent -Process $double -StartTicks $recorded.Ticks|Should -BeFalse
        $double.StartTime=$recorded.ToLocalTime()
        Test-QuietScriptsMutationSlotParent -Process $double -StartTicks $recorded.Ticks|Should -BeTrue
    }

    It 'holds for the running process, seen again through its id' {
        $current=[Diagnostics.Process]::GetCurrentProcess()
        $again=[Diagnostics.Process]::GetProcessById($current.Id)
        try{Test-QuietScriptsMutationSlotParent -Process $again -StartTicks $current.StartTime.ToUniversalTime().Ticks|Should -BeTrue}finally{$again.Dispose()}
    }
}

Describe 'Invoke-QuietScriptsMutationSlotJob on a run that cannot start' {
    # The job exports the run variables into the current process: put them back for the other test files.
    BeforeEach {$saved=@{};foreach($name in 'QUIETCLI_TEST_SEED','QUIETCLI_SCRIPTS_ROOT','QUIETCLI_WORKSPACE_ROOT'){$saved[$name]=[Environment]::GetEnvironmentVariable($name)}}
    AfterEach {foreach($entry in $saved.GetEnumerator()){[Environment]::SetEnvironmentVariable($entry.Key,$(if($null -eq $entry.Value){[NullString]::Value}else{$entry.Value}))}}

    It 'reports a crash, counted as one failure, when the run cannot start' {
        $root=[IO.Path]::Combine($TestDrive,'job-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory([IO.Path]::Combine($root,'t','unit'))
        $state=Get-QuietScriptsMutationSlotState
        $result=Invoke-QuietScriptsMutationSlotJob -Request @{ScriptsRoot=[IO.Path]::Combine($root,'s');TestsRoot=[IO.Path]::Combine($root,'t');WorkspaceRoot=$root;Directory=$root;Seed=1} -Job @{Sequence=2;UnitTestFiles=@('unit/Missing.Tests.ps1');Bail=$true} -State $state -Scope (New-Module -ScriptBlock {})
        $result.State|Should -BeExactly 'Crash'
        $result.Failed|Should -Be 1
        $result.Sequence|Should -Be 2
        $result.Error|Should -Not -BeNullOrEmpty
    }
}