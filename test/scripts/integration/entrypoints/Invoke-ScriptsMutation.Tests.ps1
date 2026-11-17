#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Invoke-ScriptsMutation.ps1')
    $repository=Get-QuietTestWorkspaceRoot
    $available=[IO.File]::Exists([IO.Path]::Combine($repository,'.cache','test-tools','Pester','Pester.psd1'))
    $library=@'
function Get-Sign {
    param([int]$Value)
    if($Value -gt 0){return 'positive'}
    if($Value -lt 0){return 'negative'}
    'zero'
}
Export-ModuleMember -Function Get-Sign
'@
    $import="BeforeAll { Import-Module ([IO.Path]::Combine(`$env:QUIETCLI_SCRIPTS_ROOT,'lib','Sign.psm1')) -Force -DisableNameChecking -ErrorAction Stop }`n"
    $strong=$import+"Describe 'Get-Sign' { It 'classifies <Value>' -ForEach @(@{Value=1;Expected='positive'},@{Value=7;Expected='positive'},@{Value=0;Expected='zero'},@{Value=-1;Expected='negative'},@{Value=-7;Expected='negative'}) { Get-Sign `$Value | Should -BeExactly `$Expected } }`n"
    $weak=$import+"Describe 'Get-Sign' { It 'classifies 5' { Get-Sign 5 | Should -BeExactly 'positive' } }`n"
    $failing=$import+"Describe 'Get-Sign' { It 'is wrong' { Get-Sign 5 | Should -BeExactly 'zero' } }`n"
    $target={param([string]$Name,[string]$Test,[int]$Break=100)"@{Name='$Name';Module='lib/Sign.psm1';Functions=@('Get-Sign');UnitTestFiles=@('unit/$Test');Break=$Break}"}
    $newWorkspace={param([string[]]$Targets)
        $root=[IO.Path]::Combine($TestDrive,'ws-'+[guid]::NewGuid().ToString('N'))
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'scripts','lib','Sign.psm1')) $library
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'tests','unit','Strong.Tests.ps1')) $strong
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'tests','unit','Weak.Tests.ps1')) $weak
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'tests','unit','Failing.Tests.ps1')) $failing
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'tests','mutation.targets.psd1')) ("@{Targets=@($($Targets -join ';'))}")
        $root
    }
    # The cache always lives under the fixture workspace, so a test never reads or writes the repository cache.
    $run={param([string]$Workspace,[string[]]$Arguments=@(),[string]$RunName='run')
        $runDirectory=[IO.Path]::Combine($Workspace,$RunName)
        $outcome=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$repository,'-ScriptsRoot',[IO.Path]::Combine($Workspace,'scripts'),'-TestsRoot',[IO.Path]::Combine($Workspace,'tests'),'-RunDirectory',$runDirectory,'-CacheDirectory',[IO.Path]::Combine($Workspace,'cache'),'-Headless','-Offline','-Seed','4242','-ThrottleLimit','4')+$Arguments) -TimeoutSeconds 900
        $reportPath=[IO.Path]::Combine($runDirectory,'report.json')
        $outcome|Add-Member -NotePropertyName RunDirectory -NotePropertyValue $runDirectory
        $outcome|Add-Member -NotePropertyName Report -NotePropertyValue $(if([IO.File]::Exists($reportPath)){Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json}else{$null})
        $outcome
    }
}

Describe 'Invoke-ScriptsMutation.ps1' {
    BeforeEach {
        if(!$available){Set-ItResult -Skipped -Because 'the pinned Pester is not cached (run Initialize-TestTools.ps1)'}
    }

    It 'kills every mutant with a strong test and reports the survivors of a weak one' {
        $workspace=& $newWorkspace @((& $target 'Strong' 'Strong.Tests.ps1'),(& $target 'Weak' 'Weak.Tests.ps1'))
        $outcome=& $run $workspace
        $outcome.ExitCode|Should -Be 1 -Because 'the weak target is below its break'
        $outcome.Report|Should -Not -BeNullOrEmpty -Because ($outcome.Output+$outcome.Error)
        $strongReport=@($outcome.Report.Targets|Where-Object Name -CEQ 'Strong')[0]
        $weakReport=@($outcome.Report.Targets|Where-Object Name -CEQ 'Weak')[0]
        $strongReport.Mutants|Should -BeGreaterThan 10
        $strongReport.Score|Should -Be 100
        $strongReport.Survived|Should -Be 0
        $strongReport.Passed|Should -BeTrue
        $weakReport.Mutants|Should -Be $strongReport.Mutants
        $weakReport.Survived|Should -BeGreaterThan 0
        $weakReport.Score|Should -BeLessThan 100
        $weakReport.Passed|Should -BeFalse
        @($weakReport.Survivors).Count|Should -Be $weakReport.Survived
        $outcome.Report.Seed|Should -Be 4242
        $outcome.Report.Passed|Should -BeFalse
        $markdown=[IO.File]::ReadAllText([IO.Path]::Combine($outcome.RunDirectory,'report.md'))
        $markdown|Should -Match '## Survivors: Weak'
        $markdown|Should -Match '`lib/Sign\.psm1:\d+:\d+`'
        $status=Get-Content -LiteralPath ([IO.Path]::Combine($outcome.RunDirectory,'status.json')) -Raw|ConvertFrom-Json
        $status.State|Should -BeExactly 'Failed'
        @((Get-Content -LiteralPath ([IO.Path]::Combine($outcome.RunDirectory,'mutants.json')) -Raw|ConvertFrom-Json).Mutants).Count|Should -Be ($strongReport.Mutants+$weakReport.Mutants)
        [IO.Directory]::Exists([IO.Path]::Combine($outcome.RunDirectory,'slots'))|Should -BeFalse
        [IO.File]::ReadAllText([IO.Path]::Combine($workspace,'scripts','lib','Sign.psm1'))|Should -BeExactly $library.Replace("`r`n","`n")
        [IO.Directory]::Exists([IO.Path]::Combine($outcome.RunDirectory,'mutants'))|Should -BeFalse
        $strongReport.Cached|Should -Be 0
        $outcome.Output|Should -Match 'cache=on'
    }

    It 'reuses every cached outcome on a second run, reruns an edited function, ignores the cache with -NoCache and prunes it with -PruneCache' {
        $workspace=& $newWorkspace @((& $target 'Strong' 'Strong.Tests.ps1'),(& $target 'Weak' 'Weak.Tests.ps1'))
        $first=& $run $workspace @() 'run-1'
        $first.Report|Should -Not -BeNullOrEmpty -Because ($first.Output+$first.Error)
        $second=& $run $workspace @() 'run-2'
        $second.Report|Should -Not -BeNullOrEmpty -Because ($second.Output+$second.Error)
        foreach($name in 'Strong','Weak'){
            $before=@($first.Report.Targets|Where-Object Name -CEQ $name)[0];$after=@($second.Report.Targets|Where-Object Name -CEQ $name)[0]
            $after.Cached|Should -Be ($before.Mutants-$before.CompileError) -Because "every runnable $name mutant is reused"
            $after.Score|Should -Be $before.Score
            $after.Survived|Should -Be $before.Survived
        }
        $second.Output|Should -Match 'Progress: Cached Strong'
        $second.Output|Should -Not -Match 'Progress: Baseline'
        $documents={@([IO.Directory]::EnumerateFiles([IO.Path]::Combine($workspace,'cache'),'*.json',[IO.SearchOption]::AllDirectories))}
        $baselines=@(& $documents|Where-Object {(Get-Content -LiteralPath $_ -Raw|ConvertFrom-Json).Kind -ceq 'Baseline'})
        $baselines.Count|Should -Be 2 -Because 'each target records its passing baseline once'
        # One missing outcome makes Weak run again, on the baseline this machine already proved.
        [IO.File]::Delete(@(& $documents|Where-Object {$_ -notin $baselines})[0])
        $partial=& $run $workspace @() 'run-2b'
        $partial.Report|Should -Not -BeNullOrEmpty -Because ($partial.Output+$partial.Error)
        $partial.Output|Should -Match 'Progress: Baseline (Strong|Weak) reused \| passed=[1-9]'
        $partial.Output|Should -Not -Match 'Progress: Baseline (Strong|Weak) \|'
        $fresh=& $run $workspace @('-NoCache') 'run-3'
        $fresh.Output|Should -Match 'cache=off'
        $fresh.Output|Should -Match 'Progress: Baseline Strong \|' -Because 'without the cache every baseline runs'
        @($fresh.Report.Targets|ForEach-Object Cached|Where-Object {$_ -ne 0}).Count|Should -Be 0
        $edited=$library.Replace("'zero'","'none'")
        [IO.File]::WriteAllText([IO.Path]::Combine($workspace,'scripts','lib','Sign.psm1'),$edited)
        $changed=& $run $workspace @('-Target','Weak') 'run-4'
        $changed.Report|Should -Not -BeNullOrEmpty -Because ($changed.Output+$changed.Error)
        @($changed.Report.Targets)[0].Cached|Should -Be 0 -Because 'an edit of the mutated function invalidates its mutants'
        $changed.Output|Should -Match 'Progress: Baseline Weak'
        $stale=(& $documents).Count
        # Reverting the edit makes run-4's outcomes the stale ones; the edit also breaks Strong's baseline.
        [IO.File]::WriteAllText([IO.Path]::Combine($workspace,'scripts','lib','Sign.psm1'),$library)
        $pruned=& $run $workspace @('-PruneCache') 'run-5'
        $pruned.Report|Should -Not -BeNullOrEmpty -Because ($pruned.Output+$pruned.Error)
        $pruned.Output|Should -Match 'cache=on,prune'
        $pruned.Output|Should -Match 'Cache: pruned [1-9]\d* unused documents'
        $kept=(($pruned.Report.Targets|ForEach-Object {$_.Killed+$_.Survived})|Measure-Object -Sum).Sum
        (& $documents).Count|Should -Be ($kept+@($pruned.Report.Targets).Count) -Because 'only the outcomes and the baseline of each target keyed by the current sources remain'
        (& $documents).Count|Should -BeLessThan $stale
        $again=& $run $workspace @('-PruneCache') 'run-6'
        @($again.Report.Targets|Where-Object {$_.Cached -ne $_.Killed+$_.Survived}).Count|Should -Be 0 -Because 'pruning keeps every outcome still in use'
        $again.Output|Should -Match 'Cache: pruned 0 unused documents'
    }

    It 'runs only the selected target and passes when it reaches its break' {
        $workspace=& $newWorkspace @((& $target 'Strong' 'Strong.Tests.ps1'),(& $target 'Weak' 'Weak.Tests.ps1'))
        $outcome=& $run $workspace @('-Target','Strong')
        $outcome.ExitCode|Should -Be 0 -Because ($outcome.Output+$outcome.Error)
        @($outcome.Report.Targets.Name)|Should -Be @('Strong')
        $outcome.Report.Passed|Should -BeTrue
    }

    It 'stops with ScriptMutationBaselineFailed when the unmutated tests fail' {
        $workspace=& $newWorkspace @((& $target 'Failing' 'Failing.Tests.ps1' 0))
        $outcome=& $run $workspace
        $outcome.ExitCode|Should -Be 1
        $outcome.Report|Should -BeNullOrEmpty
        $status=Get-Content -LiteralPath ([IO.Path]::Combine($outcome.RunDirectory,'status.json')) -Raw|ConvertFrom-Json
        $status.State|Should -BeExactly 'Crash'
        $status.Error|Should -Match '^ScriptMutationBaselineFailed: Failing state=Failed'
    }

    It 'rejects <Case> before creating the run directory' -ForEach @(
        @{Case='an unknown target';Targets=@("@{Name='Strong';Module='lib/Sign.psm1';Functions=@('Get-Sign');UnitTestFiles=@('unit/Strong.Tests.ps1');Break=100}");Arguments=@('-Target','Nope');Expected='ScriptMutationTargetUnknown: Nope'}
        @{Case='a missing function';Targets=@("@{Name='Strong';Module='lib/Sign.psm1';Functions=@('Get-Nothing');UnitTestFiles=@('unit/Strong.Tests.ps1');Break=100}");Arguments=@();Expected='ScriptMutationFunctionMissing: Get-Nothing'}
        @{Case='an invalid targets file';Targets=@("@{Name='Strong'}");Arguments=@();Expected='ScriptMutationTargetsInvalid: module'}
        @{Case='pruning a disabled cache';Targets=@("@{Name='Strong';Module='lib/Sign.psm1';Functions=@('Get-Sign');UnitTestFiles=@('unit/Strong.Tests.ps1');Break=100}");Arguments=@('-NoCache','-PruneCache');Expected='ScriptMutationCacheOptionsConflict'}
    ) {
        $workspace=& $newWorkspace $Targets
        $outcome=& $run $workspace $Arguments
        $outcome.ExitCode|Should -Be 1
        ($outcome.Output+$outcome.Error)|Should -Match ([regex]::Escape($Expected))
        [IO.Directory]::Exists($outcome.RunDirectory)|Should -BeFalse
    }

    It 'writes nothing with -WhatIf' {
        $workspace=& $newWorkspace @((& $target 'Strong' 'Strong.Tests.ps1'))
        $outcome=& $run $workspace @('-WhatIf')
        $outcome.ExitCode|Should -Be 0
        [IO.Directory]::Exists($outcome.RunDirectory)|Should -BeFalse
    }
}
