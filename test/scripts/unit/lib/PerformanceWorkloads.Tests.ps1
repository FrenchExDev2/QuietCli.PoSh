#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name PerformanceStatistics
    $null=Import-QuietTestLibrary -Name PerformanceWorkloads
    $seed=Get-QuietTestSeed
    # A Core suite summary as ConvertFrom-Json returns it, with every measure the catalog reads.
    $newCore={
        $human=@(foreach($state in 1..2){@{Human=@{Samples=@(
            @{Kind='FirstCallWithColdEngine';InvocationMs=(90+$state);ExecutionMs=70;CallbackMs=1}
            @{Kind='WarmEngine';InvocationMs=(10+$state);ExecutionMs=(8+$state);CallbackMs=0.5}
            @{Kind='WarmEngine';InvocationMs=(12+$state);ExecutionMs=(9+$state);CallbackMs=0.25}
        )}}})
        $performance=@(
            @{Kind='FreshSessionImport';Samples=@(@{Mode='Import';ElapsedMs=400},@{Mode='Baseline';ElapsedMs=250},@{Mode='Import';ElapsedMs=420});Pairs=@(@{ElapsedMs=150},@{ElapsedMs=170})}
            @{Kind='EngineStartup';Mode='Process';ElapsedMs=60}
            @{Kind='EngineStartup';Mode='InProcess';ElapsedMs=5}
            @{Kind='EngineTransport';Mode='Process';ElapsedMs=180}
            @{Kind='RecordFraming';Implementation='PowerShell';RecordWidth=64;ElapsedMs=40}
            @{Kind='RecordFraming';Implementation='CSharp';RecordWidth=64;ElapsedMs=3}
            @{Kind='EventEmission';Listeners=0;CollectEvents=$false;EmitMs=2}
            @{Kind='EventEmission';Listeners=4;CollectEvents=$true;EmitMs=9}
            @{Kind='EventEmission';Listeners=4;CollectEvents=$true;EmitMs=11}
        )
        @{Performance=$performance;Integration=@(@{Kind='ControlledGitStatus';Scenarios=$human})}|ConvertTo-Json -Depth 12|ConvertFrom-Json
    }
    $find={param($Rows,[string]$Measure,[string]$Variant='-')@($Rows|Where-Object {$_.Measure -ceq $Measure -and $_.Variant -ceq $Variant})}
}

Describe 'Get-QuietPerformanceMember' {
    It 'reads dictionaries and objects and returns nothing for an absent member or null' {
        Get-QuietPerformanceMember @{A=1} 'A'|Should -Be 1
        Get-QuietPerformanceMember ([pscustomobject]@{A=2}) 'A'|Should -Be 2
        @(Get-QuietPerformanceMember @{A=1} 'B').Count|Should -Be 0
        @(Get-QuietPerformanceMember ([pscustomobject]@{A=2}) 'B').Count|Should -Be 0
        @(Get-QuietPerformanceMember $null 'A').Count|Should -Be 0
    }

    It 'unrolls an array member so @() gives the items, not a nested array' {
        @(Get-QuietPerformanceMember @{A=@(1,2,3)} 'A').Count|Should -Be 3
        @(Get-QuietPerformanceMember ('{"A":[1,2]}'|ConvertFrom-Json) 'A').Count|Should -Be 2
    }
}

Describe 'Get-QuietPerformanceItems' {
    It 'matches the member ordinally and skips null items' {
        $items=@(@{Kind='Import'},$null,@{Kind='import'},@{Kind='Import'},@{Mode='Import'})
        @(Get-QuietPerformanceItems $items 'Import').Count|Should -Be 2
        @(Get-QuietPerformanceItems $items 'Import' -Member Mode).Count|Should -Be 1
        @(Get-QuietPerformanceItems $null 'Import').Count|Should -Be 0
    }
}

Describe 'Get-QuietPerformanceNumbers' {
    It 'keeps finite numbers of every numeric type, skips absent members and counts the rest' {
        $rejected=0
        $items=@(@{V=[int]1},@{V=[long]2},@{V=[double]3.5},@{V=[decimal]4},@{V=[single]5},@{W=1},$null,@{V='6'},@{V=$true},@{V=[double]::NaN},@{V=[double]::PositiveInfinity},@{V=@(7,8)},@{V=$null})
        $values=Get-QuietPerformanceNumbers $items 'V' ([ref]$rejected)
        $values|Should -Be @(1,2,3.5,4,5)
        # '6', $true, NaN, +Inf, an array and an explicit null; the absent member and the null item are skipped.
        $rejected|Should -Be 6
    }

    It 'returns an empty array, not null, when nothing is numeric' {
        $rejected=0
        $values=Get-QuietPerformanceNumbers @() 'V' ([ref]$rejected)
        ,$values|Should -BeOfType [double[]]
        $values.Count|Should -Be 0
    }

    It 'accounts for every present value exactly once (fuzz)' {
        Invoke-QuietProperty -Name 'number partition' -Seed $seed -Count 300 -Generator {param([Random]$Random)
            $pool=@({param($r)[int]$r.Next()},{param($r)[double]($r.NextDouble()*1e6)},{param($r)[long]$r.Next()},{param($r)[string]$r.Next()},{param($r)[double]::NaN},{param($r)[double]::NegativeInfinity},{param($r)$null},{param($r)@(1,2)},{param($r)[pscustomobject]@{X=1}})
            @{Items=@(for($i=0;$i -lt $Random.Next(0,25);$i++){
                $kind=$Random.Next(-1,$pool.Count)
                if($kind -lt 0){@{Other=1}}else{@{V=(& $pool[$kind] $Random);Kind=$kind}}
            })}
        } -Property {param($case)
            $rejected=0
            $values=Get-QuietPerformanceNumbers $case.Items 'V' ([ref]$rejected)
            $present=@($case.Items|Where-Object {$_.ContainsKey('V')}).Count
            $good=@($case.Items|Where-Object {$_.ContainsKey('V') -and $_.Kind -in 0,1,2}).Count
            $values.Count -eq $good -and $values.Count+$rejected -eq $present -and @($values|Where-Object {![double]::IsFinite($_)}).Count -eq 0
        }|Should -Be 300
    }
}

Describe 'Get-QuietPerformanceVariantGroups' {
    It 'groups by label in ordinal order and counts invalid values in the context' {
        $context=[pscustomobject]@{Rejected=[ref]0}
        $items=@(@{K='b';V=2},@{K='B';V=1},@{K='a';V=3},@{K='b';V='x'},$null)
        $groups=@(Get-QuietPerformanceVariantGroups $items {param($item)$item.K} 'V' $context)
        $groups.Variant|Should -Be @('B','a','b')
        $groups[2].Values|Should -Be @(2)
        $context.Rejected.Value|Should -Be 1
    }
}

Describe 'New-QuietPerformanceGroup' {
    It 'defaults to the single-variant label and an empty double array' {
        $group=New-QuietPerformanceGroup
        $group.Variant|Should -BeExactly '-'
        ,$group.Values|Should -BeOfType [double[]]
        $group.Values.Count|Should -Be 0
    }

    It 'keeps the variant label and the observations in order' {
        $group=New-QuietPerformanceGroup -Variant 'listeners=4, collect=on' -Values @(3,1,2)
        $group.Variant|Should -BeExactly 'listeners=4, collect=on'
        $group.Values|Should -Be @(3,1,2)
    }
}

Describe 'Get-QuietPerformanceHumanSamples' {
    It 'collects the samples of one kind across every controlled Git state, in state order' {
        $context=[pscustomobject]@{Integration=(& $newCore).Integration}
        $warm=@(Get-QuietPerformanceHumanSamples $context 'WarmEngine')
        $warm.Count|Should -Be 4
        @($warm.InvocationMs)|Should -Be @(11,13,12,14)
        @(Get-QuietPerformanceHumanSamples $context 'FirstCallWithColdEngine').Count|Should -Be 2
    }

    It 'returns nothing without controlled Git evidence or for an unknown kind' {
        @(Get-QuietPerformanceHumanSamples ([pscustomobject]@{Integration=@(@{Kind='Other'})}) 'WarmEngine').Count|Should -Be 0
        @(Get-QuietPerformanceHumanSamples ([pscustomobject]@{Integration=(& $newCore).Integration}) 'Unknown').Count|Should -Be 0
    }
}

Describe 'Get-QuietPerformanceWorkloadCatalog' {
    It 'names every workload once per measure, with phase, source, limits and a selector' {
        $catalog=@(Get-QuietPerformanceWorkloadCatalog)
        @($catalog.Workload|Sort-Object -Unique)|Should -Be @('Events','Framing','GitTransport','ImportFirstCall','Metadata')
        @($catalog|ForEach-Object {$_.Workload+'/'+$_.Measure}|Sort-Object -Unique).Count|Should -Be $catalog.Count
        foreach($entry in $catalog){
            $entry.Phase|Should -Not -BeNullOrEmpty
            $entry.Source|Should -Not -BeNullOrEmpty
            $entry.Limits|Should -Not -BeNullOrEmpty
            $entry.Select|Should -BeOfType [scriptblock]
        }
    }

    It 'lists the measures in report order' {
        @(Get-QuietPerformanceWorkloadCatalog|ForEach-Object {$_.Workload+' / '+$_.Measure})|Should -Be @(
            'ImportFirstCall / Fresh-process import','ImportFirstCall / Import minus paired baseline','ImportFirstCall / First call, cold engine','ImportFirstCall / Engine startup'
            'GitTransport / Warm call','GitTransport / Warm execution','GitTransport / Warm callbacks','GitTransport / 8 MiB transport'
            'Framing / 1 MiB framing','Metadata / Outside execution'
            'ImportFirstCall / Fresh-process startup import','ImportFirstCall / Fresh-process first short call','ImportFirstCall / Fresh-process warm short call'
            'Metadata / Diagnostic short call','Metadata / Result construction','Metadata / Metadata projection','Metadata / Save round-trip','Metadata / Writer queue wait','Metadata / Write gate wait','Metadata / Metadata validation and JSON','Metadata / Writer preparation','Metadata / SQLite write','Events / Emit loop'
        )
    }
}

Describe 'Get-QuietPerformanceWorkloadRows' {
    It 'computes every measure of a complete Core summary' {
        $result=Get-QuietPerformanceWorkloadRows -Label 'host' -Core (& $newCore) -ProfiledWorkloads @()
        $result.Rejected|Should -Be 0
        $rows=$result.Rows
        (& $find $rows 'Fresh-process import')[0].Statistics.Median|Should -Be 410
        (& $find $rows 'Import minus paired baseline')[0].Statistics.Count|Should -Be 2
        (& $find $rows 'First call, cold engine')[0].Statistics.Max|Should -Be 92
        (& $find $rows 'Engine startup' 'hosting=InProcess')[0].Statistics.Median|Should -Be 5
        (& $find $rows 'Engine startup' 'hosting=Process')[0].Statistics.Median|Should -Be 60
        (& $find $rows 'Warm call')[0].Statistics.Count|Should -Be 4
        (& $find $rows 'Warm callbacks')[0].Statistics.Min|Should -Be 0.25
        (& $find $rows 'Warm execution')[0].Statistics.Median|Should -Be 10
        (& $find $rows '8 MiB transport' 'hosting=Process')[0].Statistics.Median|Should -Be 180
        (& $find $rows '1 MiB framing' 'CSharp, width=64')[0].Statistics.Median|Should -Be 3
        (& $find $rows 'Outside execution')[0].Statistics.Count|Should -Be 4
        # Invocation minus execution of each warm call: 2, 3, 2, 3.
        (& $find $rows 'Outside execution')[0].Statistics.Median|Should -Be 2.5
        (& $find $rows 'Outside execution')[0].Statistics.Min|Should -Be 2
        (& $find $rows 'Emit loop' 'listeners=4, collect=on')[0].Statistics.Median|Should -Be 10
        (& $find $rows 'Emit loop' 'listeners=0, collect=off')[0].Statistics.Count|Should -Be 1
        @($rows|Where-Object {$_.Instrumented -and $null -ne $_.Statistics}).Count|Should -Be 0
        @($rows|Where-Object {$_.Host -cne 'host'}).Count|Should -Be 0
    }

    It 'keeps one row with null statistics per measure when Core is absent' {
        $catalog=@(Get-QuietPerformanceWorkloadCatalog)
        $result=Get-QuietPerformanceWorkloadRows -Label 'host' -Core $null -ProfiledWorkloads $null
        $result.Rows.Count|Should -Be $catalog.Count
        @($result.Rows|Where-Object {$null -ne $_.Statistics}).Count|Should -Be 0
        @($result.Rows.Variant|Sort-Object -Unique)|Should -Be @('-')
    }

    It 'adds instrumented rows for profiled workloads and counts their invalid samples' {
        $profiled=@(@{Name='Events';Scope='s';SamplesMs=@(4,2,'x',3)},@{Name='Framing';Scope='f';SamplesMs=@()},$null)
        $result=Get-QuietPerformanceWorkloadRows -Label 'host' -Core $null -ProfiledWorkloads $profiled
        $instrumented=@($result.Rows|Where-Object {$_.Measure -ceq 'Instrumented iteration'})
        $instrumented.Workload|Should -Be @('Events','Framing')
        $instrumented[0].Statistics.Median|Should -Be 3
        $instrumented[0].Measure|Should -BeExactly 'Instrumented iteration'
        $instrumented[0].Variant|Should -BeExactly '-'
        $instrumented[0].Phase|Should -BeExactly 's'
        $instrumented[0].Source|Should -BeExactly 'profiling/powershell-lines.json Workloads[Events].SamplesMs'
        $instrumented[0].Limits|Should -BeLike 'Under the line profiler*Compare only with other instrumented rows.'
        $instrumented[1].Statistics|Should -BeNullOrEmpty
        $result.Rejected|Should -Be 1
    }

    It 'leaves a warm call without both timings out of Outside execution' {
        $core=& $newCore
        $core.Integration[0].Scenarios[0].Human.Samples[1].PSObject.Properties.Remove('ExecutionMs')
        $core.Integration[0].Scenarios[1].Human.Samples[2].PSObject.Properties.Remove('InvocationMs')
        $result=Get-QuietPerformanceWorkloadRows -Label 'host' -Core $core -ProfiledWorkloads @()
        $result.Rejected|Should -Be 0
        (& $find $result.Rows 'Outside execution')[0].Statistics.Count|Should -Be 2
    }

    It 'counts a string timing as rejected instead of reading it as a number' {
        $core=& $newCore
        $core.Performance[1].ElapsedMs='60'
        $result=Get-QuietPerformanceWorkloadRows -Label 'host' -Core $core -ProfiledWorkloads @()
        $result.Rejected|Should -Be 1
        (& $find $result.Rows 'Engine startup' 'hosting=Process')[0].Statistics|Should -BeNullOrEmpty
    }
}

Describe 'Get-QuietPerformanceRuntimeNote' {
    It 'groups environments by PowerShell and CLR and refuses a ranking' {
        $note=Get-QuietPerformanceRuntimeNote @(
            [pscustomobject]@{RID='linux-musl-x64';PowerShell='7.6.10';CLR='10.0.14'}
            [pscustomobject]@{RID='win-x64';PowerShell='7.7.0';CLR='11.0.0'}
            [pscustomobject]@{RID='linux-x64';PowerShell='7.7.0';CLR='11.0.0'}
        )
        $note|Should -BeExactly 'Environments use different runtimes: PowerShell 7.6.10 on 10.0.14 (linux-musl-x64); PowerShell 7.7.0 on 11.0.0 (linux-x64, win-x64). The rows are not a general operating-system ranking, and a difference between rows on different runners or runtimes is not causal.'
    }

    It 'still refuses a causal reading when every environment shares one runtime' {
        $note=Get-QuietPerformanceRuntimeNote @([pscustomobject]@{RID='a';PowerShell='7.7.0';CLR='11.0.0'},[pscustomobject]@{RID='b';PowerShell='7.7.0';CLR='11.0.0'})
        $note|Should -BeLike 'All environments use PowerShell 7.7.0 on 11.0.0 (a, b)*not causal*'
    }

    It 'says that nothing can be compared without environments' {
        Get-QuietPerformanceRuntimeNote @()|Should -BeLike 'No environment*'
        Get-QuietPerformanceRuntimeNote $null|Should -BeLike 'No environment*'
    }
}

Describe 'Fresh-process phase selectors' {
    It 'keeps telemetry arms, first/warm stages and diagnostic controls separate' {
        $startup=@{Kind='FreshProcessStartup';Samples=@(foreach($timers in @($false,$true)){foreach($telemetry in @($false,$true)){
            @{MeasurePhases=$timers;TelemetryEnabled=$telemetry;ImportMs=100;Calls=@(
                @{Stage='FirstCall';InvocationMs=20;ResultConstructionMs=2;SqliteWriteMs=$(if($timers -and $telemetry){7})}
                @{Stage='WarmCall';InvocationMs=10;ResultConstructionMs=1;SqliteWriteMs=$(if($timers -and $telemetry){3})}
            )}
        }})}
        $rows=(Get-QuietPerformanceWorkloadRows -Label h -Core @{Performance=@($startup)} -ProfiledWorkloads @()).Rows
        $ordinary=@($rows|Where-Object Measure -CEQ 'Fresh-process first short call')
        $ordinary.Count|Should -Be 2
        @($ordinary|Where-Object Instrumented).Count|Should -Be 0
        @($ordinary|Where-Object {$_.Statistics.Count -ne 1 -or $_.Statistics.Median -ne 20}).Count|Should -Be 0
        $write=@($rows|Where-Object {$_.Measure -ceq 'SQLite write' -and $_.Variant -ceq 'telemetry=on, FirstCall'})
        $write[0].Statistics.Median|Should -Be 7
        $write[0].Instrumented|Should -BeTrue
        @($rows|Where-Object {$_.Measure -ceq 'SQLite write' -and $_.Variant -like 'telemetry=off*' -and $null -ne $_.Statistics}).Count|Should -Be 0
        @($rows|Where-Object {$_.Measure -ceq 'Diagnostic short call'}).Count|Should -Be 4
    }
}
