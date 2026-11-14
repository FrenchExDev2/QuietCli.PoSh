#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
function Test-QuietPowerShellSources {
    <#
    .SYNOPSIS
    Parses project and entry-point sources and requires readable function help without executing inspected code.
    .PARAMETER WorkspaceRoot
    Checkout or exported index snapshot containing inert project declarations and scripts.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $root=[IO.Path]::GetFullPath($WorkspaceRoot)
    $directories=@((Get-QuietWorkspaceProjects $root).Path)+@('scripts')
    $files=0;$functions=0
    foreach($directory in $directories){
        $pending=[Collections.Generic.Stack[string]]::new()
        $pending.Push([IO.Path]::Combine($root,$directory))
        while($pending.Count){
            foreach($file in Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop){
                # Preserve the owning Tooling case's generated/library exclusion boundary.
                if($file.PSIsContainer -and $file.Name -in @('bin','obj','lib','artifacts','.git','.cache','.dotnet')){continue}
                if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('PowerShellSourceLinkRejected: '+$file.FullName)}
                if($file.PSIsContainer){$pending.Push($file.FullName);continue}
                if($file.Extension -notin @('.ps1','.psm1')){continue}
                $files++
                $tokens=$null;$errors=$null
                $text=[IO.File]::ReadAllTextAsync($file.FullName,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
                $ast=[Management.Automation.Language.Parser]::ParseInput($text,$file.FullName,[ref]$tokens,[ref]$errors)
                if($errors.Count){throw ('PowerShell syntax: '+$file.Name+': '+$errors[0].Message)}
                foreach($function in $ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
                    $help=$function.GetHelpContent()
                    if(!$help -or [string]::IsNullOrWhiteSpace($help.Synopsis)){throw ('Unreadable function help: '+$file.Name+' / '+$function.Name)}
                    $functions++
                }
            }
        }
    }
    [pscustomobject]@{Check='PowerShellSources';Files=$files;Functions=$functions;State='Success'}
}
Export-ModuleMember -Function Test-QuietPowerShellSources
