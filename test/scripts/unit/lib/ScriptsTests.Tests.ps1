#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptsTests
    $seed=Get-QuietTestSeed
    $root=[IO.Path]::Combine($TestDrive,'tests')
    foreach($relative in @('unit/a.Tests.ps1','unit/sub/b.Tests.ps1','unit/helper.ps1','integration/c.Tests.ps1','support/d.Tests.ps1')){$null=New-QuietTestFile ([IO.Path]::Combine($root,$relative)) 'Describe x { It y { } }'}
    $empty=[IO.Path]::Combine($TestDrive,'empty');[void][IO.Directory]::CreateDirectory($empty)
    $expectedTypedError='^(ScriptsTestPathInvalid|ScriptsTestSelectionEmpty)\b'
    $allFiles=[string[]](Get-QuietScriptsTestPlan -TestsRoot $root).Files
}

Describe 'Get-QuietScriptsTestPlan' {
    It 'selects <Kind> files in ordinal order without support files' -ForEach @(
        @{Kind='Unit';Expected=@('unit/a.Tests.ps1','unit/sub/b.Tests.ps1')}
        @{Kind='Integration';Expected=@('integration/c.Tests.ps1')}
        @{Kind='All';Expected=@('integration/c.Tests.ps1','unit/a.Tests.ps1','unit/sub/b.Tests.ps1')}
    ) {
        $plan=Get-QuietScriptsTestPlan -TestsRoot $root -Kind $Kind
        $relative=@($plan.Files|ForEach-Object {[IO.Path]::GetRelativePath($root,$_).Replace('\','/')})
        $relative|Should -Be $Expected
        $plan.Partial|Should -BeFalse
        $plan.Kind|Should -BeExactly $Kind
    }

    It 'narrows to a file, a relative directory or an absolute directory and marks the run partial' {
        @((Get-QuietScriptsTestPlan -TestsRoot $root -Path 'unit/a.Tests.ps1').Files).Count|Should -Be 1
        $directory=Get-QuietScriptsTestPlan -TestsRoot $root -Path 'unit/sub'
        @($directory.Files).Count|Should -Be 1
        $directory.Partial|Should -BeTrue
        @((Get-QuietScriptsTestPlan -TestsRoot $root -Path ([IO.Path]::Combine($root,'unit'))).Files).Count|Should -Be 2
    }

    It 'rejects <Case> with a typed reason' -ForEach @(
        @{Case='an empty selector';Selector=' ';Reason='empty'}
        @{Case='a parent segment';Selector='unit/../integration';Reason='parent-segment'}
        @{Case='a control character';Selector="unit/a`0";Reason='control-character'}
        @{Case='a missing file';Selector='unit/missing.Tests.ps1';Reason='missing'}
        @{Case='a non-test file';Selector='unit/helper.ps1';Reason='not-a-test-file'}
    ) {
        {Get-QuietScriptsTestPlan -TestsRoot $root -Path $Selector}|Should -Throw -ExpectedMessage "ScriptsTestPathInvalid: $Reason"
    }

    It 'rejects an absolute path outside the tests root' {
        {Get-QuietScriptsTestPlan -TestsRoot $root -Path $empty}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: outside-root'
    }

    It 'rejects a missing tests root and reports an empty selection' {
        {Get-QuietScriptsTestPlan -TestsRoot ([IO.Path]::Combine($TestDrive,'nowhere'))}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: tests-root'
        {Get-QuietScriptsTestPlan -TestsRoot $empty}|Should -Throw -ExpectedMessage 'ScriptsTestSelectionEmpty'
        {Get-QuietScriptsTestPlan -TestsRoot $root -Kind Unit -Path 'integration'}|Should -Throw -ExpectedMessage 'ScriptsTestSelectionEmpty'
    }

    It 'neither discovers nor accepts tests behind a directory link' {
        $target=[IO.Path]::Combine($TestDrive,'outside');$null=New-QuietTestFile ([IO.Path]::Combine($target,'z.Tests.ps1')) 'Describe z { It z { } }'
        $link=[IO.Path]::Combine($root,'unit','linked')
        try{$null=New-Item -ItemType $(if($IsWindows){'Junction'}else{'SymbolicLink'}) -Path $link -Target $target -ErrorAction Stop}catch{Set-ItResult -Skipped -Because 'directory links are unavailable on this host';return}
        try{
            @((Get-QuietScriptsTestPlan -TestsRoot $root -Kind Unit).Files|Where-Object {$_ -like '*z.Tests.ps1'}).Count|Should -Be 0
            {Get-QuietScriptsTestPlan -TestsRoot $root -Path 'unit/linked/z.Tests.ps1'}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: link'
        }finally{[IO.Directory]::Delete($link)}
    }

    It 'fails only with typed errors and never selects outside the root on fuzzed selectors' {
        $checked=Invoke-QuietProperty -Name 'fuzzed -Path selectors' -Seed $seed -Count 400 -Generator {param($random)@(1..$random.Next(1,3)|ForEach-Object {New-QuietFuzzPath $random})} -Property {param($selectors)
            try{$plan=Get-QuietScriptsTestPlan -TestsRoot $root -Path $selectors}catch{if($_.Exception.Message -notmatch $expectedTypedError){throw "untyped error: $($_.Exception.Message)"};return $true}
            foreach($file in $plan.Files){if(!$file.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or !$file.EndsWith('.Tests.ps1')){throw "escaped: $file"}}
            return [bool]$plan.Partial
        } -Shrink {param($selectors)if(@($selectors).Count -gt 1){,@($selectors[0]);,@($selectors[1..($selectors.Count-1)])}}
        $checked|Should -Be 400
    }

    It 'is partial exactly when a selector or a non-blank filter is present' {
        $null=Invoke-QuietProperty -Name 'partial iff narrowed' -Seed $seed -Count 200 -Generator {param($random)
            $pick={param($values)[string[]](Get-QuietRandomSubset $random $values 0.3)}
            [ordered]@{Path=(& $pick @('unit','unit/sub'));FullNameFilter=(& $pick @('*a*',' ',''));Tag=(& $pick @('Fast',''));ExcludeTag=(& $pick @('Slow',' '))}
        } -Property {param($case)
            $plan=Get-QuietScriptsTestPlan -TestsRoot $root -Kind Unit -Path $case.Path -FullNameFilter $case.FullNameFilter -Tag $case.Tag -ExcludeTag $case.ExcludeTag
            $narrowed=@($case.Path).Count -gt 0 -or @(@($case.FullNameFilter)+@($case.Tag)+@($case.ExcludeTag)|Where-Object {![string]::IsNullOrWhiteSpace($_)}).Count -gt 0
            return $plan.Partial -eq $narrowed
        }
    }
}

Describe 'New-QuietScriptsPesterConfiguration' {
    It 'maps files, non-blank filters and JUnit output without coverage by default' {
        $plan=Get-QuietScriptsTestPlan -TestsRoot $root -Kind Unit -Tag Fast -ExcludeTag ' '
        $configuration=New-QuietScriptsPesterConfiguration -Plan $plan -RunDirectory $TestDrive
        $configuration.Run.Path|Should -Be $plan.Files
        $configuration.Filter.Tag|Should -Be @('Fast')
        $configuration.Filter.Contains('ExcludeTag')|Should -BeFalse
        $configuration.TestResult.OutputPath|Should -Be ([IO.Path]::Combine($TestDrive,'results.junit.xml'))
        $configuration.Contains('CodeCoverage')|Should -BeFalse
    }

    It 'enables JaCoCo coverage with the target threshold' {
        $plan=Get-QuietScriptsTestPlan -TestsRoot $root
        $configuration=New-QuietScriptsPesterConfiguration -Plan $plan -RunDirectory $TestDrive -CoverageTargets ([pscustomobject]@{Threshold=75.5;Paths=@('x.psm1')})
        $configuration.CodeCoverage.OutputFormat|Should -BeExactly 'JaCoCo'
        $configuration.CodeCoverage.CoveragePercentTarget|Should -Be 75.5
    }

    It 'rejects a plan without files' {
        {New-QuietScriptsPesterConfiguration -Plan ([pscustomobject]@{Files=@()}) -RunDirectory $TestDrive}|Should -Throw -ExpectedMessage 'ScriptsTestSelectionEmpty'
    }

    It 'always produces a configuration Pester 6 accepts' {
        $null=Invoke-QuietProperty -Name 'Pester accepts the configuration' -Seed $seed -Count 60 -Generator {param($random)
            [pscustomobject]@{Files=[string[]](Get-QuietRandomSubset $random $allFiles 0.7)+$allFiles[0];FullNameFilter=[string[]](Get-QuietRandomSubset $random @('*a*','b')) ;Tag=[string[]](Get-QuietRandomSubset $random @('Fast'));ExcludeTag=[string[]](Get-QuietRandomSubset $random @('Slow'));Coverage=($random.Next(0,2) -eq 1)}
        } -Property {param($case)
            $targets=if($case.Coverage){[pscustomobject]@{Threshold=50;Paths=@($case.Files[0])}}else{$null}
            $hashtable=New-QuietScriptsPesterConfiguration -Plan $case -RunDirectory $TestDrive -CoverageTargets $targets
            $roundTrip=ConvertTo-Json $hashtable -Depth 8|ConvertFrom-Json -AsHashtable
            $configuration=New-PesterConfiguration -Hashtable $roundTrip
            return (@($configuration.Run.Path.Value).Count -eq @($case.Files).Count) -and ($configuration.CodeCoverage.Enabled.Value -eq [bool]$case.Coverage)
        }
    }
}

Describe 'Get-QuietScriptsCoverageTargets' {
    BeforeAll {
        $scripts=[IO.Path]::Combine($TestDrive,'scripts');$null=New-QuietTestFile ([IO.Path]::Combine($scripts,'lib','X.psm1')) 'function X {}'
        $write={param($text)$folder=[IO.Path]::Combine($TestDrive,'cov-'+[guid]::NewGuid().ToString('N'));$null=New-QuietTestFile ([IO.Path]::Combine($folder,'coverage.targets.psd1')) $text;$folder}
    }
    It 'resolves targets against the scripts root' {
        $targets=Get-QuietScriptsCoverageTargets -TestsRoot (& $write "@{Threshold=80;Paths=@('lib/X.psm1')}") -ScriptsRoot $scripts
        $targets.Threshold|Should -Be 80
        $targets.Paths|Should -Be @([IO.Path]::Combine($scripts,'lib','X.psm1'))
    }
    It 'rejects <Case>' -ForEach @(
        @{Case='a threshold above 100';Text="@{Threshold=101;Paths=@('lib/X.psm1')}";Message='ScriptsTestCoverageTargetsInvalid: threshold'}
        @{Case='a string threshold';Text="@{Threshold='80';Paths=@('lib/X.psm1')}";Message='ScriptsTestCoverageTargetsInvalid: threshold'}
        @{Case='no paths';Text='@{Threshold=80;Paths=@()}';Message='ScriptsTestCoverageTargetsInvalid: paths'}
        @{Case='a parent segment';Text="@{Threshold=80;Paths=@('../X.psm1')}";Message='ScriptsTestCoverageTargetsInvalid: path'}
        @{Case='a missing target';Text="@{Threshold=80;Paths=@('lib/Y.psm1')}";Message='ScriptsTestCoverageTargetsInvalid: missing-target'}
        @{Case='invalid syntax';Text='@{';Message='ScriptsTestCoverageTargetsInvalid: syntax'}
    ) {
        {Get-QuietScriptsCoverageTargets -TestsRoot (& $write $Text) -ScriptsRoot $scripts}|Should -Throw -ExpectedMessage $Message
    }
    It 'reports a missing targets file' {
        {Get-QuietScriptsCoverageTargets -TestsRoot $empty -ScriptsRoot $scripts}|Should -Throw -ExpectedMessage 'ScriptsTestCoverageTargetsMissing'
    }
}

Describe 'ConvertTo-QuietScriptsTestReport' {
    BeforeAll {
        $plan=[pscustomobject]@{Kind='Unit';Partial=$false;Files=@('a')}
        $result={param($passed,$failed,$skipped,$blocks=0,$containers=0,$outcome='Passed')[pscustomobject]@{PassedCount=$passed;FailedCount=$failed;SkippedCount=$skipped;NotRunCount=0;FailedBlocksCount=$blocks;FailedContainersCount=$containers;Result=$outcome;Tests=@()}}
    }
    It 'reports a green run as Success' {
        $report=ConvertTo-QuietScriptsTestReport -Result (& $result 3 0 1) -Plan $plan -Seed 7
        $report.State|Should -BeExactly 'Success'
        $report.Total|Should -Be 4
        $report.Seed|Should -Be 7
        $report.Incomplete|Should -BeFalse
    }
    It 'counts failed blocks and containers as failures' {
        $report=ConvertTo-QuietScriptsTestReport -Result (& $result 2 0 0 1 1 'Failed') -Plan $plan
        $report.Failed|Should -Be 2
        $report.State|Should -BeExactly 'Failed'
    }
    It 'marks <Case> as incomplete' -ForEach @(
        @{Case='a null result';Value=$null}
        @{Case='zero executed tests';Value=[pscustomobject]@{PassedCount=0;FailedCount=0;SkippedCount=0;Result='Passed'}}
        @{Case='an unknown outcome';Value=[pscustomobject]@{PassedCount=1;FailedCount=0;SkippedCount=0;Result='NotRun'}}
    ) {
        $report=ConvertTo-QuietScriptsTestReport -Result $Value -Plan $plan
        $report.Incomplete|Should -BeTrue
        $report.State|Should -BeExactly 'Failed'
    }
    It 'enforces the coverage threshold' {
        $covered=& $result 1 0 0;$covered|Add-Member CodeCoverage ([pscustomobject]@{CoveragePercent=79.99})
        (ConvertTo-QuietScriptsTestReport -Result $covered -Plan $plan -CoverageTarget 80).State|Should -BeExactly 'Failed'
        (ConvertTo-QuietScriptsTestReport -Result $covered -Plan $plan -CoverageTarget 79).State|Should -BeExactly 'Success'
        $missing=ConvertTo-QuietScriptsTestReport -Result (& $result 1 0 0) -Plan $plan -CoverageTarget 10
        $missing.Incomplete|Should -BeTrue
    }
    It 'never throws and keeps Passed + Failed + Skipped = Total on fuzzed results' {
        $null=Invoke-QuietProperty -Name 'report invariant' -Seed $seed -Count 500 -Generator {param($random)
            $values=@($null,-1,0,1,2,7,'3','x',$true,[int]::MaxValue,[long]::MaxValue,1.5,(,@(1,2)),[pscustomobject]@{a=1},'',' 4 ')
            $shape=@{}
            foreach($name in @('PassedCount','FailedCount','SkippedCount','NotRunCount','FailedBlocksCount','FailedContainersCount','Result','Tests','CodeCoverage')){if($random.Next(0,5) -ne 0){$shape[$name]=Get-QuietRandomItem $random $values}}
            if($random.Next(0,2) -eq 0){$shape.Result=Get-QuietRandomItem $random @('Passed','Failed','NotRun')}
            $(if($random.Next(0,2) -eq 0){[pscustomobject]$shape}else{$shape})
        } -Property {param($case)
            $report=ConvertTo-QuietScriptsTestReport -Result $case -Plan $plan -CoverageTarget $(if($case.Count % 2){50}else{$null})
            if($report.Passed+$report.Failed+$report.Skipped -ne $report.Total){return $false}
            if($report.State -ceq 'Success' -and ($report.Incomplete -or $report.Failed -ne 0)){return $false}
            return $report.State -in @('Success','Failed')
        }
    }
}

Describe 'Scripts test status transitions' {
    BeforeAll {$plan=[pscustomobject]@{Kind='All';TestsRoot=$root;Files=@('a','b')}}
    It 'starts Running with the monitor fields' {
        $status=New-QuietScriptsTestStatus -WorkspaceRoot $TestDrive -Plan $plan -ProcessId 42
        $status.State|Should -BeExactly 'Running'
        foreach($field in @('Project','Task','Workspace','ProjectDirectory','Platform','StartedUtc','ProcessId','Passed','Failed','Case')){$status.Contains($field)|Should -BeTrue -Because $field}
        $status.Case|Should -Match '2 test file'
    }
    It 'moves Running to the report state exactly once' {
        $status=New-QuietScriptsTestStatus -WorkspaceRoot $TestDrive -Plan $plan -ProcessId 1
        $report=[ordered]@{State='Failed';Passed=1;Failed=2;Skipped=0;Partial=$true;Incomplete=$false}
        $terminal=Update-QuietScriptsTestStatus -Status $status -Report $report
        $terminal.State|Should -BeExactly 'Failed'
        $terminal.Failed|Should -Be 2
        $terminal.Case|Should -Match 'partial'
        $terminal.FinishedUtc|Should -Not -BeNullOrEmpty
        $status.State|Should -BeExactly 'Running'
        {Update-QuietScriptsTestStatus -Status $terminal -Report $report}|Should -Throw -ExpectedMessage 'ScriptsTestStatusTransitionInvalid'
    }
    It 'records a crash with an extra failure' {
        $crash=Update-QuietScriptsTestStatus -Status (New-QuietScriptsTestStatus -WorkspaceRoot $TestDrive -Plan $plan -ProcessId 1) -ErrorMessage 'boom'
        $crash.State|Should -BeExactly 'Crash'
        $crash.Failed|Should -Be 1
        $crash.Error|Should -BeExactly 'boom'
    }
    It 'rejects a non-terminal report state' {
        {Update-QuietScriptsTestStatus -Status (New-QuietScriptsTestStatus -WorkspaceRoot $TestDrive -Plan $plan -ProcessId 1) -Report ([ordered]@{State='Running'})}|Should -Throw -ExpectedMessage 'ScriptsTestStatusTransitionInvalid'
    }
}

Describe 'Get-QuietScriptsTestExitCode' {
    It 'returns <Code> for <State>' -ForEach @(
        @{State='Success';Code=0};@{State='Failed';Code=1};@{State='Crash';Code=1};@{State='Timeout';Code=1};@{State='Cancelled';Code=1};@{State='success';Code=1};@{State='';Code=1}
    ) {
        Get-QuietScriptsTestExitCode $State|Should -Be $Code
    }
}
