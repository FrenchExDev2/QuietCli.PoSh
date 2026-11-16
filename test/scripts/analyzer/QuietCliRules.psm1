#Objective: Repository-specific PSScriptAnalyzer rules (RAC-PS-003, RAC-PS-004 and import flags).
#requires -Version 7.6

function Measure-QuietJoinPath {
    <#
    .SYNOPSIS
    RAC-PS-004: path composition uses [IO.Path]::Combine, never Join-Path.
    .PARAMETER ScriptBlockAst
    Script block supplied by PSScriptAnalyzer; only the file root is inspected.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)][Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)
    if($null -ne $ScriptBlockAst.Parent){return}
    foreach($command in $ScriptBlockAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ieq 'Join-Path'},$true)){
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{Message='Use [IO.Path]::Combine instead of Join-Path (RAC-PS-004).';Extent=$command.Extent;RuleName='QuietJoinPath';Severity='Warning'}
    }
}

function Measure-QuietEntryPointFunction {
    <#
    .SYNOPSIS
    RAC-PS-003: an entry point under scripts/ defines no function; helpers live in scripts/lib.
    .PARAMETER ScriptBlockAst
    Script block supplied by PSScriptAnalyzer; only the file root of scripts/*.ps1 is inspected.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)][Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)
    if($null -ne $ScriptBlockAst.Parent){return}
    $file=[string]$ScriptBlockAst.Extent.File
    if($file -notmatch '(?<![\\/]test)[\\/]scripts[\\/][^\\/]+\.ps1$'){return}
    foreach($function in $ScriptBlockAst.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{Message=('Entry points define no function; move '+$function.Name+' to scripts/lib (RAC-PS-003).');Extent=$function.Extent;RuleName='QuietEntryPointFunction';Severity='Warning'}
    }
}

function Measure-QuietImportErrorAction {
    <#
    .SYNOPSIS
    Every Import-Module states -ErrorAction Stop, so a missing module fails at once.
    .DESCRIPTION
    -DisableNameChecking is already enforced by the ScriptLayout check and is not repeated here.
    .PARAMETER ScriptBlockAst
    Script block supplied by PSScriptAnalyzer; only the file root is inspected.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param([Parameter(Mandatory)][Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst)
    if($null -ne $ScriptBlockAst.Parent){return}
    foreach($command in $ScriptBlockAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ieq 'Import-Module'},$true)){
        $elements=@($command.CommandElements)
        $stop=$false
        for($index=1;$index -lt $elements.Count;$index++){
            $element=$elements[$index]
            if($element -isnot [Management.Automation.Language.CommandParameterAst] -or $element.ParameterName -ine 'ErrorAction'){continue}
            $value=if($element.Argument){$element.Argument}elseif($index+1 -lt $elements.Count){$elements[$index+1]}else{$null}
            if($value -is [Management.Automation.Language.StringConstantExpressionAst] -and $value.Value -ieq 'Stop'){$stop=$true}
        }
        if(!$stop){
            [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{Message='Import-Module requires -ErrorAction Stop.';Extent=$command.Extent;RuleName='QuietImportErrorAction';Severity='Warning'}
        }
    }
}

Export-ModuleMember -Function Measure-QuietJoinPath,Measure-QuietEntryPointFunction,Measure-QuietImportErrorAction
