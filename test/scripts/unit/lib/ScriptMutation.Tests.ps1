#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptMutation
    $null=Import-QuietTestLibrary -Name ScriptMutators
    $seed=Get-QuietTestSeed
    $source=@'
function Get-A {
    param([int]$Value)
    if($Value -gt 1){return 'big'}
    'small'
}

function Get-B { $true -and $false }

function Get-C { 'untouched' }
'@
    $typedTargetsError='^ScriptMutationTargets(Missing|Invalid: (syntax|shape|name|duplicate|module|functions|tests|break|inputs|equivalent))$'
    $scripts=[IO.Path]::Combine($TestDrive,'scripts');$tests=[IO.Path]::Combine($TestDrive,'tests')
    $null=New-QuietTestFile ([IO.Path]::Combine($scripts,'lib','A.psm1')) $source
    $null=New-QuietTestFile ([IO.Path]::Combine($tests,'unit','lib','A.Tests.ps1')) 'Describe a { It b { } }'
    $null=New-QuietTestFile ([IO.Path]::Combine($tests,'integration','A.Tests.ps1')) 'Describe a { It b { } }'
    $writeTargets={param([string]$Text)
        $path=[IO.Path]::Combine($TestDrive,'targets-'+[guid]::NewGuid().ToString('N')+'.psd1');[IO.File]::WriteAllText($path,$Text);$path
    }
    $readTargets={param([string]$Text)Read-QuietScriptMutationTargets -Path (& $writeTargets $Text) -ScriptsRoot $scripts -TestsRoot $tests}
    $validTarget="@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80}"
    $newResult={param([string]$Target,[string]$Status,[int]$Line=1)[pscustomobject]@{Target=$Target;Status=$Status;Id='id'+$Line;Function='F';Mutator='M';Line=$Line;Column=2;Original='a|b';Replacement='`x`'}}
}

Describe 'Get-QuietScriptMutants' {
    It 'mutates only the named functions, in source order, with unique ids' {
        $mutants=@(Get-QuietScriptMutants -Text $source -Functions @('Get-A','Get-B') -Module 'lib/A.psm1')
        $mutants.Count|Should -BeGreaterThan 5
        @($mutants.Function|Sort-Object -Unique)|Should -Be @('Get-A','Get-B')
        @($mutants.Id|Sort-Object -Unique).Count|Should -Be $mutants.Count
        $offsets=@($mutants.StartOffset);$offsets|Should -Be @($offsets|Sort-Object)
        $end=$source.IndexOf('function Get-C')
        @($mutants|Where-Object EndOffset -GT $end).Count|Should -Be 0
        foreach($mutant in $mutants){$source.Substring($mutant.StartOffset,$mutant.EndOffset-$mutant.StartOffset)|Should -BeExactly $mutant.Original}
        @($mutants|Where-Object Mutator -CEQ 'LogicalOperator').Count|Should -Be 1
        @($mutants|Where-Object Mutator -CEQ 'EqualityOperator'|ForEach-Object Replacement)|Should -Be @('-ge','-le')
    }

    It 'keeps ids stable across runs and edits after the function, and changes them with the module path' {
        $first=@(Get-QuietScriptMutants -Text $source -Functions @('Get-A') -Module 'lib/A.psm1').Id
        $again=@(Get-QuietScriptMutants -Text ($source+"`nfunction Get-D { 1 -eq 2 }`n") -Functions @('Get-A') -Module 'lib/A.psm1').Id
        $moved=@(Get-QuietScriptMutants -Text $source -Functions @('Get-A') -Module 'lib/B.psm1').Id
        $again|Should -Be $first
        @($moved|Where-Object {$_ -in $first}).Count|Should -Be 0
        foreach($id in $first){$id|Should -MatchExactly '^[0-9a-f]{12}$'}
    }

    It 'drops duplicate and no-op candidates' {
        # On a literal condition BooleanLiteral and ConditionalExpression both propose $false, and ConditionalExpression also proposes $true unchanged.
        $mutants=@(Get-QuietScriptMutants -Text "function F { if(`$true){1} }" -Functions @('F') -Module 'lib/F.psm1')
        @($mutants|ForEach-Object {"$($_.Mutator):$($_.StartOffset):$($_.EndOffset):$($_.Replacement)"}) -join '|'|Should -BeExactly 'BooleanLiteral:16:21:$false|BlockStatement:22:25:{}'
    }

    It 'finds a target function defined inside a script block' {
        $mutants=@(Get-QuietScriptMutants -Text "`$x={ function G { 1 -eq 2 } }" -Functions @('G') -Module 'lib/G.psm1')
        @($mutants.Mutator)|Should -Contain 'EqualityOperator'
    }

    It 'rejects <Case>' -ForEach @(
        @{Case='a missing function';Text='function F { 1 }';Functions=@('G');Expected='ScriptMutationFunctionMissing: G'}
        @{Case='a function defined twice';Text="function F { 1 }`nfunction F { 2 }";Functions=@('F');Expected='ScriptMutationFunctionMissing: F'}
        @{Case='a source that does not parse';Text='function F { (';Functions=@('F');Expected='ScriptMutationSourceInvalid: lib/F.psm1'}
    ) {
        {Get-QuietScriptMutants -Text $Text -Functions $Functions -Module 'lib/F.psm1'}|Should -Throw -ExpectedMessage $Expected
    }

    It 'matches function names case-sensitively' {
        {Get-QuietScriptMutants -Text 'function Get-A { 1 }' -Functions @('get-a') -Module 'lib/A.psm1'}|Should -Throw -ExpectedMessage 'ScriptMutationFunctionMissing: get-a'
    }
}

Describe 'New-QuietScriptMutantSource' {
    It 'replaces exactly the mutant extent' {
        $mutant=@(Get-QuietScriptMutants -Text $source -Functions @('Get-B') -Module 'lib/A.psm1'|Where-Object Mutator -CEQ 'LogicalOperator')[0]
        $result=New-QuietScriptMutantSource -Text $source -Mutant $mutant
        $result.Compiles|Should -BeTrue
        $result.Text|Should -BeExactly $source.Replace('$true -and $false','$true -or $false')
    }

    It 'reports a replacement that no longer parses' {
        $mutant=[pscustomobject]@{Id='x';StartOffset=0;EndOffset=8;Original='function';Replacement='function ('}
        $result=New-QuietScriptMutantSource -Text $source -Mutant $mutant
        $result.Compiles|Should -BeFalse
        $result.Text|Should -BeLike 'function (*'
    }

    It 'rejects a mutant whose extent does not match the text (<Case>)' -ForEach @(
        @{Case='other text';Start=0;End=8;Original='funktion'}
        @{Case='negative start';Start=-1;End=2;Original='fu'}
        @{Case='end before start';Start=5;End=4;Original=''}
        @{Case='end past the text';Start=0;End=100000;Original='x'}
    ) {
        $mutant=[pscustomobject]@{Id='m1';StartOffset=$Start;EndOffset=$End;Original=$Original;Replacement=''}
        {New-QuietScriptMutantSource -Text $source -Mutant $mutant}|Should -Throw -ExpectedMessage 'ScriptMutationOffsetMismatch: m1'
    }

    It 'accepts an empty extent at the end of the text' {
        $result=New-QuietScriptMutantSource -Text 'a' -Mutant ([pscustomobject]@{Id='e';StartOffset=1;EndOffset=1;Original='';Replacement='b'})
        $result.Text|Should -BeExactly 'ab'
    }

    It 'every generated mutant of the fixture can be applied' {
        foreach($mutant in Get-QuietScriptMutants -Text $source -Functions @('Get-A','Get-B','Get-C') -Module 'lib/A.psm1'){
            (New-QuietScriptMutantSource -Text $source -Mutant $mutant).Compiles|Should -BeTrue -Because "$($mutant.Mutator) $($mutant.Original) -> $($mutant.Replacement)"
        }
    }
}

Describe 'Get-QuietScriptMutantStatus' {
    It 'classifies state <State>, failed <Failed>, timed out <TimedOut> as <Expected>' -ForEach @(
        @{State='Success';Failed=0;TimedOut=$false;Expected='Survived'}
        @{State='Success';Failed=1;TimedOut=$false;Expected='Killed'}
        @{State='Failed';Failed=0;TimedOut=$false;Expected='Killed'}
        @{State='Failed';Failed=3;TimedOut=$false;Expected='Killed'}
        @{State='Crash';Failed=1;TimedOut=$false;Expected='Killed'}
        @{State='Cancelled';Failed=0;TimedOut=$false;Expected='Killed'}
        @{State='';Failed=0;TimedOut=$false;Expected='Killed'}
        @{State='success';Failed=0;TimedOut=$false;Expected='Killed'}
        @{State='Timeout';Failed=1;TimedOut=$false;Expected='Timeout'}
        @{State='Success';Failed=0;TimedOut=$true;Expected='Timeout'}
        @{State='';Failed=0;TimedOut=$true;Expected='Timeout'}
    ) {
        Get-QuietScriptMutantStatus -State $State -Failed $Failed -TimedOut:$TimedOut|Should -BeExactly $Expected
    }
}

Describe 'Get-QuietScriptMutantTimeout' {
    It 'returns <Expected> s for a <Seconds> s baseline' -ForEach @(
        @{Seconds=0;Expected=60}
        @{Seconds=10;Expected=60}
        @{Seconds=10.1;Expected=61}
        @{Seconds=20;Expected=90}
        @{Seconds=100;Expected=330}
    ) {
        Get-QuietScriptMutantTimeout -BaselineSeconds $Seconds|Should -Be $Expected
    }

    It 'rejects <Seconds>' -ForEach @(@{Seconds=-1},@{Seconds=[double]::NaN},@{Seconds=[double]::PositiveInfinity}) {
        {Get-QuietScriptMutantTimeout -BaselineSeconds $Seconds}|Should -Throw -ExpectedMessage 'ScriptMutationBaselineDurationInvalid'
    }
}

Describe 'Get-QuietScriptMutationFocus' {
    It 'runs each function''s own top-level blocks first and every other top-level block after' {
        $one=@'
Describe 'Get-A' { It a { } ; Context 'Get-B inside' { It b { } } }
Describe 'Get-A and Get-B' { It ab { } }
Describe 'Get-AB' { It x { } }
'@
        $two="Context 'Get-B over a graph' { It c { } }`nDescribe -Name 'Set-C' { It d { } }`nDescribe 'misc' { It e { } }`n"
        $focus=Get-QuietScriptMutationFocus -Sources @($one,$two) -Functions @('Get-A','Get-B','Set-C','Get-Z')
        @($focus.Keys)|Should -Be @('Get-A','Get-B','Set-C')
        $focus['Get-A'].Focus|Should -Be @('Get-A','Get-A and Get-B')
        $focus['Get-A'].Rest|Should -Be @('Get-AB','Get-B over a graph','Set-C','misc')
        $focus['Get-B'].Focus|Should -Be @('Get-A and Get-B','Get-B over a graph') -Because 'a nested Context does not count, a top-level one does'
        $focus['Get-B'].Rest|Should -Be @('Get-A','Get-AB','Set-C','misc')
        $focus['Set-C'].Focus|Should -Be @('Set-C')
        ,$focus['Set-C'].Rest|Should -BeOfType [string[]]
        ,$focus['Set-C'].Focus|Should -BeOfType [string[]]
    }

    It 'escapes the wildcard characters of a block name' {
        $focus=Get-QuietScriptMutationFocus -Sources @("Describe 'Get-A [x]*?' { It a { } }`nDescribe 'b?' { It b { } }") -Functions @('Get-A')
        $focus['Get-A'].Focus|Should -Be @('Get-A `[x`]`*`?')
        $focus['Get-A'].Rest|Should -Be @('b`?')
        'Get-A [x]*?' -like $focus['Get-A'].Focus[0]|Should -BeTrue
        'Get-A [x]*?!' -like $focus['Get-A'].Focus[0]|Should -BeFalse
    }

    It 'merges block names that differ only by case, as Pester filters ignore case' {
        $focus=Get-QuietScriptMutationFocus -Sources @("Describe 'Get-A' { It a { } }","Describe 'get-a' { It b { } }`nDescribe 'other' { It c { } }") -Functions @('Get-A')
        $focus['Get-A'].Focus|Should -Be @('Get-A')
        $focus['Get-A'].Rest|Should -Be @('other')
    }

    It 'gives no entry to <Case>' -ForEach @(
        @{Case='a function without its own block';Sources=@("Describe 'Get-A' { It a { } }`nDescribe 'b' { It b { } }");Function='Get-Z'}
        @{Case='a function that owns every block';Sources=@("Describe 'Get-A' { It a { } }`nDescribe 'Get-A edge cases' { It b { } }");Function='Get-A'}
        @{Case='a name that only starts the same';Sources=@("Describe 'Get-AB' { It a { } }`nDescribe 'b' { It b { } }");Function='Get-A'}
        @{Case='a name that only ends the same';Sources=@("Describe 'X-Get-A' { It a { } }`nDescribe 'b' { It b { } }");Function='Get-A'}
        @{Case='a name in another case';Sources=@("Describe 'get-a' { It a { } }`nDescribe 'b' { It b { } }");Function='Get-A'}
    ) {
        $focus=Get-QuietScriptMutationFocus -Sources $Sources -Functions @($Function)
        $focus.Count|Should -Be 0
    }

    It 'splits nothing when <Case>, because the other blocks could not be listed' -ForEach @(
        @{Case='a source does not parse';Source="Describe 'Get-A' { It a { } }`nDescribe 'b' { It b { } }`n`$x=("}
        @{Case='a block name is expanded';Source="Describe 'Get-A' { It a { } }`nDescribe `"b `$x`" { It b { } }"}
        @{Case='a block name is a variable';Source="Describe 'Get-A' { It a { } }`nDescribe `$name { It b { } }"}
        @{Case='a block name follows another parameter';Source="Describe 'Get-A' { It a { } }`nDescribe -Tag t 'b' { It b { } }"}
        @{Case='a named block name is expanded';Source="Describe 'Get-A' { It a { } }`nDescribe -Name `"b`$x`" { It b { } }"}
    ) {
        $focus=Get-QuietScriptMutationFocus -Sources @($Source) -Functions @('Get-A')
        $focus -is [Collections.Specialized.OrderedDictionary]|Should -BeTrue -Because 'the worker looks functions up in the map'
        $focus.Count|Should -Be 0
    }

    It 'counts a top-level block declared inside a script block, so Rest does not miss its tests' {
        $focus=Get-QuietScriptMutationFocus -Sources @("Describe 'Get-A' { It a { } }`n& { Describe 'b' { It b { } } }") -Functions @('Get-A')
        $focus['Get-A'].Rest|Should -Be @('b')
    }

    It 'reads a name given as -Name:value' {
        $focus=Get-QuietScriptMutationFocus -Sources @("Describe -Name:'Get-A' { It a { } }`nDescribe 'b' { It b { } }") -Functions @('Get-A')
        $focus['Get-A'].Focus|Should -Be @('Get-A')
    }

    It 'returns an empty map for no source or no function' {
        (Get-QuietScriptMutationFocus -Sources @() -Functions @('Get-A')).Count|Should -Be 0
        (Get-QuietScriptMutationFocus -Sources @("Describe 'Get-A' { It a { } }`nDescribe 'b' { }") -Functions @()).Count|Should -Be 0
    }

    It 'partitions the top-level blocks for any catalogue of names' {
        $null=Invoke-QuietProperty -Name 'focus partition' -Seed $seed -Count 150 -Generator {param($random)
            $functions=@(1..$random.Next(1,5)|ForEach-Object {'Get-F'+$_})
            $words=@($functions)+@('edge','cases','and','[x]','*','Get-F1x')
            $names=@(1..$random.Next(1,8)|ForEach-Object {(@(1..$random.Next(1,4)|ForEach-Object {Get-QuietRandomItem $random $words}) -join ' ')})
            $files=$random.Next(1,4)
            $sources=@(foreach($file in 1..$files){(@($names|Where-Object {$file -eq 1 -or $random.Next(0,2) -eq 0})|ForEach-Object {"Describe '$_' { It t { } }"}) -join "`n"})
            [pscustomobject]@{Functions=$functions;Sources=$sources}
        } -Property {param($case)
            $all=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach($text in $case.Sources){foreach($match in [regex]::Matches($text,"Describe '([^']*)'")){[void]$all.Add($match.Groups[1].Value)}}
            $focus=Get-QuietScriptMutationFocus -Sources $case.Sources -Functions $case.Functions
            foreach($function in $case.Functions){
                $word='(?<![\w-])'+[regex]::Escape($function)+'(?![\w-])'
                $own=@($all|Where-Object {$_ -cmatch $word})
                if($focus.Contains($function) -ne ($own.Count -gt 0 -and $own.Count -lt $all.Count)){return $false}
                if(!$focus.Contains($function)){continue}
                $entry=$focus[$function]
                foreach($name in $all){
                    # Every block is selected by exactly one pattern, in Focus exactly when it names the function.
                    $inFocus=@($entry.Focus|Where-Object {$name -like $_}).Count
                    $inRest=@($entry.Rest|Where-Object {$name -like $_}).Count
                    if($inFocus+$inRest -ne 1){return $false}
                    if(($inFocus -eq 1) -ne ($name -cin $own)){return $false}
                }
            }
            $true
        }
    }
}

Describe 'Measure-QuietScriptMutationScore' {
    It 'counts every status, ignores compile errors in the score and passes exactly at the break' {
        $null=Invoke-QuietProperty -Name 'score model' -Seed $seed -Count 300 -Generator {param($random)
            [pscustomobject]@{
                Results=@(1..$random.Next(0,40)|ForEach-Object {[pscustomobject]@{Status=(Get-QuietRandomItem $random @('Killed','Survived','Timeout','CompileError'))}})
                Break=$random.Next(0,101)
            }
        } -Property {param($case)
            $score=Measure-QuietScriptMutationScore -Results $case.Results -Break $case.Break
            $killed=@($case.Results|Where-Object Status -CEQ 'Killed').Count;$survived=@($case.Results|Where-Object Status -CEQ 'Survived').Count
            $timeout=@($case.Results|Where-Object Status -CEQ 'Timeout').Count;$compile=@($case.Results|Where-Object Status -CEQ 'CompileError').Count
            $strict=$case.Break -eq 100
            $valid=if($strict){$killed+$survived+$timeout+$compile}else{$killed+$survived+$timeout}
            $detected=if($strict){$killed}else{$killed+$timeout}
            $expected=if($valid){[Math]::Round(100.0*$detected/$valid,2)}elseif($strict){0.0}else{100.0}
            $passed=if($strict){$valid -gt 0 -and $killed -eq $valid}else{$expected -ge $case.Break}
            $score.Killed -eq $killed -and $score.Survived -eq $survived -and $score.Timeout -eq $timeout -and $score.CompileError -eq $compile -and
                $score.Valid -eq $valid -and $score.Score -eq $expected -and $score.Score -ge 0 -and $score.Score -le 100 -and
                $score.Passed -eq $passed -and $score.Break -eq $case.Break
        }
    }

    It 'preserves legacy thresholds and requires evidence at 100' {
        (Measure-QuietScriptMutationScore -Results @() -Break 99).Passed|Should -BeTrue
        $strict=Measure-QuietScriptMutationScore -Results @() -Break 100
        $strict.Passed|Should -BeFalse
        $strict.Score|Should -Be 0
        $all=Measure-QuietScriptMutationScore -Results @([pscustomobject]@{Status='Survived'},[pscustomobject]@{Status='CompileError'}) -Break 1
        $all.Score|Should -Be 0
        $all.Passed|Should -BeFalse
    }

    It 'requires a killed mutant and excludes reviewed equivalences' {
        $results=@([pscustomobject]@{Status='Killed'},[pscustomobject]@{Status='Equivalent'})
        $score=Measure-QuietScriptMutationScore -Results $results -Break 100
        $score.Passed|Should -BeTrue
        $score.Valid|Should -Be 1
        (Measure-QuietScriptMutationScore -Results @($results[1]) -Break 100).Passed|Should -BeFalse
    }

    It 'rejects a single <Status> at Break 100' -ForEach @(
        @{Status='Timeout'},@{Status='CompileError'},@{Status='Survived'}
    ) {
        $results=@([pscustomobject]@{Status='Killed'},[pscustomobject]@{Status=$Status})
        $score=Measure-QuietScriptMutationScore -Results $results -Break 100
        $score.Passed|Should -BeFalse
        $score.Score|Should -Be 50
    }

    It 'rejects a survivor even when the displayed score rounds to 100' {
        $results=@([pscustomobject]@{Status='Killed'})*20000+@([pscustomobject]@{Status='Survived'})
        $score=Measure-QuietScriptMutationScore -Results $results -Break 100
        $score.Score|Should -Be 100
        $score.Passed|Should -BeFalse
    }

    It 'rounds to two decimals' {
        (Measure-QuietScriptMutationScore -Results @([pscustomobject]@{Status='Killed'},[pscustomobject]@{Status='Survived'},[pscustomobject]@{Status='Survived'})).Score|Should -Be 33.33
    }

    It 'rejects an unknown status' {
        {Measure-QuietScriptMutationScore -Results @([pscustomobject]@{Status='killed'})}|Should -Throw -ExpectedMessage 'ScriptMutationStatusInvalid: killed'
    }
}

Describe 'Read-QuietScriptMutationTargets' {
    It 'returns validated targets with resolved module paths' {
        $targets=@(& $readTargets "@{Targets=@($validTarget;@{Name='B';Module='lib/A.psm1';Functions=@('Get-B','Get-C');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=0})}")
        $targets.Count|Should -Be 2
        $targets[0].Name|Should -BeExactly 'A'
        $targets[0].ModulePath|Should -Be ([IO.Path]::GetFullPath([IO.Path]::Combine($scripts,'lib/A.psm1')))
        $targets[1].Functions|Should -Be @('Get-B','Get-C')
        $targets[1].Break|Should -Be 0
        $targets[0].Inputs.Count|Should -Be 0 -Because 'Inputs is optional'
    }

    It 'accepts the full break of 100' {
        (& $readTargets "@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=100})}").Break|Should -Be 100
    }

    It 'rejects an existing module that is not under lib/' {
        $null=New-QuietTestFile ([IO.Path]::Combine($scripts,'Root.psm1')) 'function Get-A { 1 }'
        {& $readTargets "@{Targets=@(@{Name='A';Module='Root.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}"}|Should -Throw -ExpectedMessage 'ScriptMutationTargetsInvalid: module'
    }

    It 'returns the declared repository inputs' {
        $targets=@(& $readTargets "@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80;Inputs=@('build/companions.yml','.github/containers/**','src/*/ci/*.ps1')})}")
        $targets[0].Inputs|Should -Be @('build/companions.yml','.github/containers/**','src/*/ci/*.ps1')
        $targets[0].Inputs.GetType()|Should -Be ([string[]])
    }

    It 'returns the declared equivalents with trimmed reasons and an empty platform by default' {
        $targets=@(& $readTargets "@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80;Equivalent=@(@{Function='Get-A';Mutator='StringLiteral';Original=`"'small'`";Replacement=`"''`";Reason='  the caller ignores the text  '};@{Function='Get-A';Mutator='StringLiteral';Original=`"'small'`";Replacement=`"''`";Reason='12345678901234567890';Platform='Linux'})})}")
        @($targets[0].Equivalent|ForEach-Object {'{0}|{1}|{2}|{3}|{4}|{5}' -f $_.Function,$_.Mutator,$_.Original,$_.Replacement,$_.Reason,$_.Platform}) -join "`n"|Should -BeExactly ("Get-A|StringLiteral|'small'|''|the caller ignores the text|`nGet-A|StringLiteral|'small'|''|12345678901234567890|Linux")
        (& $readTargets "@{Targets=@($validTarget)}").Equivalent.Count|Should -Be 0 -Because 'Equivalent is optional'
        @($targets[0].Equivalent|ForEach-Object {$_.Platform.GetType().Name}) -join ','|Should -BeExactly 'String,String' -Because 'an entry without a platform applies on every platform'
    }

    It 'rejects the equivalent <Value>' -ForEach @(
        @{Value='@()'};@{Value="@('x')"};@{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text';Line=1})"}
        @{Value="@(@{Function='Get-B';Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text'})"}
        @{Value="@(@{Function=@('Get-A');Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text'})"}
        @{Value="@(@{Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text'})"}
        @{Value="@(@{Function='Get-A';Mutator='Nope';Original='a';Replacement='';Reason='the caller ignores the text'})"}
        @{Value="@(@{Function='Get-A';Mutator=@('Regex');Original='a';Replacement='';Reason='the caller ignores the text'})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='';Replacement='';Reason='the caller ignores the text'})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original=1;Replacement='';Reason='the caller ignores the text'})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Reason='the caller ignores the text'})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement=1;Reason='the caller ignores the text'})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement=''})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='1234567890123456789'})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='     short reason      '})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text';Platform='Win'})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text';Platform=`$null})"}
        @{Value="@(@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text'};@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='another long enough reason'})"}
    ) {
        {& $readTargets "@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80;Equivalent=$Value})}"}|Should -Throw -ExpectedMessage 'ScriptMutationTargetsInvalid: equivalent'
    }

    It 'accepts the same equivalent on another platform and every mutator of the catalog' {
        $entries=@(foreach($mutator in Get-QuietScriptMutatorCatalog){"@{Function='Get-A';Mutator='$mutator';Original='a';Replacement='';Reason='the caller ignores the text'}"})+@(foreach($platform in 'Windows','Linux','MacOS'){"@{Function='Get-A';Mutator='Regex';Original='a';Replacement='';Reason='the caller ignores the text';Platform='$platform'}"})
        $target=& $readTargets "@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80;Equivalent=@($($entries -join ';'))})}"
        @($target.Equivalent|ForEach-Object {$_.Mutator+'/'+$_.Platform}) -join ','|Should -BeExactly ((@(Get-QuietScriptMutatorCatalog|ForEach-Object {"$_/"})+'Regex/Windows'+'Regex/Linux'+'Regex/MacOS') -join ',')
    }

    It 'rejects the inputs <Value>' -ForEach @(
        @{Value='@()'};@{Value='$null'};@{Value="@('')"};@{Value="@('a','a')"};@{Value="@('../x')"};@{Value="@('a/../b')"};@{Value="@('./a')"};@{Value="@('a/.')"}
        @{Value="@('/abs')"};@{Value="@('C:/abs')"};@{Value="@('a\b')"};@{Value="@('a//b')"};@{Value="@('a/')"};@{Value="@('a b')"};@{Value="@('a?')"};@{Value='@(1)'};@{Value='@(@{})'}
    ) {
        {& $readTargets "@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80;Inputs=$Value})}"}|Should -Throw -ExpectedMessage 'ScriptMutationTargetsInvalid: inputs'
    }

    It 'rejects <Case> with <Expected>' -ForEach @(
        @{Case='invalid syntax';Text='@{Targets=';Expected='ScriptMutationTargetsInvalid: syntax'}
        @{Case='no target';Text='@{Targets=@()}';Expected='ScriptMutationTargetsInvalid: shape'}
        @{Case='an extra top-level key';Text='@{Targets=@(@{});Other=1}';Expected='ScriptMutationTargetsInvalid: shape'}
        @{Case='a non-hashtable target';Text="@{Targets=@('A')}";Expected='ScriptMutationTargetsInvalid: shape'}
        @{Case='an unknown target key';Text="@{Targets=@(@{Name='A';Extra=1})}";Expected='ScriptMutationTargetsInvalid: shape'}
        @{Case='an invalid name';Text="@{Targets=@(@{Name='a b';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: name'}
        @{Case='a duplicate name';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80};@{Name='a';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: duplicate'}
        @{Case='a module outside lib';Text="@{Targets=@(@{Name='A';Module='../A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: module'}
        @{Case='a missing module';Text="@{Targets=@(@{Name='A';Module='lib/Z.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: module'}
        @{Case='no function';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@();UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: functions'}
        @{Case='a duplicate function';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A','Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: functions'}
        @{Case='an invalid function name';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: functions'}
        @{Case='no test file';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@();Break=80})}";Expected='ScriptMutationTargetsInvalid: tests'}
        @{Case='an integration test file';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('integration/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: tests'}
        @{Case='a missing test file';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/Z.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: tests'}
        @{Case='a traversing test file';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/../integration/A.Tests.ps1');Break=80})}";Expected='ScriptMutationTargetsInvalid: tests'}
        @{Case='a break above 100';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=101})}";Expected='ScriptMutationTargetsInvalid: break'}
        @{Case='a negative break';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=-1})}";Expected='ScriptMutationTargetsInvalid: break'}
        @{Case='a fractional break';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1');Break=80.5})}";Expected='ScriptMutationTargetsInvalid: break'}
        @{Case='a missing break';Text="@{Targets=@(@{Name='A';Module='lib/A.psm1';Functions=@('Get-A');UnitTestFiles=@('unit/lib/A.Tests.ps1')})}";Expected='ScriptMutationTargetsInvalid: break'}
    ) {
        {& $readTargets $Text}|Should -Throw -ExpectedMessage $Expected
    }

    It 'rejects a missing file' {
        {Read-QuietScriptMutationTargets -Path ([IO.Path]::Combine($TestDrive,'none.psd1')) -ScriptsRoot $scripts -TestsRoot $tests}|Should -Throw -ExpectedMessage 'ScriptMutationTargetsMissing'
    }

    It 'raises only typed errors on fuzzed documents' {
        $null=Invoke-QuietProperty -Name 'fuzzed targets' -Seed $seed -Count 150 -Generator {param($random)
            $values=@("'A'","'lib/A.psm1'","'../x'","@('Get-A')","@()",'80','101','-3','$null',"@('unit/lib/A.Tests.ps1')","@{}",'1.5',"'x y'","@('build/*.yml')","@('../x')","@('a','a')")
            $keys=@('Name','Module','Functions','UnitTestFiles','Break','Inputs','Other')
            $targets=foreach($index in 1..$random.Next(1,3)){
                $pairs=foreach($key in Get-QuietRandomSubset $random $keys 0.8){"$key=$(Get-QuietRandomItem $random $values)"}
                '@{'+(@($pairs) -join ';')+'}'
            }
            $text="@{Targets=@($(@($targets) -join ';'))}"
            if($random.Next(5) -eq 0){$text=$text.Substring(0,$random.Next(0,$text.Length))}
            $text
        } -Property {param($text)
            try{$null=& $readTargets $text;$true}catch{$_.Exception.Message -match $typedTargetsError}
        }
    }
}

Describe 'Select-QuietScriptMutationEquivalents' {
    BeforeAll {
        $mutant={param([string]$Id,[string]$Function='F',[string]$Mutator='M',[string]$Original='a',[string]$Replacement='b')[pscustomobject][ordered]@{Id=$Id;Function=$Function;Mutator=$Mutator;Line=[int]$Id;Original=$Original;Replacement=$Replacement}}
        $entry={param([string]$Platform='',[string]$Original='a',[string]$Replacement='b',[string]$Reason='same')[pscustomobject]@{Function='F';Mutator='M';Original=$Original;Replacement=$Replacement;Reason=$Reason;Platform=$Platform}}
    }

    It 'covers only the mutants identical in function, mutator, original and replacement, keeping every field and the reason' {
        $mutants=@((& $mutant '0'),(& $mutant '1' -Function 'f'),(& $mutant '2' -Mutator 'm'),(& $mutant '3' -Original 'A'),(& $mutant '4' -Replacement 'B'),$null,(& $mutant '5'))
        $split=Select-QuietScriptMutationEquivalents -Mutants $mutants -Equivalent @($null,(& $entry)) -Platform Windows -Target T
        @($split.Run.Id) -join ','|Should -BeExactly '1,2,3,4'
        @($split.Equivalent|ForEach-Object {'{0}:{1}:{2}' -f $_.Id,$_.Line,$_.Reason}) -join ','|Should -BeExactly '0:0:same,5:5:same'
        $split.Equivalent[0].Replacement|Should -BeExactly 'b'
    }

    It 'compares the texts with normalized line endings' {
        $split=Select-QuietScriptMutationEquivalents -Mutants @((& $mutant '0' -Original "a`nb" -Replacement "c`r`nd")) -Equivalent @((& $entry -Original "a`r`nb" -Replacement "c`nd")) -Platform Linux -Target T
        @($split.Equivalent.Id)|Should -Be @('0')
        $split.Run.Count|Should -Be 0
    }

    It 'applies a platform entry only on its platform' {
        $windows=Select-QuietScriptMutationEquivalents -Mutants @((& $mutant '0')) -Equivalent @((& $entry 'Linux')) -Platform Windows -Target T
        @($windows.Run.Id)|Should -Be @('0')
        $linux=Select-QuietScriptMutationEquivalents -Mutants @((& $mutant '0')) -Equivalent @((& $entry 'Linux')) -Platform Linux -Target T
        @($linux.Equivalent.Id)|Should -Be @('0')
    }

    It 'rejects every applicable entry that covers no mutant, the first matching entry taking the mutant' {
        {Select-QuietScriptMutationEquivalents -Mutants @((& $mutant '0')) -Equivalent @((& $entry),(& $entry 'MacOS'),(& $entry -Original 'z'),(& $entry -Replacement 'y')) -Platform MacOS -Target T}|
            Should -Throw -ExpectedMessage 'ScriptMutationEquivalentStale: T: F M a -> b on MacOS; F M z -> b; F M a -> y'
        {Select-QuietScriptMutationEquivalents -Mutants @() -Equivalent @((& $entry 'Windows')) -Platform Linux -Target T}|Should -Not -Throw
    }

    It 'runs a mutant lacking identity fields, which no declaration can cover' {
        @((Select-QuietScriptMutationEquivalents -Mutants @([pscustomobject]@{Id='x'},(& $mutant '0')) -Equivalent @((& $entry)) -Platform Windows -Target T).Run.Id)|Should -Be @('x')
    }

    It 'runs every mutant without declarations' {
        $split=Select-QuietScriptMutationEquivalents -Mutants @((& $mutant '0'),(& $mutant '1')) -Platform Windows -Target T
        @($split.Run.Id) -join ','|Should -BeExactly '0,1'
        $split.Equivalent.Count|Should -Be 0
    }
}

Describe 'New-QuietScriptMutationReport' {
    It 'scores each target from its own results and lists its survivors' {
        $targets=@([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=50},[pscustomobject]@{Name='B';Module='lib/B.psm1';Functions=@('F','G');Break=100})
        $results=@((& $newResult 'A' 'Killed' 1),(& $newResult 'A' 'Survived' 2),(& $newResult 'A' 'CompileError' 3),(& $newResult 'B' 'Timeout' 4),(& $newResult 'B' 'Survived' 5),$null)
        $report=New-QuietScriptMutationReport -Targets $targets -Results $results -Seed 42
        $report.SchemaVersion|Should -Be 1
        $report.Seed|Should -Be 42
        $report.Passed|Should -BeFalse
        $report.Targets[0].Score|Should -Be 50
        $report.Targets[0].Passed|Should -BeTrue
        $report.Targets[0].Mutants|Should -Be 3
        $report.Targets[0].Functions|Should -Be 1
        @($report.Targets[0].Survivors.Line)|Should -Be @(2)
        $report.Targets[1].Passed|Should -BeFalse
        @($report.Targets[1].Survivors.Id)|Should -Be @('id5')
        $report.Targets[0].Cached|Should -Be 0
        $report.Targets[1].Cached|Should -Be 0
        $report.Incomplete|Should -BeFalse
        $report.Crash|Should -BeNullOrEmpty
    }

    It 'marks a stopped campaign Incomplete and never Passed, with only its finished targets and the normalized crash' {
        $targets=@([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=50})
        $report=New-QuietScriptMutationReport -Targets $targets -Results @((& $newResult 'A' 'Killed' 1),(& $newResult 'B' 'Survived' 2)) -Seed 7 -Crash @{Target='B';Error='ScriptMutationBaselineFailed: B';NotRun=@('C','',$null,'D')}
        $report.Incomplete|Should -BeTrue
        $report.Passed|Should -BeFalse -Because 'the finished target passes, but the campaign stopped'
        @($report.Targets.Name)|Should -Be @('A')
        $report.Targets[0].Passed|Should -BeTrue
        $report.Targets[0].Mutants|Should -Be 1
        '{0}|{1}|{2}' -f $report.Crash.Target,$report.Crash.Error,($report.Crash.NotRun -join ',')|Should -BeExactly 'B|ScriptMutationBaselineFailed: B|C,D'
        ,$report.Crash.NotRun|Should -BeOfType ([string[]])
    }

    It 'reports a campaign stopped outside any target without a target entry' {
        $report=New-QuietScriptMutationReport -Targets @() -Seed 7 -Crash ([pscustomobject]@{Target=$null;Error='boom';NotRun=@('A')})
        $report.Incomplete|Should -BeTrue
        $report.Passed|Should -BeFalse
        @($report.Targets).Count|Should -Be 0
        $report.Crash.Target|Should -BeExactly ''
        @($report.Crash.NotRun)|Should -Be @('A')
    }

    It 'counts declared equivalents apart from the score and lists them with their reason' {
        $targets=@([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=50})
        $equivalent=(& $newResult 'A' 'Equivalent' 3)|Add-Member -NotePropertyName Reason -NotePropertyValue 'same output' -PassThru
        $report=New-QuietScriptMutationReport -Targets $targets -Results @((& $newResult 'A' 'Killed' 1),(& $newResult 'A' 'Survived' 2),$equivalent,(& $newResult 'A' 'Equivalent' 4)) -Seed 1
        $entry=$report.Targets[0]
        '{0}|{1}|{2}|{3}|{4}' -f $entry.Mutants,$entry.Equivalent,$entry.Score,@($entry.Survivors.Id).Count,(@($entry.Equivalents|ForEach-Object {$_.Id+'='+$_.Reason+'@'+$_.Line+':'+$_.Column+':'+$_.Function+':'+$_.Mutator+':'+$_.Original+':'+$_.Replacement}) -join ',')|Should -BeExactly '4|2|50|1|id3=same output@3:2:F:M:a|b:`x`,id4=@4:2:F:M:a|b:`x`'
        (Measure-QuietScriptMutationScore -Results @([pscustomobject]@{Status='Equivalent'})).Valid|Should -Be 0
    }

    It 'counts reused outcomes as Cached without changing the score' {
        $targets=@([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=50})
        $reused=(& $newResult 'A' 'Killed' 1)|Add-Member -NotePropertyName Cached -NotePropertyValue $true -PassThru
        $fresh=(& $newResult 'A' 'Survived' 2)|Add-Member -NotePropertyName Cached -NotePropertyValue $false -PassThru
        $text=(& $newResult 'A' 'Killed' 3)|Add-Member -NotePropertyName Cached -NotePropertyValue 'true' -PassThru
        $report=New-QuietScriptMutationReport -Targets $targets -Results @($reused,$fresh,$text,(& $newResult 'A' 'Killed' 4)) -Seed 1
        $report.Targets[0].Cached|Should -Be 1 -Because 'only a boolean true marks a reused outcome'
        $report.Targets[0].Score|Should -Be 75
        $report.Targets[0].Mutants|Should -Be 4
    }

    It 'passes when every target reaches its break, including a target without results' {
        $targets=@([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=80},[pscustomobject]@{Name='C';Module='lib/C.psm1';Functions=@('F');Break=80})
        $report=New-QuietScriptMutationReport -Targets $targets -Results @((& $newResult 'A' 'Killed'),(& $newResult 'a' 'Survived')) -Seed 1
        $report.Passed|Should -BeTrue
        $report.Incomplete|Should -BeFalse
        $report.Targets[1].Mutants|Should -Be 0
        $report.Targets[0].Mutants|Should -Be 1
    }
}

Describe 'ConvertTo-QuietScriptMutationMarkdown' {
    It 'renders the verdict, the score table, escaped survivors and declared equivalents exactly' {
        $targets=@([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=80},[pscustomobject]@{Name='B';Module='lib/B.psm1';Functions=@('F');Break=0})
        $survivor=& $newResult 'A' 'Survived' 7;$survivor.Original="a|b`r`nc"
        $equivalent=(& $newResult 'A' 'Equivalent' 9)|Add-Member -NotePropertyName Reason -NotePropertyValue 'same | result' -PassThru
        $cached=(& $newResult 'B' 'Killed' 1)|Add-Member -NotePropertyName Cached -NotePropertyValue $true -PassThru
        $report=New-QuietScriptMutationReport -Targets $targets -Results @((& $newResult 'A' 'Killed' 1),$survivor,$equivalent,$cached) -Seed 9
        $expected=@(
            '# Script mutation report',''
            'Verdict: **failed**. Seed: 9.',''
            '| Target | Module | Mutants | Killed | Timeout | Survived | Compile errors | Equivalent | Cached | Score | Break | Verdict |'
            '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
            '| A | `lib/A.psm1` | 3 | 1 | 0 | 1 | 0 | 1 | 0 | 50 % | 80 % | failed |'
            '| B | `lib/B.psm1` | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 100 % | 0 % | passed |'
            '','## Survivors: A',''
            '| Location | Function | Mutator | Before | After |'
            '| --- | --- | --- | --- | --- |'
            '| `lib/A.psm1:7:2` | F | M | `a\|b  c` | `''x''` |'
            '','## Equivalent mutants: A',''
            '| Location | Function | Mutator | Before | After | Reason |'
            '| --- | --- | --- | --- | --- | --- |'
            '| `lib/A.psm1:9:2` | F | M | `a\|b` | `''x''` | same \| result |'
        ) -join "`n"
        ConvertTo-QuietScriptMutationMarkdown -Report $report|Should -BeExactly ($expected+"`n")
    }

    It 'reports a passed verdict without a survivors or equivalents section, also for a report read back without them' {
        $report=New-QuietScriptMutationReport -Targets @([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=80}) -Results @((& $newResult 'A' 'Killed')) -Seed 3
        $markdown=ConvertTo-QuietScriptMutationMarkdown -Report $report
        $markdown|Should -Match 'Verdict: \*\*passed\*\*'
        $markdown|Should -Not -Match 'Survivors|Equivalent mutants'
        $report.Targets[0].PSObject.Properties.Remove('Equivalents')
        $report.PSObject.Properties.Remove('Incomplete')
        ConvertTo-QuietScriptMutationMarkdown -Report $report|Should -BeExactly $markdown
    }

    It 'names where an incomplete campaign stopped <Case>, with its escaped error and the targets never run' -ForEach @(
        @{Case='in a target';Crash=@{Target='B|1';Error='Baseline | `x`';NotRun=@('C|2','D')};Line='Stopped in target `B\|1` with `Baseline \| ''x''`. Not run: `C\|2`, `D`. Only the finished targets are scored below.'}
        @{Case='outside any target';Crash=@{Target='';Error='boom';NotRun=@()};Line='Stopped outside any target with `boom`. Not run: none. Only the finished targets are scored below.'}
    ) {
        $report=New-QuietScriptMutationReport -Targets @([pscustomobject]@{Name='A';Module='lib/A.psm1';Functions=@('F');Break=80}) -Results @((& $newResult 'A' 'Killed' 1)) -Seed 4 -Crash $Crash
        $expected=@(
            '# Script mutation report',''
            'Verdict: **incomplete**. Seed: 4.',''
            $Line,''
            '| Target | Module | Mutants | Killed | Timeout | Survived | Compile errors | Equivalent | Cached | Score | Break | Verdict |'
            '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'
            '| A | `lib/A.psm1` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 100 % | 80 % | passed |'
        ) -join "`n"
        ConvertTo-QuietScriptMutationMarkdown -Report ($report|ConvertTo-Json -Depth 6|ConvertFrom-Json)|Should -BeExactly ($expected+"`n") -Because 'the report is rendered as read back from report.json'
    }
}

Describe 'Assert-QuietScriptMutationShards' {
    BeforeAll {
        $shardTargets=@(foreach($name in 'A','B','C','D'){[pscustomobject]@{Name=$name;Module="lib/$name.psm1";Functions=[string[]]@('F','G');Break=80}})
        # A shard report exactly as the CI job downloads it: written by the engine, then read back from JSON.
        $shard={param([object[]]$Targets,[string]$Status='Killed')
            $results=@(foreach($target in $Targets){(& $newResult $target.Name $Status 1);(& $newResult $target.Name 'Killed' 2)})
            New-QuietScriptMutationReport -Targets $Targets -Results $results -Seed 5|ConvertTo-Json -Depth 6|ConvertFrom-Json
        }
        $issuesOf={param([object[]]$Reports)
            try{$null=Assert-QuietScriptMutationShards -Targets $shardTargets -Reports $Reports;@()}catch{[string[]]($_.Exception.Message -split '; ')}
        }
        $typedShardIssue='^ScriptMutationShard(ReportsMissing|ReportInvalid|(Incomplete|Unknown|Duplicate|Missing|Stale|BreakLowered|Failed): .*)$'
    }

    It 'accepts any partition of the targets into shards and returns one receipt row per target' {
        $null=Invoke-QuietProperty -Name 'shard partitions' -Seed $seed -Count 80 -Generator {param($random)
            $buckets=@{}
            foreach($target in [object[]](Get-QuietShuffle $random $shardTargets)){$index=$random.Next(0,4);if(!$buckets.ContainsKey($index)){$buckets[$index]=[Collections.Generic.List[object]]::new()};$buckets[$index].Add($target)}
            $groups=[Collections.Generic.List[object]]::new();foreach($key in @($buckets.Keys)){$groups.Add($buckets[$key].ToArray())}
            [pscustomobject]@{Groups=$groups.ToArray()}
        } -Property {param($partition)
            $receipt=Assert-QuietScriptMutationShards -Targets $shardTargets -Reports @(foreach($group in $partition.Groups){& $shard $group})
            $receipt.Passed -and (@($receipt.Targets.Name) -join ',') -ceq 'A,B,C,D' -and @($receipt.Targets|Where-Object {$_.Mutants -ne 2 -or $_.Break -ne 80 -or $_.Score -ne 100}).Count -eq 0
        }
    }

    It 'reports every missing, duplicated and unknown target together' {
        $extra=[pscustomobject]@{Name='Z';Module='lib/Z.psm1';Functions=[string[]]@('F','G');Break=80}
        $issues=& $issuesOf @((& $shard $shardTargets[0..1]),(& $shard @($shardTargets[1],$extra)))
        ($issues|Sort-Object -CaseSensitive) -join '|'|Should -BeExactly 'ScriptMutationShardDuplicate: B|ScriptMutationShardMissing: C|ScriptMutationShardMissing: D|ScriptMutationShardUnknown: Z'
    }

    It 'rejects a shard below its break, without mutants, with a lowered break or for a stale target' -ForEach @(
        @{Case='survivors';Edit={param($r)$r.Targets[0].Passed=$false;$r.Targets[0].Score=50};Issue='ScriptMutationShardFailed: A'}
        @{Case='score under break';Edit={param($r)$r.Targets[0].Score=79.5};Issue='ScriptMutationShardFailed: A'}
        @{Case='no mutants';Edit={param($r)$r.Targets[0].Mutants=0};Issue='ScriptMutationShardFailed: A'}
        @{Case='string verdict';Edit={param($r)$r.Targets[0].Passed='true'};Issue='ScriptMutationShardFailed: A'}
        @{Case='lowered break';Edit={param($r)$r.Targets[0].Break=79};Issue='ScriptMutationShardBreakLowered: A'}
        @{Case='missing break';Edit={param($r)$r.Targets[0].PSObject.Properties.Remove('Break')};Issue='ScriptMutationShardBreakLowered: A'}
        @{Case='other module';Edit={param($r)$r.Targets[0].Module='lib/Other.psm1'};Issue='ScriptMutationShardStale: A'}
        @{Case='fewer functions';Edit={param($r)$r.Targets[0].Functions=1};Issue='ScriptMutationShardStale: A'}
    ) {
        $report=& $shard $shardTargets
        & $Edit $report
        (& $issuesOf @($report)) -join '|'|Should -BeExactly $Issue -Because $Case
    }

    It 'accepts a shard whose outcomes came from the content-addressed cache, whatever its Cached count' -ForEach @(
        @{Case='every outcome reused';Edit={param($r)$r.Targets[0].Cached=$r.Targets[0].Mutants}}
        @{Case='no cached count';Edit={param($r)$r.Targets[0].PSObject.Properties.Remove('Cached')}}
    ) {
        $report=& $shard $shardTargets
        & $Edit $report
        (Assert-QuietScriptMutationShards -Targets $shardTargets -Reports @($report)).Passed|Should -BeTrue -Because $Case
    }

    It 'reports exactly <Issue> for <Case>' -ForEach @(
        @{Case='an other schema with valid targets';Edit={param($r)$r.SchemaVersion=2};Issue='ScriptMutationShardReportInvalid|ScriptMutationShardMissing: A|ScriptMutationShardMissing: B|ScriptMutationShardMissing: C|ScriptMutationShardMissing: D'}
        @{Case='a dictionary entry instead of a parsed object';Edit={param($r)$h=[ordered]@{};foreach($p in $r.Targets[0].PSObject.Properties){$h[$p.Name]=$p.Value};$r.Targets[0]=[hashtable]$h};Issue='ScriptMutationShardUnknown: |ScriptMutationShardMissing: A'}
        @{Case='a stale target with a lowered break';Edit={param($r)$r.Targets[0].Module='lib/Other.psm1';$r.Targets[0].Break=79};Issue='ScriptMutationShardStale: A'}
        @{Case='a lowered break with a failed verdict';Edit={param($r)$r.Targets[0].Break=79;$r.Targets[0].Passed=$false};Issue='ScriptMutationShardBreakLowered: A'}
        @{Case='a textual incomplete flag without a crash';Edit={param($r)$r.Incomplete='false'};Issue='ScriptMutationShardIncomplete: '}
    ) {
        $report=& $shard $shardTargets
        & $Edit $report
        (& $issuesOf @($report)) -join '|'|Should -BeExactly $Issue -Because $Case
    }

    It 'rejects a shard that stopped <Case> but still counts the targets it finished' -ForEach @(
        @{Case='in a target';Finished=@('A','B');Crash=@{Target='C';Error='boom';NotRun=@('D')};Issue='ScriptMutationShardIncomplete: C|ScriptMutationShardMissing: C|ScriptMutationShardMissing: D'}
        @{Case='outside any target';Finished=@();Crash=@{Target='';Error='boom';NotRun=@('A','B','C','D')};Issue='ScriptMutationShardIncomplete: |ScriptMutationShardMissing: A|ScriptMutationShardMissing: B|ScriptMutationShardMissing: C|ScriptMutationShardMissing: D'}
    ) {
        $finishedTargets=@($shardTargets|Where-Object {$_.Name -cin $Finished})
        $report=New-QuietScriptMutationReport -Targets $finishedTargets -Results @(foreach($entry in $finishedTargets){& $newResult $entry.Name 'Killed' 1}) -Seed 5 -Crash $Crash|ConvertTo-Json -Depth 6|ConvertFrom-Json
        (& $issuesOf @($report)) -join '|'|Should -BeExactly $Issue -Because $Case
    }

    It 'reports an unknown target once per occurrence, never as a duplicate' {
        $extra=[pscustomobject]@{Name='Z';Module='lib/Z.psm1';Functions=[string[]]@('F','G');Break=80}
        (& $issuesOf @((& $shard $shardTargets),(& $shard @($extra)),(& $shard @($extra)))) -join '|'|Should -BeExactly 'ScriptMutationShardUnknown: Z|ScriptMutationShardUnknown: Z'
    }

    It 'accepts a shard with a single mutant' {
        $report=& $shard $shardTargets
        $report.Targets[0].Mutants=1
        (Assert-QuietScriptMutationShards -Targets $shardTargets -Reports @($report)).Targets[0].Mutants|Should -Be 1
    }

    It 'accepts a score equal to its break' {
        $report=& $shard $shardTargets
        $report.Targets[0].Score=80
        (Assert-QuietScriptMutationShards -Targets $shardTargets -Reports @($report)).Targets[0].Score|Should -Be 80
    }

    It 'accepts a raised break that the score still reaches' {
        $report=& $shard $shardTargets
        $report.Targets[0].Break=100
        (Assert-QuietScriptMutationShards -Targets $shardTargets -Reports @($report)).Passed|Should -BeTrue
    }

    It 'rejects an empty download and malformed reports with typed issues only' -ForEach @(
        @{Case='no report';Reports=@();Issue='ScriptMutationShardReportsMissing'}
        @{Case='null report';Reports=@($null);Issue='ScriptMutationShardReportsMissing'}
        @{Case='other schema';Reports=@([pscustomobject]@{SchemaVersion=2;Targets=@([pscustomobject]@{Name='A'})});Issue='ScriptMutationShardReportInvalid'}
        @{Case='no targets';Reports=@([pscustomobject]@{SchemaVersion=1;Targets=@()});Issue='ScriptMutationShardReportInvalid'}
    ) {
        $issues=& $issuesOf $Reports
        $issues[0]|Should -BeExactly $Issue -Because $Case
    }

    It 'never fails with an untyped error on fuzzed shard reports' {
        $null=Invoke-QuietProperty -Name 'fuzzed shard reports' -Seed $seed -Count 150 -Generator {param($random)
            $values=@($null,'',0,1,-1,79.99,80,100,'80','x',$true,$false,@(),[pscustomobject]@{})
            $reports=@(for($index=0;$index -lt $random.Next(0,4);$index++){
                $picked=[object[]](Get-QuietRandomSubset $random $shardTargets 0.7);if(!$picked.Count){$picked=@($shardTargets[0])}
                $report=& $shard $picked
                foreach($entry in @($report.Targets)){
                    foreach($property in 'Name','Module','Functions','Mutants','Score','Break','Cached','Passed'){
                        if($random.Next(0,6) -eq 0){$entry.$property=Get-QuietRandomItem $random $values}
                    }
                }
                if($random.Next(0,8) -eq 0){$report.SchemaVersion=Get-QuietRandomItem $random $values}
                if($random.Next(0,8) -eq 0){$report.Incomplete=Get-QuietRandomItem $random $values}
                if($random.Next(0,8) -eq 0){$report.Crash=Get-QuietRandomItem $random $values}
                if($random.Next(0,10) -eq 0){$null}else{$report}
            })
            [pscustomobject]@{Reports=[object[]]$reports}
        } -Property {param($case)
            try{$null=Assert-QuietScriptMutationShards -Targets $shardTargets -Reports $case.Reports;$true}
            catch{@(($_.Exception.Message -split '; ')|Where-Object {$_ -cnotmatch $typedShardIssue}).Count -eq 0}
        }
    }
}
