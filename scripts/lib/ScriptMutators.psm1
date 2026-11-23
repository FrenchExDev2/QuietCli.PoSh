#Objective: Stryker-style PowerShell AST mutators; one function per mutator, listed by Get-QuietScriptMutatorCatalog.
#requires -Version 7.6

function Get-QuietScriptMutatorCatalog {
    <#
    .SYNOPSIS
    Returns the mutator names in application order; mutator <Name> is implemented by Find-QuietScriptMutant<Name>.
    .DESCRIPTION
    Adding a mutator means adding one Find-QuietScriptMutant<Name> function and its name here; the engine does not change.
    #>
    @('EqualityOperator','LogicalOperator','Regex','BooleanLiteral','ConditionalExpression','StringLiteral','ArrayDeclaration','BlockStatement','MethodExpression')
}

function Test-QuietScriptMutableNode {
    <#
    .SYNOPSIS
    Returns false for nodes inside attributes (parameter validation and CmdletBinding), which are not behavior under test.
    .PARAMETER Node
    Candidate node.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Node)
    for($current=$Node.Parent;$null -ne $current;$current=$current.Parent){
        if($current -is [Management.Automation.Language.AttributeBaseAst]){return $false}
    }
    $true
}

function New-QuietScriptMutant {
    <#
    .SYNOPSIS
    Builds one mutation candidate: replace [StartOffset, EndOffset) of the file text with Replacement.
    .PARAMETER Mutator
    Mutator name.
    .PARAMETER Extent
    Replaced extent.
    .PARAMETER Replacement
    Replacement text.
    #>
    param([Parameter(Mandatory)][string]$Mutator,[Parameter(Mandatory)][Management.Automation.Language.IScriptExtent]$Extent,[Parameter(Mandatory)][AllowEmptyString()][string]$Replacement)
    [pscustomobject][ordered]@{Mutator=$Mutator;StartOffset=$Extent.StartOffset;EndOffset=$Extent.EndOffset;Line=$Extent.StartLineNumber;Column=$Extent.StartColumnNumber;Original=$Extent.Text;Replacement=$Replacement}
}

function Find-QuietScriptMutantEqualityOperator {
    <#
    .SYNOPSIS
    EqualityOperator: -eq/-ne swap; -lt/-le/-gt/-ge become their boundary and negated forms, keeping the c/i prefix.
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    $map=@{eq=@('ne');ne=@('eq');lt=@('le','ge');le=@('lt','gt');gt=@('ge','le');ge=@('gt','lt')}
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.BinaryExpressionAst]},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        $text=$node.ErrorPosition.Text
        $match=[regex]::Match($text,'^-(?<prefix>[ci]?)(?<op>eq|ne|lt|le|gt|ge)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if(!$match.Success){continue}
        foreach($target in $map[$match.Groups['op'].Value.ToLowerInvariant()]){New-QuietScriptMutant 'EqualityOperator' $node.ErrorPosition ('-'+$match.Groups['prefix'].Value+$target)}
    }
}

function Find-QuietScriptMutantLogicalOperator {
    <#
    .SYNOPSIS
    LogicalOperator: -and becomes -or and -or becomes -and.
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.BinaryExpressionAst] -and $n.Operator -in @([Management.Automation.Language.TokenKind]::And,[Management.Automation.Language.TokenKind]::Or)},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'LogicalOperator' $node.ErrorPosition $(if($node.Operator -eq [Management.Automation.Language.TokenKind]::And){'-or'}else{'-and'})
    }
}

function Find-QuietScriptMutantRegex {
    <#
    .SYNOPSIS
    Regex: -match becomes -notmatch and back, keeping the c/i prefix.
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.BinaryExpressionAst]},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        $match=[regex]::Match($node.ErrorPosition.Text,'^-(?<prefix>[ci]?)(?<not>not)?match$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if(!$match.Success){continue}
        New-QuietScriptMutant 'Regex' $node.ErrorPosition ('-'+$match.Groups['prefix'].Value+$(if($match.Groups['not'].Success){'match'}else{'notmatch'}))
    }
}

function Find-QuietScriptMutantBooleanLiteral {
    <#
    .SYNOPSIS
    BooleanLiteral: $true and $false swap; a ! or -not negation is removed.
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -in @('true','false')},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'BooleanLiteral' $node.Extent $(if($node.VariablePath.UserPath -ieq 'true'){'$false'}else{'$true'})
    }
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.UnaryExpressionAst] -and $n.TokenKind -in @([Management.Automation.Language.TokenKind]::Exclaim,[Management.Automation.Language.TokenKind]::Not)},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'BooleanLiteral' $node.Extent ('('+$node.Child.Extent.Text+')')
    }
}

function Find-QuietScriptMutantConditionalExpression {
    <#
    .SYNOPSIS
    ConditionalExpression: if/elseif and ternary conditions become $true and $false; loop conditions stop the loop ($true for do-until, $false otherwise).
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst]},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        foreach($clause in $node.Clauses){
            New-QuietScriptMutant 'ConditionalExpression' $clause.Item1.Extent '$true'
            New-QuietScriptMutant 'ConditionalExpression' $clause.Item1.Extent '$false'
        }
    }
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.TernaryExpressionAst]},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'ConditionalExpression' $node.Condition.Extent '$true'
        New-QuietScriptMutant 'ConditionalExpression' $node.Condition.Extent '$false'
    }
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.LoopStatementAst] -and $n -isnot [Management.Automation.Language.ForEachStatementAst] -and $null -ne $n.Condition},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'ConditionalExpression' $node.Condition.Extent $(if($node -is [Management.Automation.Language.DoUntilStatementAst]){'$true'}else{'$false'})
    }
}

function Find-QuietScriptMutantStringLiteral {
    <#
    .SYNOPSIS
    StringLiteral: a quoted non-empty string becomes '' and an empty one a marker; bare words and hashtable keys are kept.
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    foreach($node in $Ast.FindAll({param($n)
        ($n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -ne [Management.Automation.Language.StringConstantType]::BareWord) -or
        $n -is [Management.Automation.Language.ExpandableStringExpressionAst]
    },$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        if($node.Parent -is [Management.Automation.Language.HashtableAst] -and @($node.Parent.KeyValuePairs|Where-Object {[object]::ReferenceEquals($_.Item1,$node)}).Count){continue}
        if($node.Parent -is [Management.Automation.Language.ExpandableStringExpressionAst]){continue}
        New-QuietScriptMutant 'StringLiteral' $node.Extent $(if([string]::IsNullOrEmpty($node.Value)){"'Stryker was here!'"}else{"''"})
    }
}

function Find-QuietScriptMutantArrayDeclaration {
    <#
    .SYNOPSIS
    ArrayDeclaration: a non-empty @(...) becomes @().
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.ArrayExpressionAst] -and $n.SubExpression.Statements.Count -gt 0},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'ArrayDeclaration' $node.Extent '@()'
    }
}

function Find-QuietScriptMutantBlockStatement {
    <#
    .SYNOPSIS
    BlockStatement: a non-empty statement block becomes {}; throw, continue and break are removed; return loses its value.
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.StatementBlockAst] -and $n.Statements.Count -gt 0},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'BlockStatement' $node.Extent '{}'
    }
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.ThrowStatementAst] -or $n -is [Management.Automation.Language.ContinueStatementAst] -or $n -is [Management.Automation.Language.BreakStatementAst]},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'BlockStatement' $node.Extent ''
    }
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.ReturnStatementAst] -and $null -ne $n.Pipeline},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        New-QuietScriptMutant 'BlockStatement' $node.Extent 'return'
    }
}

function Find-QuietScriptMutantMethodExpression {
    <#
    .SYNOPSIS
    MethodExpression: StartsWith/EndsWith, ToUpper/ToLower and Min/Max swap; a standalone .Add(...) statement is removed.
    .PARAMETER Ast
    Function or script AST to inspect.
    #>
    param([Parameter(Mandatory)][Management.Automation.Language.Ast]$Ast)
    $swap=@{StartsWith='EndsWith';EndsWith='StartsWith';ToUpperInvariant='ToLowerInvariant';ToLowerInvariant='ToUpperInvariant';ToUpper='ToLower';ToLower='ToUpper';Min='Max';Max='Min'}
    foreach($node in $Ast.FindAll({param($n)$n -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true)){
        if(!(Test-QuietScriptMutableNode $node)){continue}
        $member=$node.Member -as [Management.Automation.Language.StringConstantExpressionAst]
        $name=${member}?.Value
        $key=@($swap.Keys|Where-Object {$_ -ceq $name})
        if($key.Count){New-QuietScriptMutant 'MethodExpression' $node.Member.Extent $swap[$key[0]]}
        if($name -ceq 'Add' -and $node.Parent -is [Management.Automation.Language.CommandExpressionAst] -and $node.Parent.Parent -is [Management.Automation.Language.PipelineAst] -and
            $node.Parent.Parent.PipelineElements.Count -eq 1 -and
            ($node.Parent.Parent.Parent -is [Management.Automation.Language.StatementBlockAst] -or
             $node.Parent.Parent.Parent -is [Management.Automation.Language.NamedBlockAst])){
            New-QuietScriptMutant 'MethodExpression' $node.Parent.Parent.Extent ''
        }
    }
}

Export-ModuleMember -Function Get-QuietScriptMutatorCatalog,Test-QuietScriptMutableNode,New-QuietScriptMutant,Find-QuietScriptMutantEqualityOperator,Find-QuietScriptMutantLogicalOperator,Find-QuietScriptMutantRegex,Find-QuietScriptMutantBooleanLiteral,Find-QuietScriptMutantConditionalExpression,Find-QuietScriptMutantStringLiteral,Find-QuietScriptMutantArrayDeclaration,Find-QuietScriptMutantBlockStatement,Find-QuietScriptMutantMethodExpression
