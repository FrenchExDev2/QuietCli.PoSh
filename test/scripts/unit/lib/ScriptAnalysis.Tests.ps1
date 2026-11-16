#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptAnalysis
    $seed=Get-QuietTestSeed
    $typedBaselineError='^ScriptAnalysisBaseline(Missing|Invalid: (syntax|schema|entry|path|hash|count|duplicate))$'
    $newFinding={param([Random]$random)
        [pscustomobject][ordered]@{
            Rule=(Get-QuietRandomItem $random @('RuleA','RuleB','RuleC'));Path=(Get-QuietRandomItem $random @('scripts/a.ps1','scripts/lib/b.psm1'))
            Function=(Get-QuietRandomItem $random @('','F1','F2'));ExtentSHA256=(Get-QuietRandomItem $random @(('A'*64),('B'*64)))
            Line=$random.Next(1,500);Column=1;Severity='Warning';Message='m'
        }
    }
    $newFindings={param([Random]$random)@(1..$random.Next(1,25)|ForEach-Object {& $newFinding $random})}
    $writeBaseline={param([string]$text)
        $path=[IO.Path]::Combine($TestDrive,'baseline-'+[guid]::NewGuid().ToString('N')+'.json');[IO.File]::WriteAllText($path,$text);$path
    }
    $validEntry=[ordered]@{Rule='R';Path='scripts/a.ps1';Function='';ExtentSHA256=('C'*64);Count=1}
    $writeSettings={param([string]$text)
        $path=[IO.Path]::Combine($TestDrive,'settings-'+[guid]::NewGuid().ToString('N')+'.psd1');[IO.File]::WriteAllText($path,$text);$path
    }
    $analyzerManifest=[IO.Path]::Combine((Get-QuietTestWorkspaceRoot),'.cache','test-tools','PSScriptAnalyzer','PSScriptAnalyzer.psd1')
    $rulesPath=[IO.Path]::Combine((Get-QuietTestWorkspaceRoot),'test','scripts','analyzer','QuietCliRules.psm1')
}

Describe 'Compare-QuietScriptAnalysisBaseline' {
    It 'passes when the baseline was built from the same findings, in any order' {
        $null=Invoke-QuietProperty -Name 'baseline accepts its own findings' -Seed $seed -Count 150 -Generator {param($random)
            $findings=& $newFindings $random
            [pscustomobject]@{Findings=$findings;Shuffled=[object[]](Get-QuietShuffle $random $findings)}
        } -Property {param($case)
            $baseline=ConvertTo-QuietScriptAnalysisBaseline -Findings $case.Findings -Analyzer 'A'
            $result=Compare-QuietScriptAnalysisBaseline -Findings $case.Shuffled -Baseline $baseline
            $result.Passed -and $result.Baselined -eq $case.Findings.Count -and $result.New.Count -eq 0 -and $result.Stale.Count -eq 0
        }
    }

    It 'reports exactly the added findings as new' {
        $null=Invoke-QuietProperty -Name 'additions are new' -Seed $seed -Count 150 -Generator {param($random)
            [pscustomobject]@{Old=(& $newFindings $random);Added=(& $newFindings $random)}
        } -Property {param($case)
            $baseline=ConvertTo-QuietScriptAnalysisBaseline -Findings $case.Old -Analyzer 'A'
            $result=Compare-QuietScriptAnalysisBaseline -Findings (@($case.Old)+@($case.Added)) -Baseline $baseline
            !$result.Passed -and $result.New.Count -eq $case.Added.Count -and $result.Stale.Count -eq 0
        }
    }

    It 'reports removed findings as stale and prunes without ever adding an entry' {
        $null=Invoke-QuietProperty -Name 'removals are stale; prune shrinks' -Seed $seed -Count 150 -Generator {param($random)
            $all=& $newFindings $random
            [pscustomobject]@{All=$all;Kept=[object[]](Get-QuietRandomSubset $random $all 0.5)}
        } -Property {param($case)
            $baseline=ConvertTo-QuietScriptAnalysisBaseline -Findings $case.All -Analyzer 'A'
            $result=Compare-QuietScriptAnalysisBaseline -Findings $case.Kept -Baseline $baseline
            if($result.New.Count){throw 'a subset produced a new finding'}
            if(($result.Stale.Count -eq 0) -ne (@($case.Kept).Count -eq $case.All.Count)){throw 'stale iff something was removed'}
            $expected=ConvertTo-QuietScriptAnalysisBaseline -Findings $case.Kept -Analyzer 'A'
            $byKey=@{};foreach($entry in $baseline.Entries){$byKey[(Get-QuietScriptAnalysisFindingKey $entry)]=$entry.Count}
            foreach($entry in $result.Pruned.Entries){
                $key=Get-QuietScriptAnalysisFindingKey $entry
                if(!$byKey.ContainsKey($key) -or $entry.Count -gt $byKey[$key]){throw 'prune added or grew an entry'}
            }
            ($result.Pruned.Entries|ConvertTo-Json -Compress -Depth 3) -ceq ($expected.Entries|ConvertTo-Json -Compress -Depth 3)
        }
    }

    It 'counts duplicates of one key against the baseline count' {
        $one=& $newFinding (New-QuietRandom 1)
        $baseline=ConvertTo-QuietScriptAnalysisBaseline -Findings @($one) -Analyzer 'A'
        $result=Compare-QuietScriptAnalysisBaseline -Findings @($one,$one) -Baseline $baseline
        $result.New.Count|Should -Be 1
        $result.Baselined|Should -Be 1
    }

    It 'passes with no finding and an empty baseline' {
        (Compare-QuietScriptAnalysisBaseline -Findings @() -Baseline ([pscustomobject]@{Analyzer='A';Entries=@()})).Passed|Should -BeTrue
    }
}

Describe 'ConvertTo-QuietScriptAnalysisBaseline' {
    It 'emits ordinal-sorted unique entries whose counts sum to the findings' {
        $null=Invoke-QuietProperty -Name 'baseline shape' -Seed $seed -Count 100 -Generator {param($random)& $newFindings $random} -Property {param($findings)
            $entries=@((ConvertTo-QuietScriptAnalysisBaseline -Findings $findings -Analyzer 'A').Entries)
            $keys=@($entries|ForEach-Object {Get-QuietScriptAnalysisFindingKey $_})
            $sorted=[string[]]$keys.Clone();[Array]::Sort($sorted,[StringComparer]::Ordinal)
            (($entries|Measure-Object Count -Sum).Sum -eq $findings.Count) -and (@($keys|Select-Object -Unique).Count -eq $keys.Count) -and (($keys -join '|') -ceq ($sorted -join '|'))
        }
    }
}

Describe 'Read-QuietScriptAnalysisBaseline' {
    It 'reads a valid document' {
        $path=& $writeBaseline (@{SchemaVersion=1;Analyzer='A';Entries=@($validEntry)}|ConvertTo-Json -Depth 4)
        $baseline=Read-QuietScriptAnalysisBaseline $path
        $baseline.Entries.Count|Should -Be 1
        $baseline.Analyzer|Should -BeExactly 'A'
    }
    It 'rejects a missing file' {
        {Read-QuietScriptAnalysisBaseline ([IO.Path]::Combine($TestDrive,'none.json'))}|Should -Throw -ExpectedMessage 'ScriptAnalysisBaselineMissing'
    }
    It 'rejects <Reason>' -ForEach @(
        @{Reason='syntax';Text='{'}
        @{Reason='schema';Text='{"SchemaVersion":2,"Entries":[]}'}
        @{Reason='schema';Text='[1]'}
        @{Reason='entry';Text='{"SchemaVersion":1,"Entries":[{"Rule":"","Path":"a","Function":"","ExtentSHA256":"x","Count":1}]}'}
        @{Reason='path';Text=('{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"../a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":1}]}')}
        @{Reason='path';Text=('{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"/a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":1}]}')}
        @{Reason='path';Text=('{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"C:/a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":1}]}')}
        @{Reason='hash';Text='{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"a.ps1","Function":"","ExtentSHA256":"abc","Count":1}]}'}
        @{Reason='count';Text=('{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":0}]}')}
        @{Reason='count';Text=('{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":"1"}]}')}
        @{Reason='count';Text=('{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":1.5}]}')}
        @{Reason='duplicate';Text=('{"SchemaVersion":1,"Entries":[{"Rule":"R","Path":"a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":1},{"Rule":"R","Path":"a.ps1","Function":"","ExtentSHA256":"'+('C'*64)+'","Count":2}]}')}
    ) {
        $path=& $writeBaseline $Text
        {Read-QuietScriptAnalysisBaseline $path}|Should -Throw -ExpectedMessage "ScriptAnalysisBaseline*: $Reason"
    }
    It 'fails only with typed errors on fuzzed documents' {
        $null=Invoke-QuietProperty -Name 'fuzzed baseline documents' -Seed $seed -Count 300 -Generator {param($random)
            $entry=[ordered]@{}
            foreach($name in @('Rule','Path','Function','ExtentSHA256','Count')){
                if($random.NextDouble() -lt 0.85){$entry[$name]=Get-QuietRandomItem $random @($validEntry[$name],$null,'',(New-QuietFuzzPath $random),7,-1,(New-QuietRandomSha256 $random),@(1),@{a=1})}
            }
            $document=[ordered]@{SchemaVersion=(Get-QuietRandomItem $random @(1,1,1,0,'1',$null));Entries=@(1..$random.Next(0,4)|ForEach-Object {Get-QuietRandomItem $random @($entry,$null,3,'x')})}
            $text=$document|ConvertTo-Json -Depth 5 -Compress
            if($random.NextDouble() -lt 0.1){$text=$text.Substring(0,$random.Next(0,$text.Length))}
            $text
        } -Property {param($text)
            $path=& $writeBaseline $text
            try{$null=Read-QuietScriptAnalysisBaseline $path}catch{if($_.Exception.Message -notmatch $typedBaselineError){throw "untyped error: $($_.Exception.Message)"}}
            $true
        }
    }
}

Describe 'Read-QuietScriptAnalysisSettings' {
    It 'reads the repository settings with a reason for every exclusion' {
        $settings=Read-QuietScriptAnalysisSettings ([IO.Path]::Combine((Get-QuietTestWorkspaceRoot),'test','scripts','ScriptAnalyzerSettings.psd1'))
        $settings.Settings.Severity|Should -Be @('Error','Warning')
        $settings.Settings.ExcludeRules|Should -Contain 'PSAvoidUsingWriteHost'
        $settings.TestSettings.ExcludeRules|Should -Contain 'PSUseDeclaredVarsMoreThanAssignments'
        $settings.Settings.ExcludeRules|Should -Not -Contain 'PSUseDeclaredVarsMoreThanAssignments'
        $settings.SHA256|Should -Match '^[0-9A-F]{64}$'
    }
    It 'hashes the same content written in another order identically' {
        $one=& $writeSettings "@{Severity=@('Warning','Error');ExcludeRules=@('B','A');ExclusionReasons=@{A='aaaaaaaaaaaaaaaaaaaaaaaa';B='bbbbbbbbbbbbbbbbbbbbbbbb'}}"
        $two=& $writeSettings "@{ExclusionReasons=@{B='bbbbbbbbbbbbbbbbbbbbbbbb';A='aaaaaaaaaaaaaaaaaaaaaaaa'};ExcludeRules=@('A','B');Severity=@('Error','Warning')}"
        (Read-QuietScriptAnalysisSettings $one).SHA256|Should -BeExactly (Read-QuietScriptAnalysisSettings $two).SHA256
    }
    It 'rejects <Reason>' -ForEach @(
        @{Reason='syntax';Text='@{'}
        @{Reason='key';Text="@{Severity=@('Error');Rules=@{}}"}
        @{Reason='severity';Text="@{Severity=@()}"}
        @{Reason='severity';Text="@{Severity=@('Fatal')}"}
        @{Reason='reason';Text="@{Severity=@('Error');ExcludeRules=@('A')}"}
        @{Reason='reason';Text="@{Severity=@('Error');ExcludeRules=@('A');ExclusionReasons=@{A='short'}}"}
        @{Reason='orphan-reason';Text="@{Severity=@('Error');ExclusionReasons=@{A='aaaaaaaaaaaaaaaaaaaaaaaa'}}"}
        @{Reason='duplicate';Text="@{Severity=@('Error');ExcludeRules=@('A');TestExcludeRules=@('A');ExclusionReasons=@{A='aaaaaaaaaaaaaaaaaaaaaaaa'}}"}
        @{Reason='reasons';Text="@{Severity=@('Error');ExclusionReasons='x'}"}
    ) {
        $path=& $writeSettings $Text
        {Read-QuietScriptAnalysisSettings $path}|Should -Throw -ExpectedMessage "ScriptAnalysisSettingsInvalid: $Reason"
    }
    It 'rejects a missing file' {
        {Read-QuietScriptAnalysisSettings ([IO.Path]::Combine($TestDrive,'none.psd1'))}|Should -Throw -ExpectedMessage 'ScriptAnalysisSettingsMissing'
    }
}

Describe 'Findings and keys' {
    It 'classifies <Path> as test container: <Expected>' -ForEach @(
        @{Path='test/scripts/unit/lib/A.Tests.ps1';Expected=$true}
        @{Path='test\scripts\integration\B.Tests.ps1';Expected=$true}
        @{Path='test/scripts/support/Generators.psm1';Expected=$false}
        @{Path='scripts/A.Tests.ps1';Expected=$false}
        @{Path='test/scripts/unit/a.tests.ps1';Expected=$false}
    ) {
        Test-QuietScriptAnalysisTestContainer $Path|Should -Be $Expected
    }
    It 'names the innermost enclosing function, or none at file level' {
        $ast=[Management.Automation.Language.Parser]::ParseInput("`$x=1`nfunction Outer {`n  function Inner { Join-Path a b }`n  Get-Item .`n}",[ref]$null,[ref]$null)
        $join=$ast.Find({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Join-Path'},$true)
        $item=$ast.Find({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-Item'},$true)
        Get-QuietScriptAnalysisFunctionName -Ast $ast -StartOffset $join.Extent.StartOffset -EndOffset $join.Extent.EndOffset|Should -BeExactly 'Inner'
        Get-QuietScriptAnalysisFunctionName -Ast $ast -StartOffset $item.Extent.StartOffset -EndOffset $item.Extent.EndOffset|Should -BeExactly 'Outer'
        Get-QuietScriptAnalysisFunctionName -Ast $ast -StartOffset 0 -EndOffset 2|Should -BeExactly ''
    }
    It 'keys a finding independently of line endings, line number and path separators' {
        $ast=[Management.Automation.Language.Parser]::ParseInput('Join-Path a b',[ref]$null,[ref]$null)
        $extent={param($text)[pscustomobject]@{Text=$text;StartOffset=0;EndOffset=13}}
        $one=ConvertTo-QuietScriptAnalysisFinding -Record ([pscustomobject]@{RuleName='R';Extent=(& $extent "a`r`nb");Line=1;Column=1;Severity='Warning';Message='m'}) -RelativePath 'scripts\a.ps1' -Ast $ast
        $two=ConvertTo-QuietScriptAnalysisFinding -Record ([pscustomobject]@{RuleName='R';Extent=(& $extent "a`nb");Line=9;Column=4;Severity='Warning';Message='m'}) -RelativePath 'scripts/a.ps1' -Ast $ast
        $one.Path|Should -BeExactly 'scripts/a.ps1'
        Get-QuietScriptAnalysisFindingKey $one|Should -BeExactly (Get-QuietScriptAnalysisFindingKey $two)
    }
    It 'accepts a record without extent' {
        $ast=[Management.Automation.Language.Parser]::ParseInput('1',[ref]$null,[ref]$null)
        $finding=ConvertTo-QuietScriptAnalysisFinding -Record ([pscustomobject]@{RuleName='R';Extent=$null;Line=0;Column=0;Severity='Error';Message='m'}) -RelativePath 'a.ps1' -Ast $ast
        $finding.ExtentSHA256|Should -BeExactly (Get-QuietScriptAnalysisSha256 '')
        $finding.Function|Should -BeExactly ''
    }
    It 'changes the cache key when any input changes and ignores separator and hash case' {
        $null=Invoke-QuietProperty -Name 'cache key sensitivity' -Seed $seed -Count 100 -Generator {param($random)
            [pscustomobject]@{Path=('scripts/'+(New-QuietRandomString $random)+'.ps1');Content=(New-QuietRandomSha256 $random);Configuration=(New-QuietRandomSha256 $random);Other=(New-QuietRandomSha256 $random)}
        } -Property {param($case)
            $key=Get-QuietScriptAnalysisCacheKey -RelativePath $case.Path -ContentSHA256 $case.Content -ConfigurationSHA256 $case.Configuration
            ($key -ceq (Get-QuietScriptAnalysisCacheKey -RelativePath $case.Path.Replace('/','\') -ContentSHA256 $case.Content.ToLowerInvariant() -ConfigurationSHA256 $case.Configuration)) -and
            ($key -cne (Get-QuietScriptAnalysisCacheKey -RelativePath ($case.Path+'x') -ContentSHA256 $case.Content -ConfigurationSHA256 $case.Configuration)) -and
            ($key -cne (Get-QuietScriptAnalysisCacheKey -RelativePath $case.Path -ContentSHA256 $case.Other -ConfigurationSHA256 $case.Configuration)) -and
            ($key -cne (Get-QuietScriptAnalysisCacheKey -RelativePath $case.Path -ContentSHA256 $case.Content -ConfigurationSHA256 $case.Other))
        }
    }
}

Describe 'Get-QuietScriptAnalysisFiles' {
    It 'lists only .ps1 and .psm1 under scripts/ and test/scripts/, sorted in ordinal order' {
        $root=[IO.Path]::Combine($TestDrive,'files')
        foreach($relative in @('scripts/b.ps1','scripts/A.ps1','scripts/lib/c.psm1','scripts/d.psd1','scripts/e.md','test/scripts/unit/x.Tests.ps1','test/other/y.ps1','src/z.ps1')){$null=New-QuietTestFile ([IO.Path]::Combine($root,$relative)) '1'}
        @(Get-QuietScriptAnalysisFiles $root)|Should -Be @('scripts/A.ps1','scripts/b.ps1','scripts/lib/c.psm1','test/scripts/unit/x.Tests.ps1')
    }
    It 'returns nothing for a workspace without those areas' {
        @(Get-QuietScriptAnalysisFiles ([IO.Path]::Combine($TestDrive,'empty'))).Count|Should -Be 0
    }
    It 'skips linked directories' {
        $root=[IO.Path]::Combine($TestDrive,'linked');$null=New-QuietTestFile ([IO.Path]::Combine($root,'scripts','a.ps1')) '1'
        $outside=[IO.Path]::Combine($TestDrive,'outside');$null=New-QuietTestFile ([IO.Path]::Combine($outside,'b.ps1')) '1'
        try{$null=New-Item -ItemType Junction -Path ([IO.Path]::Combine($root,'scripts','lib')) -Target $outside -ErrorAction Stop}catch{Set-ItResult -Skipped -Because 'this host cannot create a directory link';return}
        @(Get-QuietScriptAnalysisFiles $root)|Should -Be @('scripts/a.ps1')
    }
}

Describe 'QuietCliRules' {
    BeforeAll {
        $available=[IO.File]::Exists($analyzerManifest)
        if($available){
            Import-Module $analyzerManifest -DisableNameChecking -ErrorAction Stop
            Import-Module $rulesPath -Force -DisableNameChecking -ErrorAction Stop
        }
        $parse={param([string]$relative,[string]$text)
            $path=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'rules',[guid]::NewGuid().ToString('N'),$relative)) $text
            [Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$null)
        }
    }
    BeforeEach {
        if(!$available){Set-ItResult -Skipped -Because 'the pinned PSScriptAnalyzer is not cached (run Initialize-TestTools.ps1)'}
    }
    It 'flags Join-Path anywhere in a file' {
        $ast=& $parse 'scripts/lib/a.psm1' "function F { Join-Path a b }`njoin-path c d"
        @(Measure-QuietJoinPath -ScriptBlockAst $ast).Count|Should -Be 2
        @(Measure-QuietJoinPath -ScriptBlockAst (& $parse 'scripts/lib/a.psm1' "[IO.Path]::Combine('a','b')")).Count|Should -Be 0
    }
    It 'flags functions in scripts/*.ps1 entry points only' {
        $text="function Helper { 1 }"
        @(Measure-QuietEntryPointFunction -ScriptBlockAst (& $parse 'scripts/Entry.ps1' $text)).Count|Should -Be 1
        @(Measure-QuietEntryPointFunction -ScriptBlockAst (& $parse 'scripts/lib/Lib.psm1' $text)).Count|Should -Be 0
        @(Measure-QuietEntryPointFunction -ScriptBlockAst (& $parse 'test/scripts/Helper.ps1' $text)).Count|Should -Be 0
        @(Measure-QuietEntryPointFunction -ScriptBlockAst (& $parse 'scripts/lib/nested.ps1' $text)).Count|Should -Be 0
    }
    It 'requires -ErrorAction Stop on Import-Module: <Text>' -ForEach @(
        @{Text="Import-Module x -DisableNameChecking -ErrorAction Stop";Expected=0}
        @{Text="Import-Module x -ErrorAction:Stop";Expected=0}
        @{Text="Import-Module x -erroraction stop";Expected=0}
        @{Text="Import-Module x -DisableNameChecking";Expected=1}
        @{Text="Import-Module x -ErrorAction Continue";Expected=1}
        @{Text="Import-Module x -ErrorAction `$mode";Expected=1}
        @{Text="Import-Module x -ErrorAction";Expected=1}
    ) {
        @(Measure-QuietImportErrorAction -ScriptBlockAst (& $parse 'scripts/lib/a.psm1' $Text)).Count|Should -Be $Expected
    }
    It 'inspects only the file root' {
        $ast=& $parse 'scripts/Entry.ps1' "function F { Join-Path a b; Import-Module x }"
        $inner=$ast.Find({param($n)$n -is [Management.Automation.Language.ScriptBlockAst] -and $null -ne $n.Parent},$true)
        @(Measure-QuietJoinPath -ScriptBlockAst $inner).Count|Should -Be 0
        @(Measure-QuietImportErrorAction -ScriptBlockAst $inner).Count|Should -Be 0
        @(Measure-QuietEntryPointFunction -ScriptBlockAst $inner).Count|Should -Be 0
    }
}
