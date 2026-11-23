#requires -Version 7.6
# Real slot workers: one hidden pwsh per slot running the pinned Pester, driven through the file job protocol.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptMutationSlot
    $repository=Get-QuietTestWorkspaceRoot
    $pester=[IO.Path]::Combine($repository,'.cache','test-tools','Pester','Pester.psd1')
    $available=[IO.File]::Exists($pester)
    $import="BeforeAll { Import-Module ([IO.Path]::Combine(`$env:QUIETCLI_SCRIPTS_ROOT,'lib','Value.psm1')) -Force -DisableNameChecking -ErrorAction Stop }`n"
    $tests=@{
        'unit/Value.Tests.ps1'=$import+"Describe 'Get-Value' { It 'is one' { Get-Value | Should -Be 1 } }`n"
        'unit/Many.Tests.ps1'=$import+"Describe 'Get-Value' { It 'first <N>' -ForEach @(@{N=1},@{N=2},@{N=3}) { Get-Value | Should -Be 1 } }`n"
        # Leaves state behind and fails if a previous run's state is still there.
        'unit/Leak.Tests.ps1'="Describe 'state' { It 'starts clean' { `$Global:QuietSlotLeak | Should -BeNullOrEmpty; `$env:QUIETCLI_SLOT_LEAK | Should -BeNullOrEmpty; `$Global:QuietSlotLeak=1; `$env:QUIETCLI_SLOT_LEAK='1' } }`n"
        'unit/Seed.Tests.ps1'="Describe 'seed' { It 'is exported' { `$env:QUIETCLI_TEST_SEED | Should -BeExactly '31' } }`n"
        'unit/Unload.Tests.ps1'="Describe 'sabotage' { It 'passes' { 1 | Should -Be 1 } }`nAfterAll { Remove-Module Pester -Force }`n"
        'unit/Phases.Tests.ps1'=$import+"Describe 'one' { It 'is constant' { 1 | Should -Be 1 } }`nDescribe 'two' { It 'value <N>' -ForEach @(@{N=1},@{N=2}) { Get-Value | Should -Be 1 } }`nDescribe 'three' { It 'is constant' { 3 | Should -Be 3 } }`n"
        'unit/Slow.Tests.ps1'="Describe 'slow' { It 'sleeps' { Start-Sleep -Seconds 120 } }`n"
    }
    $newSlot={
        $root=[IO.Path]::Combine($TestDrive,'slot-'+[guid]::NewGuid().ToString('N'))
        $scripts=[IO.Path]::Combine($root,'scripts');$testsRoot=[IO.Path]::Combine($root,'tests')
        $null=New-QuietTestFile ([IO.Path]::Combine($scripts,'lib','Value.psm1')) "function Get-Value { 1 }`nExport-ModuleMember -Function Get-Value`n"
        foreach($entry in $tests.GetEnumerator()){$null=New-QuietTestFile ([IO.Path]::Combine($testsRoot,$entry.Key)) $entry.Value}
        Start-QuietScriptsMutationSlot -Index 0 -Directory ([IO.Path]::Combine($root,'control')) -ScriptsRoot $scripts -TestsRoot $testsRoot -WorkspaceRoot $repository -PesterModulePath $pester -Seed 31
    }
    $runJob={param($Slot,[string[]]$Files,[switch]$Bail,[int]$Timeout=120,[object[]]$Phases=@())
        Submit-QuietScriptsMutationJob -Slot $Slot -Name 'job' -UnitTestFiles $Files -Bail:$Bail -Phases $Phases -TimeoutSeconds $Timeout
        Wait-QuietScriptsMutationJob -Slot $Slot
    }
    $diagnosis={param($Slot)
        # The live worker holds its logs open, so they are read with shared access.
        foreach($name in 'worker.stdout.log','worker.stderr.log'){
            $path=[IO.Path]::Combine($Slot.Directory,$name)
            if(![IO.File]::Exists($path)){continue}
            $stream=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            try{"$name`: "+[IO.StreamReader]::new($stream).ReadToEnd()}finally{$stream.Dispose()}
        }
    }
}

Describe 'Persistent mutation slot worker (Start-QuietScriptsMutationSlot, Invoke-QuietScriptsMutationSlotWorker, Invoke-QuietScriptsMutationSlotJob)' {
    BeforeEach {
        if(!$available){Set-ItResult -Skipped -Because 'the pinned Pester is not cached (run Initialize-TestTools.ps1)'}
        $slot=$null
    }
    AfterEach {
        if($null -ne $slot){Stop-QuietScriptsMutationSlot -Slot $slot}
    }

    It 'runs several jobs in one process, reloads an edited library and resets the state between runs' {
        $slot=& $newSlot
        $processId=$slot.Process.Id
        $first=& $runJob $slot @('unit/Value.Tests.ps1')
        $first.State|Should -BeExactly 'Success' -Because ((& $diagnosis $slot) -join "`n")
        $first.Passed|Should -Be 1
        $library=[IO.Path]::Combine($slot.ScriptsRoot,'lib','Value.psm1')
        [IO.File]::WriteAllText($library,"function Get-Value { 2 }`nExport-ModuleMember -Function Get-Value`n")
        $mutated=& $runJob $slot @('unit/Value.Tests.ps1')
        $mutated.State|Should -BeExactly 'Failed' -Because 'the mutated library must be re-imported, not reused'
        $mutated.Failed|Should -Be 1
        [IO.File]::WriteAllText($library,"function Get-Value { 1 }`nExport-ModuleMember -Function Get-Value`n")
        foreach($round in 1..2){
            $leak=& $runJob $slot @('unit/Leak.Tests.ps1','unit/Seed.Tests.ps1')
            $leak.State|Should -BeExactly 'Success' -Because "round $round must start from the captured state"
            $leak.Passed|Should -Be 2
        }
        (& $runJob $slot @('unit/Value.Tests.ps1')).State|Should -BeExactly 'Success'
        $slot.Jobs|Should -Be 5
        $slot.Process.Id|Should -Be $processId
        $slot.Process.HasExited|Should -BeFalse
        $slot.Alive|Should -BeTrue
    }

    It 'runs the same sequence after Windows releases the job file' -Skip:(-not $IsWindows) {
        $slot=& $newSlot
        $files=@('unit/Value.Tests.ps1')
        (& $runJob $slot $files).State|Should -BeExactly 'Success'
        $processId=$slot.Process.Id
        $sequence=$slot.Sequence+1
        $path=[IO.Path]::Combine($slot.Directory,"job-$sequence.json")
        $payload=@{Sequence=$sequence;Name='locked job fixture';UnitTestFiles=$files;Bail=$false;Phases=@()}|ConvertTo-Json -Compress
        $bytes=[Text.Encoding]::UTF8.GetBytes($payload)
        $lock=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{
            $lock.Write($bytes,0,$bytes.Length)
            $lock.Flush()
            $slot.Process.WaitForExit(1000)|Should -BeFalse -Because ((& $diagnosis $slot) -join "`n")
        }finally{$lock.Dispose()}

        $now=[DateTimeOffset]::UtcNow
        $slot.Sequence=$sequence
        $slot.Job=[pscustomobject]@{Sequence=$sequence;Name='locked job fixture';Started=$now;Deadline=$now.AddSeconds(60)}
        $result=Wait-QuietScriptsMutationJob -Slot $slot
        $result.State|Should -BeExactly 'Success' -Because ((& $diagnosis $slot) -join "`n")
        $result.Passed|Should -Be 1
        $slot.Process.Id|Should -Be $processId
        $slot.Jobs|Should -Be 2
    }

    It 'stops a mutant run at its first failure with bail, and runs every test without it' {
        $slot=& $newSlot
        [IO.File]::WriteAllText([IO.Path]::Combine($slot.ScriptsRoot,'lib','Value.psm1'),"function Get-Value { 2 }`nExport-ModuleMember -Function Get-Value`n")
        $full=& $runJob $slot @('unit/Many.Tests.ps1')
        $full.Failed|Should -Be 3 -Because ((& $diagnosis $slot) -join "`n")
        $bailed=& $runJob $slot @('unit/Many.Tests.ps1') -Bail
        $bailed.State|Should -BeExactly 'Failed'
        $bailed.Failed|Should -Be 1
        $bailed.Passed|Should -Be 0
    }

    It 'runs the phases one after the other and adds up their counts' {
        $slot=& $newSlot
        $split=& $runJob $slot @('unit/Phases.Tests.ps1') -Phases @(@('two'),@('one','three'))
        $split.State|Should -BeExactly 'Success' -Because ((& $diagnosis $slot) -join "`n")
        $split.Passed|Should -Be 4
        $split.Failed|Should -Be 0
        $full=& $runJob $slot @('unit/Phases.Tests.ps1')
        $full.Passed|Should -Be $split.Passed -Because 'the phases select every test once'
    }

    It 'skips the next phases after a failing one with bail, and runs them all without it' {
        $slot=& $newSlot
        [IO.File]::WriteAllText([IO.Path]::Combine($slot.ScriptsRoot,'lib','Value.psm1'),"function Get-Value { 2 }`nExport-ModuleMember -Function Get-Value`n")
        $bailed=& $runJob $slot @('unit/Phases.Tests.ps1') -Bail -Phases @(@('two'),@('one','three'))
        $bailed.State|Should -BeExactly 'Failed' -Because ((& $diagnosis $slot) -join "`n")
        $bailed.Failed|Should -Be 1
        $bailed.Passed|Should -Be 0
        $all=& $runJob $slot @('unit/Phases.Tests.ps1') -Phases @(@('one'),@('two'),@('three'))
        $all.State|Should -BeExactly 'Failed'
        $all.Failed|Should -Be 2
        $all.Passed|Should -Be 2 -Because 'the phase after the failing one still runs'
    }

    It 'fails a phase that selects no test instead of passing it' {
        $slot=& $newSlot
        $empty=& $runJob $slot @('unit/Phases.Tests.ps1') -Phases @(@('one'),@('missing'))
        $empty.State|Should -BeExactly 'Failed' -Because ((& $diagnosis $slot) -join "`n")
        $empty.Passed|Should -Be 1
    }

    It 'reports a crash for an unloadable test plan and keeps serving jobs' {
        $slot=& $newSlot
        $broken=& $runJob $slot @('unit/Missing.Tests.ps1')
        $broken.State|Should -BeExactly 'Crash'
        $broken.Error|Should -Not -BeNullOrEmpty
        (& $runJob $slot @('unit/Value.Tests.ps1')).State|Should -BeExactly 'Success' -Because ((& $diagnosis $slot) -join "`n")
    }

    It 'reports the next job as corrupted after a run unloads Pester' {
        $slot=& $newSlot
        $null=& $runJob $slot @('unit/Unload.Tests.ps1')
        $next=& $runJob $slot @('unit/Value.Tests.ps1')
        $next.State|Should -BeExactly 'Corrupted' -Because ((& $diagnosis $slot) -join "`n")
        $next.Error|Should -BeExactly 'ScriptMutationSlotCorrupted: Pester'
    }

    It 'kills a run past its deadline and marks the slot dead' {
        $slot=& $newSlot
        $outcome=& $runJob $slot @('unit/Slow.Tests.ps1') -Timeout 5
        $outcome.State|Should -BeExactly 'Timeout'
        $outcome.TimedOut|Should -BeTrue
        $slot.Alive|Should -BeFalse
        $slot.Process.HasExited|Should -BeTrue
        {& $runJob $slot @('unit/Value.Tests.ps1')}|Should -Throw -ExpectedMessage 'ScriptMutationSlotDead'
    }

    It 'exits cleanly on stop' {
        $slot=& $newSlot
        $null=& $runJob $slot @('unit/Value.Tests.ps1')
        $processId=$slot.Process.Id
        $watch=[Diagnostics.Stopwatch]::StartNew()
        Stop-QuietScriptsMutationSlot -Slot $slot -GraceMilliseconds 10000
        $watch.Elapsed.TotalSeconds|Should -BeLessThan 10 -Because 'the worker polls for the stop file'
        Get-Process -Id $processId -ErrorAction SilentlyContinue|Should -BeNullOrEmpty
        $slot.Alive|Should -BeFalse
        $slot=$null
    }
}
