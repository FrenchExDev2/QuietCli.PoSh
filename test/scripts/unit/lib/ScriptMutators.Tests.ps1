#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptMutators
    $seed=Get-QuietTestSeed
    $bodyOf={param([string]$Code)
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseInput("function T {`n$Code`n}",[ref]$tokens,[ref]$errors)
        if($errors.Count){throw "fixture does not parse: $Code"}
        $ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true).Body
    }
    $find={param([string]$Mutator,[string]$Code)@(& ('Find-QuietScriptMutant'+$Mutator) -Ast (& $bodyOf $Code))}
    $apply={param([string]$Code,$Mutant)
        $text="function T {`n$Code`n}"
        $text.Substring(0,$Mutant.StartOffset)+$Mutant.Replacement+$text.Substring($Mutant.EndOffset)
    }
}

Describe 'Get-QuietScriptMutatorCatalog' {
    It 'lists unique mutators, each implemented by an exported Find-QuietScriptMutant function' {
        $catalog=@(Get-QuietScriptMutatorCatalog)
        $catalog.Count|Should -Be 9
        @($catalog|Sort-Object -Unique).Count|Should -Be $catalog.Count
        foreach($name in $catalog){Get-Command ('Find-QuietScriptMutant'+$name) -ErrorAction Stop|Should -Not -BeNullOrEmpty}
    }

    It 'maps <Name> to <Function> and to nothing else' -ForEach @(
        @{Name='EqualityOperator';Function='Find-QuietScriptMutantEqualityOperator';Code='$a -eq 1'}
        @{Name='LogicalOperator';Function='Find-QuietScriptMutantLogicalOperator';Code='$a -and $b'}
        @{Name='Regex';Function='Find-QuietScriptMutantRegex';Code="`$a -match 'x'"}
        @{Name='BooleanLiteral';Function='Find-QuietScriptMutantBooleanLiteral';Code='$true'}
        @{Name='ConditionalExpression';Function='Find-QuietScriptMutantConditionalExpression';Code='if($a){1}'}
        @{Name='StringLiteral';Function='Find-QuietScriptMutantStringLiteral';Code="'x'"}
        @{Name='ArrayDeclaration';Function='Find-QuietScriptMutantArrayDeclaration';Code='@(1)'}
        @{Name='BlockStatement';Function='Find-QuietScriptMutantBlockStatement';Code='if($a){1}'}
        @{Name='MethodExpression';Function='Find-QuietScriptMutantMethodExpression';Code="`$a.StartsWith('x')"}
    ) {
        @(Get-QuietScriptMutatorCatalog)|Should -Contain $Name
        $mutants=@(& $Function -Ast (& $bodyOf $Code))
        $mutants.Count|Should -BeGreaterThan 0
        foreach($mutant in $mutants){$mutant.Mutator|Should -BeExactly $Name}
    }

    It 'exports exactly one finder per catalogued mutator' {
        $exported=@((Get-Module ScriptMutators).ExportedFunctions.Keys|Where-Object {$_ -like 'Find-QuietScriptMutant*'}|ForEach-Object {$_.Substring('Find-QuietScriptMutant'.Length)}|Sort-Object)
        $exported|Should -Be @(Get-QuietScriptMutatorCatalog|Sort-Object)
    }
}

Describe 'Mutator <Mutator>' -ForEach @(
    @{Mutator='EqualityOperator';Code='$a -eq 1';Expected=@('-ne')}
    @{Mutator='EqualityOperator';Code='$a -cne $b';Expected=@('-ceq')}
    @{Mutator='EqualityOperator';Code='$a -lt 1';Expected=@('-le','-ge')}
    @{Mutator='EqualityOperator';Code='$a -ile 1';Expected=@('-ilt','-igt')}
    @{Mutator='EqualityOperator';Code='$a -gt 1';Expected=@('-ge','-le')}
    @{Mutator='EqualityOperator';Code='$a -ge 1';Expected=@('-gt','-lt')}
    @{Mutator='EqualityOperator';Code='$a + 1';Expected=@()}
    @{Mutator='LogicalOperator';Code='$a -and $b';Expected=@('-or')}
    @{Mutator='LogicalOperator';Code='$a -or $b';Expected=@('-and')}
    @{Mutator='LogicalOperator';Code='$a -xor $b';Expected=@()}
    @{Mutator='Regex';Code='$a -match "x"';Expected=@('-notmatch')}
    @{Mutator='Regex';Code='$a -cnotmatch "x"';Expected=@('-cmatch')}
    @{Mutator='Regex';Code='$a -like "x"';Expected=@()}
    @{Mutator='BooleanLiteral';Code='$true';Expected=@('$false')}
    @{Mutator='BooleanLiteral';Code='$False';Expected=@('$true')}
    @{Mutator='BooleanLiteral';Code='!$a';Expected=@('($a)')}
    @{Mutator='BooleanLiteral';Code='-not $a';Expected=@('($a)')}
    @{Mutator='BooleanLiteral';Code='$null';Expected=@()}
    @{Mutator='ConditionalExpression';Code='if($a){1}';Expected=@('$true','$false')}
    @{Mutator='ConditionalExpression';Code='if($a){1}elseif($b){2}';Expected=@('$true','$false','$true','$false')}
    @{Mutator='ConditionalExpression';Code='$a ? 1 : 2';Expected=@('$true','$false')}
    @{Mutator='ConditionalExpression';Code='while($a){break}';Expected=@('$false')}
    @{Mutator='ConditionalExpression';Code='for($i=0;$i -lt 2;$i++){}';Expected=@('$false')}
    @{Mutator='ConditionalExpression';Code='do{$i++}until($i -gt 2)';Expected=@('$true')}
    @{Mutator='ConditionalExpression';Code='foreach($x in $a){}';Expected=@()}
    @{Mutator='StringLiteral';Code="'text'";Expected=@("''")}
    @{Mutator='StringLiteral';Code='"a$b"';Expected=@("''")}
    @{Mutator='StringLiteral';Code="''";Expected=@("'Stryker was here!'")}
    @{Mutator='StringLiteral';Code="@{'key'=1}";Expected=@()}
    @{Mutator='StringLiteral';Code='Write-Output bare';Expected=@()}
    @{Mutator='ArrayDeclaration';Code='@(1,2)';Expected=@('@()')}
    @{Mutator='ArrayDeclaration';Code='@()';Expected=@()}
    @{Mutator='BlockStatement';Code='if($a){1}';Expected=@('{}')}
    @{Mutator='BlockStatement';Code="throw 'x'";Expected=@('')}
    @{Mutator='BlockStatement';Code='foreach($x in $a){continue}';Expected=@('{}','')}
    @{Mutator='BlockStatement';Code='return 1';Expected=@('return')}
    @{Mutator='BlockStatement';Code='return';Expected=@()}
    @{Mutator='MethodExpression';Code="'a'.StartsWith('b')";Expected=@('EndsWith')}
    @{Mutator='MethodExpression';Code="'a'.ToLowerInvariant()";Expected=@('ToUpperInvariant')}
    @{Mutator='MethodExpression';Code='[Math]::Max(1,2)';Expected=@('Min')}
    @{Mutator='MethodExpression';Code='$list.Add(1)';Expected=@('')}
    @{Mutator='MethodExpression';Code='$null=$list.Add(1)';Expected=@()}
    @{Mutator='MethodExpression';Code="'a'.startswith('b')";Expected=@()}
) {
    It 'mutates <Code> into <Expected>' {
        $mutants=& $find $Mutator $Code
        @($mutants|ForEach-Object Replacement)|Should -Be $Expected
        foreach($mutant in $mutants){
            $mutant.Mutator|Should -BeExactly $Mutator
            $text="function T {`n$Code`n}"
            $text.Substring($mutant.StartOffset,$mutant.EndOffset-$mutant.StartOffset)|Should -BeExactly $mutant.Original
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseInput((& $apply $Code $mutant),[ref]$tokens,[ref]$errors)
            $errors.Count|Should -Be 0 -Because "$Mutator on $Code must still parse"
        }
    }
}

Describe 'Test-QuietScriptMutableNode' {
    It 'excludes attribute arguments, validation sets and type constraints from every mutator' {
        $code="param([ValidateSet('a','b')][ValidateRange(0,1)][Parameter(Mandatory=`$true)][string]`$Value)"
        foreach($mutator in Get-QuietScriptMutatorCatalog){@(& $find $mutator $code).Count|Should -Be 0 -Because $mutator}
    }

    It 'keeps parameter default values mutable' {
        @((& $find 'StringLiteral' "param([string]`$Value='x')")|ForEach-Object Replacement)|Should -Be @("''")
    }
}

Describe 'New-QuietScriptMutant' {
    It 'records the extent position and text' {
        $body=& $bodyOf "`$a -eq 1"
        $node=$body.Find({param($n)$n -is [Management.Automation.Language.BinaryExpressionAst]},$true)
        $mutant=New-QuietScriptMutant 'M' $node.ErrorPosition '-ne'
        $mutant.Original|Should -BeExactly '-eq'
        $mutant.Line|Should -Be 2
        $mutant.Column|Should -Be 4
        $mutant.EndOffset-$mutant.StartOffset|Should -Be 3
    }
}

Describe 'Mutator properties' {
    It 'every mutant of a generated program reports its original text and still parses' {
        $null=Invoke-QuietProperty -Name 'mutants are exact and parse' -Seed $seed -Count 60 -Generator {param($random)
            $atoms=@('$a','$b','1','$true','$false',"'s'",'""','@(1)','$x.Count')
            $operators=@('-eq','-ne','-lt','-le','-gt','-ge','-and','-or','-match','-notmatch','-ceq','-inotmatch')
            $expression={param($depth)
                if($depth -le 0 -or $random.Next(3) -eq 0){return (Get-QuietRandomItem $random $atoms)}
                switch($random.Next(4)){
                    0{'('+(& $expression ($depth-1))+' '+(Get-QuietRandomItem $random $operators)+' '+(& $expression ($depth-1))+')'}
                    1{'!('+(& $expression ($depth-1))+')'}
                    2{'(-not '+(& $expression ($depth-1))+')'}
                    default{'@('+(& $expression ($depth-1))+')'}
                }
            }
            $statements=foreach($index in 1..$random.Next(1,5)){
                switch($random.Next(6)){
                    0{'if('+(& $expression 2)+'){ return '+(& $expression 1)+' }else{ throw ''x'' }'}
                    1{'foreach($item in @(1,2)){ if('+(& $expression 1)+'){ continue } }'}
                    2{'$list.Add('+(& $expression 1)+')'}
                    3{'$r=('+(& $expression 2)+') ? ''a'' : ''b'''}
                    4{'while('+(& $expression 1)+'){ break }'}
                    default{'$s=''abc''.StartsWith(''a'')'}
                }
            }
            ($statements -join "`n")
        } -Property {param($code)
            $text="function T {`n$code`n}"
            foreach($mutator in Get-QuietScriptMutatorCatalog){
                foreach($mutant in & $find $mutator $code){
                    if($text.Substring($mutant.StartOffset,$mutant.EndOffset-$mutant.StartOffset) -cne $mutant.Original){return $false}
                    $tokens=$null;$errors=$null
                    $null=[Management.Automation.Language.Parser]::ParseInput((& $apply $code $mutant),[ref]$tokens,[ref]$errors)
                    if($errors.Count){throw "$mutator produced unparsable code from [$($mutant.Original)] to [$($mutant.Replacement)]"}
                }
            }
            $true
        }
    }
}
