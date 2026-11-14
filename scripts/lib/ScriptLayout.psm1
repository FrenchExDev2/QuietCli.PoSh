#requires -Version 7.6
function Test-QuietScriptLayout {
    <#
    .SYNOPSIS
    Enforces RAC-PS-004 using inert PowerShell syntax trees, independently of legacy preview waivers.
    .PARAMETER WorkspaceRoot
    Root containing the scripts directory. No script or module under inspection is executed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $scripts=[IO.Path]::GetFullPath([IO.Path]::Combine($WorkspaceRoot,'scripts'))
    if(!(Test-Path -LiteralPath $scripts -PathType Container)){throw 'ScriptLayoutDirectoryMissing'}
    $violations=[Collections.Generic.List[string]]::new()
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push($scripts)
    $checked=0
    while($pending.Count){
        foreach($file in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            $relative=[IO.Path]::GetRelativePath($WorkspaceRoot,$file.FullName).Replace('\','/')
            if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){$violations.Add($relative+': links are not allowed');continue}
            if($file.PSIsContainer){$pending.Push($file.FullName);continue}
            if($file.Extension -notin @('.ps1','.psm1')){continue}
            $checked++
            $tokens=$null;$errors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
            if($errors.Count){$violations.Add($relative+': invalid PowerShell syntax');continue}
            if($file.Extension -eq '.ps1'){
                $name=[regex]::Match($file.BaseName,'\A([A-Z][a-z]+)-([A-Z][A-Za-z0-9]*)\z')
                if(!$name.Success){$violations.Add($relative+': expected Verb-Noun')}
                if(@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)).Count){$violations.Add($relative+': functions belong in scripts/lib/*.psm1')}
            }elseif(!$relative.StartsWith('scripts/lib/',[StringComparison]::Ordinal)){
                $violations.Add($relative+': modules belong in scripts/lib/')
            }
            foreach($command in $ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)){
                $name=$command.GetCommandName()
                if($name -and ($name -split '\\')[-1] -ieq 'Join-Path'){$violations.Add($relative+': use System.IO.Path instead of Join-Path')}
                if($command.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Dot -and $command.Extent.Text -match '\.psm1'){$violations.Add($relative+': import libraries with Import-Module')}
                if($name -and ($name -split '\\')[-1] -ieq 'Import-Module'){
                    $quietImport=@($command.CommandElements | Where-Object {$_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ieq 'DisableNameChecking' -and (!$_.Argument -or $_.Argument.Extent.Text -ieq '$true')})
                    if(!$quietImport.Count){$violations.Add($relative+': Import-Module requires -DisableNameChecking')}
                }
            }
        }
    }
    if($violations.Count){throw ('ScriptLayoutInvalid: '+($violations -join '; '))}
    [pscustomobject]@{Check='ScriptLayout';Files=$checked;State='Success'}
}
Export-ModuleMember -Function Test-QuietScriptLayout
