#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $library=Import-QuietTestLibrary -Name ScriptsTests
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

    It 'defaults to All' {
        $plan=Get-QuietScriptsTestPlan -TestsRoot $root
        $plan.Kind|Should -BeExactly 'All'
        $plan.Files|Should -Be $allFiles
        @($plan.Files).Count|Should -Be 3
        $plan.TestsRoot|Should -BeExactly ([IO.Path]::GetFullPath($root))
        $plan.Partial|Should -BeFalse
    }

    It 'selects a file once when overlapping selectors both contain it' {
        $plan=Get-QuietScriptsTestPlan -TestsRoot $root -Path 'unit','unit/a.Tests.ps1','unit/sub'
        @($plan.Files|ForEach-Object {[IO.Path]::GetRelativePath($root,$_).Replace('\','/')})|Should -Be @('unit/a.Tests.ps1','unit/sub/b.Tests.ps1')
    }

    It 'keeps only non-blank filters in the plan' {
        $plan=Get-QuietScriptsTestPlan -TestsRoot $root -FullNameFilter '*a*',' ' -Tag '','Fast' -ExcludeTag 'Slow'
        $plan.FullNameFilter|Should -Be @('*a*')
        $plan.Tag|Should -Be @('Fast')
        $plan.ExcludeTag|Should -Be @('Slow')
    }

    It 'rejects a blank tests root and one the platform cannot resolve' {
        {Get-QuietScriptsTestPlan -TestsRoot ' '}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: tests-root*'
        {Get-QuietScriptsTestPlan -TestsRoot "unit`0root"}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: tests-root-unresolvable'
    }

    It 'rejects a tests root that is a link and skips a kind directory that is a link' {
        $real=[IO.Path]::Combine($TestDrive,'real-root');$null=New-QuietTestFile ([IO.Path]::Combine($real,'unit','r.Tests.ps1')) 'Describe r { It r { } }'
        $linkedRoot=[IO.Path]::Combine($TestDrive,'linked-root')
        $kindRoot=[IO.Path]::Combine($TestDrive,'kind-root');[void][IO.Directory]::CreateDirectory($kindRoot)
        $linkedKind=[IO.Path]::Combine($kindRoot,'unit')
        $type=if($IsWindows){'Junction'}else{'SymbolicLink'}
        try{$null=New-Item -ItemType $type -Path $linkedRoot -Target $real -ErrorAction Stop;$null=New-Item -ItemType $type -Path $linkedKind -Target ([IO.Path]::Combine($real,'unit')) -ErrorAction Stop}catch{Set-ItResult -Skipped -Because 'directory links are unavailable on this host';return}
        try{
            {Get-QuietScriptsTestPlan -TestsRoot $linkedRoot}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: tests-root'
            {Get-QuietScriptsTestPlan -TestsRoot $kindRoot -Kind Unit}|Should -Throw -ExpectedMessage 'ScriptsTestSelectionEmpty'
            {Resolve-QuietScriptsTestPath -Path 'unit' -TestsRoot $kindRoot}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: link'
            Resolve-QuietScriptsTestPath -Path 'unit' -TestsRoot $linkedRoot|Should -BeExactly ([IO.Path]::Combine($linkedRoot,'unit')) -Because 'the root itself is trusted; only the path below it is walked'
            Resolve-QuietScriptsTestPath -Path '.' -TestsRoot $linkedRoot|Should -BeExactly $linkedRoot
        }finally{[IO.Directory]::Delete($linkedRoot);[IO.Directory]::Delete($linkedKind)}
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

Describe 'Resolve-QuietScriptsTestPath' {
    It 'returns the full path of <Selector>' -ForEach @(
        @{Selector='unit/a.Tests.ps1';Relative='unit/a.Tests.ps1'}
        @{Selector='unit/sub/';Relative='unit/sub/'}
        @{Selector='integration';Relative='integration'}
    ) {
        Resolve-QuietScriptsTestPath -Path $Selector -TestsRoot $root|Should -BeExactly ([IO.Path]::GetFullPath([IO.Path]::Combine($root,$Relative)))
    }

    It 'reads a backslash as a separator on Windows only' {
        if($IsWindows){
            Resolve-QuietScriptsTestPath -Path 'unit\sub' -TestsRoot $root|Should -BeExactly ([IO.Path]::GetFullPath([IO.Path]::Combine($root,'unit/sub')))
        }else{
            # Elsewhere a backslash is an ordinary file name character, so unit\sub names a missing entry.
            {Resolve-QuietScriptsTestPath -Path 'unit\sub' -TestsRoot $root}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: missing'
        }
    }

    It 'accepts an absolute path inside the root unchanged' {
        $absolute=[IO.Path]::Combine($root,'unit','a.Tests.ps1')
        Resolve-QuietScriptsTestPath -Path $absolute -TestsRoot $root|Should -BeExactly $absolute
    }

    It 'rejects <Case> without echoing the value' -ForEach @(
        @{Case='null';Selector=$null;Reason='empty'}
        @{Case='an empty string';Selector='';Reason='empty'}
        @{Case='whitespace';Selector="`t ";Reason='empty'}
        @{Case='a tab inside';Selector="unit/a`t.Tests.ps1";Reason='control-character'}
        @{Case='a leading NUL';Selector=([string][char]0)+'unit/a.Tests.ps1';Reason='control-character'}
        @{Case='an embedded NUL';Selector='unit/a'+[char]0+'.Tests.ps1';Reason='control-character'}
        @{Case='a parent segment';Selector='unit\..\unit';Reason='parent-segment'}
        @{Case='a leading parent';Selector='../tests/unit';Reason='parent-segment'}
        @{Case='a missing directory';Selector='nowhere';Reason='missing'}
        @{Case='a support test file';Selector='unit/helper.ps1';Reason='not-a-test-file'}
    ) {
        $message=try{$null=Resolve-QuietScriptsTestPath -Path $Selector -TestsRoot $root;'no error'}catch{$_.Exception.Message}
        $message|Should -BeExactly "ScriptsTestPathInvalid: $Reason"
    }

    It 'rejects an absolute path outside the root' {
        {Resolve-QuietScriptsTestPath -Path $empty -TestsRoot $root}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: outside-root'
    }

    It 'rejects a sibling directory that shares the root prefix' {
        $sibling=$root+'-sibling';$null=New-QuietTestFile ([IO.Path]::Combine($sibling,'s.Tests.ps1')) ''
        {Resolve-QuietScriptsTestPath -Path ([IO.Path]::Combine($sibling,'s.Tests.ps1')) -TestsRoot $root}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: outside-root'
    }

    It 'rejects a character the platform forbids in paths' {
        $forbidden=@([IO.Path]::GetInvalidPathChars()|Where-Object {![char]::IsControl($_)})
        if($forbidden.Count -eq 0){Set-ItResult -Skipped -Because 'every invalid path character is a control character here';return}
        {Resolve-QuietScriptsTestPath -Path ('unit/a'+$forbidden[0]+'.Tests.ps1') -TestsRoot $root}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: invalid-character'
        {Resolve-QuietScriptsTestPath -Path ($forbidden[0]+'unit/a.Tests.ps1') -TestsRoot $root}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: invalid-character' -Because 'the first character is checked too'
    }

    It 'compares the root case-insensitively on Windows only' {
        $upper=[IO.Path]::Combine($root.ToUpperInvariant(),'unit','a.Tests.ps1')
        if($IsWindows){Resolve-QuietScriptsTestPath -Path $upper -TestsRoot $root|Should -BeExactly $upper}
        else{{Resolve-QuietScriptsTestPath -Path $upper -TestsRoot $root}|Should -Throw -ExpectedMessage 'ScriptsTestPathInvalid: outside-root'}
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
        $configuration=New-QuietScriptsPesterConfiguration -Plan $plan -RunDirectory $TestDrive -CoverageTargets ([pscustomobject]@{Threshold=75.5;Paths=@('x.psm1','y.psm1')})
        $configuration.CodeCoverage.Enabled|Should -BeTrue
        $configuration.CodeCoverage.OutputFormat|Should -BeExactly 'JaCoCo'
        $configuration.CodeCoverage.CoveragePercentTarget|Should -Be 75.5
        $configuration.CodeCoverage.Path|Should -Be @('x.psm1','y.psm1')
        $configuration.CodeCoverage.OutputPath|Should -BeExactly ([IO.Path]::Combine($TestDrive,'coverage.xml'))
    }

    It 'produces exactly the documented configuration' {
        $plan=[pscustomobject]@{Files=@('a.Tests.ps1');FullNameFilter=@('*x*','');Tag=@('Fast');ExcludeTag=@('Slow')}
        $expected=[ordered]@{
            Run=[ordered]@{Path=@('a.Tests.ps1');PassThru=$true;Exit=$false;Throw=$false}
            Filter=[ordered]@{FullName=@('*x*');Tag=@('Fast');ExcludeTag=@('Slow')}
            Output=[ordered]@{Verbosity='Detailed';StackTraceVerbosity='Filtered';RenderMode='Plaintext'}
            TestResult=[ordered]@{Enabled=$true;OutputFormat='JUnitXml';OutputPath=[IO.Path]::Combine($TestDrive,'results.junit.xml')}
            Should=[ordered]@{ErrorAction='Stop'}
        }
        (New-QuietScriptsPesterConfiguration -Plan $plan -RunDirectory $TestDrive|ConvertTo-Json -Depth 6)|Should -BeExactly ($expected|ConvertTo-Json -Depth 6)
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
        @{Case='a negative threshold';Text="@{Threshold=-0.5;Paths=@('lib/X.psm1')}";Message='ScriptsTestCoverageTargetsInvalid: threshold'}
        @{Case='a threshold just above 100';Text="@{Threshold=100.01;Paths=@('lib/X.psm1')}";Message='ScriptsTestCoverageTargetsInvalid: threshold'}
        @{Case='a numeric path';Text='@{Threshold=80;Paths=@(5)}';Message='ScriptsTestCoverageTargetsInvalid: path'}
        @{Case='a blank path';Text="@{Threshold=80;Paths=@('  ')}";Message='ScriptsTestCoverageTargetsInvalid: path'}
        @{Case='a rooted path';Text="@{Threshold=80;Paths=@('/lib/X.psm1')}";Message='ScriptsTestCoverageTargetsInvalid: path'}
    ) {
        {Get-QuietScriptsCoverageTargets -TestsRoot (& $write $Text) -ScriptsRoot $scripts}|Should -Throw -ExpectedMessage $Message
    }
    It 'accepts the threshold bound <Threshold>' -ForEach @(@{Threshold='0'},@{Threshold='100'},@{Threshold='99.5'}) {
        (Get-QuietScriptsCoverageTargets -TestsRoot (& $write "@{Threshold=$Threshold;Paths=@('lib/X.psm1')}") -ScriptsRoot $scripts).Threshold|Should -Be ([double]$Threshold)
    }
    It 'reports a missing targets file' {
        {Get-QuietScriptsCoverageTargets -TestsRoot $empty -ScriptsRoot $scripts}|Should -Throw -ExpectedMessage 'ScriptsTestCoverageTargetsMissing'
    }
}

Describe 'ConvertTo-QuietScriptsXmlText' {
    It 'turns <Case> into the expected text' -ForEach @(
        @{Case='null';Text=$null;Expected=''}
        @{Case='an empty string';Text='';Expected=''}
        @{Case='plain text';Text='plain text';Expected='plain text'}
        @{Case='tab, line feed and carriage return';Text="a`tb`nc`rd";Expected="a`tb`nc`rd"}
        @{Case='ANSI colors';Text="`e[31;1mred`e[0m text";Expected='red text'}
        @{Case='an ANSI sequence with an intermediate byte';Text="a`e[1 qb";Expected='ab'}
        @{Case='a lone escape';Text="a`ex";Expected='aU+001Bx'}
        @{Case='NUL and bell';Text=('a'+[char]0+'b'+[char]7);Expected='aU+0000bU+0007'}
        @{Case='the last control character';Text=[string][char]0x1F;Expected='U+001F'}
        @{Case='the first printable character';Text=' ';Expected=' '}
        @{Case='the last valid BMP character';Text=[string][char]0xFFFD;Expected=[string][char]0xFFFD}
        @{Case='U+FFFE';Text=[string][char]0xFFFE;Expected='U+FFFE'}
        @{Case='U+FFFF';Text=[string][char]0xFFFF;Expected='U+FFFF'}
        @{Case='a character outside the BMP';Text=('x'+[char]::ConvertFromUtf32(0x1F600));Expected=('x'+[char]::ConvertFromUtf32(0x1F600))}
        @{Case='the first character outside the BMP';Text=[char]::ConvertFromUtf32(0x10000);Expected=[char]::ConvertFromUtf32(0x10000)}
        @{Case='a lone surrogate';Text=('a'+[char]0xD800+'b');Expected=('a'+[char]0xFFFD+'b')}
    ) {
        ConvertTo-QuietScriptsXmlText -Text $Text|Should -BeExactly $Expected
    }

    It 'always returns text an XML document can hold, on fuzzed input' {
        $random=[Random]::new([int]$env:QUIETCLI_TEST_SEED)
        for($i=0;$i -lt 200;$i++){
            $text=-join @(for($j=$random.Next(0,40);$j -gt 0;$j--){[char]$random.Next(0,0x10000)})
            $safe=ConvertTo-QuietScriptsXmlText -Text $text
            {[Xml.XmlConvert]::VerifyXmlChars($safe)}|Should -Not -Throw -Because ('seed '+$env:QUIETCLI_TEST_SEED+', case '+$i)
        }
    }
}

Describe 'Protect-QuietScriptsTestResult' {
    BeforeAll {
        $record={param($message,$stack)[pscustomobject]@{DisplayErrorMessage=$message;DisplayStackTrace=$stack}}
    }

    It 'cleans test paths and the messages and stack traces of tests and containers, and counts the changes' {
        $testError=& $record ("`e[31mtest failed`e[0m") ('at'+[char]0)
        $containerError=& $record ('setup'+[char]7) 'clean'
        $result=[pscustomobject]@{
            Tests=@([pscustomobject]@{ExpandedPath=('d.n'+[char]0+'x');ErrorRecord=@($testError)},[pscustomobject]@{ExpandedPath='d.ok';ErrorRecord=@()})
            Containers=@([pscustomobject]@{ErrorRecord=@($containerError)})
        }
        Protect-QuietScriptsTestResult -Result $result|Should -Be 4
        $result.Tests[0].ExpandedPath|Should -BeExactly 'd.nU+0000x'
        $result.Tests[1].ExpandedPath|Should -BeExactly 'd.ok'
        $testError.DisplayErrorMessage|Should -BeExactly 'test failed'
        $testError.DisplayStackTrace|Should -BeExactly 'atU+0000'
        $containerError.DisplayErrorMessage|Should -BeExactly 'setupU+0007'
        $containerError.DisplayStackTrace|Should -BeExactly 'clean'
    }

    It 'leaves values that are not strings alone' {
        $nonText=& $record $null 42
        $result=[pscustomobject]@{Tests=@([pscustomobject]@{ExpandedPath=$null;ErrorRecord=@($nonText)});Containers=$null}
        Protect-QuietScriptsTestResult -Result $result|Should -Be 0
        $null -eq $result.Tests[0].ExpandedPath|Should -BeTrue
        $null -eq $nonText.DisplayErrorMessage|Should -BeTrue
        $nonText.DisplayStackTrace|Should -BeOfType [int]
        $nonText.DisplayStackTrace|Should -Be 42
    }

    It 'accepts a result without tests or containers' {
        Protect-QuietScriptsTestResult -Result ([pscustomobject]@{})|Should -Be 0
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
        $report.TestFailed|Should -Be 0
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
    It 'reports the project, kind, plan files and seed' {
        $report=ConvertTo-QuietScriptsTestReport -Result (& $result 1 0 0) -Plan ([pscustomobject]@{Kind='Integration';Partial=$true;Files=@('x','y')}) -Seed 9
        $report.Project|Should -BeExactly 'Scripts.Tests'
        $report.Kind|Should -BeExactly 'Integration'
        $report.Files|Should -Be @('x','y')
        $report.Partial|Should -BeTrue
        $report.Seed|Should -Be 9
        $report.Coverage|Should -BeNullOrEmpty
    }
    It 'reads a dictionary whose keys are not strings as a result with no counts' {
        $report=ConvertTo-QuietScriptsTestReport -Result ([Collections.Generic.Dictionary[int,string]]::new()) -Plan $plan
        $report.Incomplete|Should -BeTrue
        $report.Passed|Should -Be 0
    }
    It 'reads a property whose getter throws as absent instead of throwing' {
        $object=& $result 3 0 0
        $object|Add-Member -MemberType ScriptProperty -Name Result -Value {throw 'getter failure'} -Force
        $value=& $library {param($Value)Get-QuietScriptsTestValue $Value 'Result'} $object
        $value|Should -BeNullOrEmpty -Because 'Get-QuietScriptsTestValue relies on PowerShell reading a throwing getter as null'
        $report=ConvertTo-QuietScriptsTestReport -Result $object -Plan $plan
        $report.Incomplete|Should -BeTrue -Because 'an unreadable outcome is not a known one'
        $report.State|Should -BeExactly 'Failed'
    }
    It 'converts <Raw> to the count <Expected>' -ForEach @(
        @{Raw='7';Expected=7};@{Raw='0';Expected=0};@{Raw='-1';Expected=-1};@{Raw='x';Expected=-1};@{Raw='2147483648';Expected=-1};@{Raw=$null;Expected=-1}
    ) {
        $count=& $library {param($Value)ConvertTo-QuietScriptsTestCount $Value} $Raw
        $count|Should -BeExactly $Expected
        $count|Should -BeOfType [int]
    }
    It 'reads a dictionary result exactly like an object result' {
        $object=& $result 4 1 2 0 0 'Failed'
        $dictionary=[ordered]@{};foreach($property in $object.PSObject.Properties){$dictionary[$property.Name]=$property.Value}
        $generic=[Collections.Generic.Dictionary[string,object]]::new();foreach($property in $object.PSObject.Properties){if($property.Name -cne 'NotRunCount'){$generic[$property.Name]=$property.Value}}
        $fromObject=ConvertTo-QuietScriptsTestReport -Result $object -Plan $plan|ConvertTo-Json -Depth 5
        (ConvertTo-QuietScriptsTestReport -Result $dictionary -Plan $plan|ConvertTo-Json -Depth 5)|Should -BeExactly $fromObject
        (ConvertTo-QuietScriptsTestReport -Result $generic -Plan $plan|ConvertTo-Json -Depth 5)|Should -BeExactly $fromObject -Because 'a missing key of a generic dictionary reads as absent instead of throwing'
        $failed=ConvertTo-QuietScriptsTestReport -Result $object -Plan $plan
        $failed.Incomplete|Should -BeFalse -Because 'Failed is a known outcome'
        $failed.Failed|Should -Be 1
    }
    It 'reads <Name> = <Raw> as <Count>' -ForEach @(
        @{Name='PassedCount';Raw='3';Count=3;Incomplete=$false}
        @{Name='PassedCount';Raw=' 4 ';Count=4;Incomplete=$false}
        @{Name='PassedCount';Raw=[int]::MaxValue;Count=[int]::MaxValue;Incomplete=$false}
        @{Name='PassedCount';Raw=([long][int]::MaxValue+1);Count=0;Incomplete=$true}
        @{Name='PassedCount';Raw=-1;Count=0;Incomplete=$true}
        @{Name='PassedCount';Raw=$true;Count=0;Incomplete=$true}
        @{Name='PassedCount';Raw=1.5;Count=0;Incomplete=$true}
        @{Name='PassedCount';Raw='x';Count=0;Incomplete=$true}
        @{Name='PassedCount';Raw=$null;Count=0;Incomplete=$true}
        @{Name='SkippedCount';Raw='x';Count=0;Incomplete=$true}
        @{Name='NotRunCount';Raw='x';Count=0;Incomplete=$false}
        @{Name='NotRunCount';Raw='5';Count=5;Incomplete=$false}
    ) {
        $value=[ordered]@{PassedCount=1;FailedCount=0;SkippedCount=1;NotRunCount=0;FailedBlocksCount=0;FailedContainersCount=0;Result='Passed'}
        $value[$Name]=$Raw
        $report=ConvertTo-QuietScriptsTestReport -Result $value -Plan $plan
        $field=switch($Name){'PassedCount'{'Passed'}'SkippedCount'{'Skipped'}'NotRunCount'{'NotRun'}}
        $report[$field]|Should -Be $Count
        $report.Incomplete|Should -Be $Incomplete
    }
    It 'marks a missing <Name> as incomplete only for the reported counts' -ForEach @(
        @{Name='PassedCount';Incomplete=$true};@{Name='FailedCount';Incomplete=$true};@{Name='SkippedCount';Incomplete=$true}
        @{Name='NotRunCount';Incomplete=$false};@{Name='FailedBlocksCount';Incomplete=$false};@{Name='FailedContainersCount';Incomplete=$false}
    ) {
        $value=[ordered]@{PassedCount=2;FailedCount=0;SkippedCount=0;NotRunCount=0;FailedBlocksCount=0;FailedContainersCount=0;Result='Passed'}
        $value.Remove($Name)
        (ConvertTo-QuietScriptsTestReport -Result $value -Plan $plan).Incomplete|Should -Be $Incomplete
    }
    It 'lists the executed cases with their name, result, file and duration' {
        $value=& $result 2 1 0 0 0 'Failed'
        $value.Tests=@(
            [pscustomobject]@{ExpandedPath='D.adds 1';Name='adds <n>';Result='Passed';ScriptBlock=[pscustomobject]@{File='a.Tests.ps1'};Duration=[TimeSpan]::FromMilliseconds(12.345)}
            $null
            [pscustomobject]@{ExpandedPath='';Name='fallback';Result='Failed';ScriptBlock=$null;Duration='slow'}
            @{Name='dictionary';Result='Skipped';ScriptBlock=@{File='b.Tests.ps1'}}
        )
        $cases=@((ConvertTo-QuietScriptsTestReport -Result $value -Plan $plan).Cases)
        $cases.Count|Should -Be 3
        ($cases|ConvertTo-Json -Depth 3 -Compress)|Should -BeExactly (@(
            [ordered]@{Name='D.adds 1';Result='Passed';File='a.Tests.ps1';DurationMs=12.3}
            [ordered]@{Name='fallback';Result='Failed';File='';DurationMs=$null}
            [ordered]@{Name='dictionary';Result='Skipped';File='b.Tests.ps1';DurationMs=$null}
        )|ConvertTo-Json -Depth 3 -Compress)
    }
    It 'reads coverage <Percent> against 80 as met=<Met> incomplete=<Incomplete>' -ForEach @(
        @{Percent=80;Met=$true;Incomplete=$false;Shown=80}
        @{Percent='80.004';Met=$true;Incomplete=$false;Shown=80}
        @{Percent=79.999;Met=$false;Incomplete=$false;Shown=80}
        @{Percent=$true;Met=$false;Incomplete=$true;Shown=$null}
        @{Percent='x';Met=$false;Incomplete=$true;Shown=$null}
        @{Percent=[double]::NaN;Met=$false;Incomplete=$true;Shown=$null}
        @{Percent=$null;Met=$false;Incomplete=$true;Shown=$null}
    ) {
        $value=& $result 1 0 0;$value|Add-Member CodeCoverage ([pscustomobject]@{CoveragePercent=$Percent})
        $report=ConvertTo-QuietScriptsTestReport -Result $value -Plan $plan -CoverageTarget 80
        $report.Coverage.Met|Should -Be $Met
        $report.Coverage.Target|Should -Be 80
        $report.Coverage.Percent|Should -Be $Shown
        $report.Incomplete|Should -Be $Incomplete
        $report.State|Should -BeExactly $(if($Met){'Success'}else{'Failed'})
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
    It 'fills the monitor fields exactly' {
        $started=[DateTimeOffset]::new(2026,1,2,3,4,5,[TimeSpan]::Zero)
        $status=New-QuietScriptsTestStatus -WorkspaceRoot 'W' -Plan $plan -ProcessId 42 -StartedUtc $started
        $status.Project|Should -BeExactly 'FrenchExDev2.QuietCli.Scripts.Tests'
        $status.Task|Should -BeExactly 'Tests scripts (All)'
        $status.Workspace|Should -BeExactly 'W'
        $status.ProjectDirectory|Should -BeExactly $root
        $status.StartedUtc|Should -BeExactly $started.ToString('o')
        $status.ProcessId|Should -Be 42
        $status.Case|Should -BeExactly 'Running 2 test file(s)'
        $status.Passed|Should -Be 0
        $status.Failed|Should -Be 0
        $status.Error|Should -BeNullOrEmpty
        $status.FinishedUtc|Should -BeNullOrEmpty
    }
    It 'accepts the terminal report state <State> and keeps the other fields' -ForEach @(@{State='Success'},@{State='Failed'},@{State='Crash'},@{State='Timeout'},@{State='Cancelled'}) {
        $status=New-QuietScriptsTestStatus -WorkspaceRoot 'W' -Plan $plan -ProcessId 7
        $finished=[DateTimeOffset]::new(2026,1,2,3,4,6,[TimeSpan]::Zero)
        $terminal=Update-QuietScriptsTestStatus -Status $status -Report ([ordered]@{State=$State;Passed=3;Failed=0;Skipped=1;Partial=$false;Incomplete=$false}) -FinishedUtc $finished
        $terminal.State|Should -BeExactly $State
        $terminal.FinishedUtc|Should -BeExactly $finished.ToString('o')
        $terminal.Passed|Should -Be 3
        foreach($field in @('Project','Task','Workspace','ProjectDirectory','Platform','StartedUtc','ProcessId')){$terminal[$field]|Should -Be $status[$field] -Because $field}
        $terminal.Error|Should -BeNullOrEmpty
    }
    It 'summarises partial=<Partial> incomplete=<Incomplete> as <Case>' -ForEach @(
        @{Partial=$false;Incomplete=$false;Case='3 passed, 1 failed, 2 skipped'}
        @{Partial=$true;Incomplete=$false;Case='3 passed, 1 failed, 2 skipped (partial)'}
        @{Partial=$false;Incomplete=$true;Case='3 passed, 1 failed, 2 skipped (incomplete)'}
        @{Partial=$true;Incomplete=$true;Case='3 passed, 1 failed, 2 skipped (partial) (incomplete)'}
    ) {
        $terminal=Update-QuietScriptsTestStatus -Status (New-QuietScriptsTestStatus -WorkspaceRoot 'W' -Plan $plan -ProcessId 7) -Report ([ordered]@{State='Failed';Passed=3;Failed=1;Skipped=2;Partial=$Partial;Incomplete=$Incomplete})
        $terminal.Case|Should -BeExactly $Case
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
        $crash.Case|Should -BeExactly 'Worker failed before a complete report'
        $crash.ProcessId|Should -Be 1
        $crash.FinishedUtc|Should -Match '^\d{4}-\d{2}-\d{2}T'
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

Describe 'Test-QuietScriptsTestsApplicable' {
    # Exhaustive product: test/scripts as a directory, a file or absent, crossed with src/ present or absent.
    It 'returns <Expected> for tests=<Tests> src=<Source>' -ForEach @(
        @{Tests='Directory';Source=$true;Expected='True'}
        @{Tests='Directory';Source=$false;Expected='True'}
        @{Tests='File';Source=$false;Expected='False'}
        @{Tests='Absent';Source=$false;Expected='False'}
        @{Tests='File';Source=$true;Expected='ScriptsTestsRootMissing: test/scripts'}
        @{Tests='Absent';Source=$true;Expected='ScriptsTestsRootMissing: test/scripts'}
    ) {
        $workspace=[IO.Path]::Combine($TestDrive,'applicable-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($workspace,'test'))
        if($Tests -ceq 'Directory'){[void][IO.Directory]::CreateDirectory([IO.Path]::Combine($workspace,'test','scripts'))}
        if($Tests -ceq 'File'){$null=New-QuietTestFile ([IO.Path]::Combine($workspace,'test','scripts')) 'not a tree'}
        if($Source){[void][IO.Directory]::CreateDirectory([IO.Path]::Combine($workspace,'src'))}
        if($Expected -like 'ScriptsTestsRootMissing*'){
            {Test-QuietScriptsTestsApplicable -WorkspaceRoot $workspace}|Should -Throw -ExpectedMessage $Expected
        }else{
            $result=@(Test-QuietScriptsTestsApplicable -WorkspaceRoot $workspace)
            $result.Count|Should -Be 1
            $result[0]|Should -BeOfType [bool]
            [string]$result[0]|Should -BeExactly $Expected
        }
    }
}
