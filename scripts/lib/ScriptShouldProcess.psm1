#requires -Version 7.6
function Get-QuietScriptShouldProcess {
    <#
    .SYNOPSIS
    Classifies a PowerShell file without executing it; mutation previews require the standard API and a guard.
    .PARAMETER Path
    Script or module file to parse.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('ScriptSafetyParseFailed: '+$Path)}
    $statements=@(foreach($block in @($ast.BeginBlock,$ast.ProcessBlock,$ast.EndBlock)){if($block){$block.Statements}})
    if(!$ast.ParamBlock -and @($statements|Where-Object {$_ -isnot [Management.Automation.Language.FunctionDefinitionAst]}).Count -eq 0){return 'Library'}
    # A script library may declare strict mode, exports and a sibling library import.
    # Arbitrary initializer code is executable and still requires its own effect boundary.
    if([IO.Path]::GetExtension($Path) -eq '.psm1' -and !$ast.ParamBlock){
        $declarative=$true
        foreach($statement in $statements){
            if($statement -is [Management.Automation.Language.FunctionDefinitionAst]){continue}
            if($statement -isnot [Management.Automation.Language.PipelineAst] -or $statement.PipelineElements.Count -ne 1){$declarative=$false;break}
            $command=$statement.PipelineElements[0]
            if($command -isnot [Management.Automation.Language.CommandAst]){$declarative=$false;break}
            $name=$command.GetCommandName()
            $nested=@($statement.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true))
            if($name -in @('Set-StrictMode','Export-ModuleMember') -and $nested.Count -eq 1){continue}
            if($name -eq 'Import-Module' -and $nested.Count -eq 1 -and $statement.Extent.Text -match '^Import-Module \(\[IO\.Path\]::Combine\(\$PSScriptRoot,''[A-Za-z0-9_.-]+\.psm1''\)\) -(?:DisableNameChecking -ErrorAction Stop|ErrorAction Stop -DisableNameChecking)$'){continue}
            $declarative=$false;break
        }
        if($declarative){return 'Library'}
    }
    $supported=$false
    if($ast.ParamBlock){foreach($attribute in $ast.ParamBlock.Attributes){
        if($attribute.TypeName.Name -ine 'CmdletBinding'){continue}
        foreach($argument in $attribute.NamedArguments){
            if($argument.ArgumentName -ieq 'SupportsShouldProcess' -and ($argument.ExpressionOmitted -or $argument.Argument.SafeGetValue() -eq $true)){$supported=$true}
        }
    }}
    $guard=$ast.FindAll({param($node)
        $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Member.Value -ieq 'ShouldProcess' -and
        $node.Expression -is [Management.Automation.Language.VariableExpressionAst] -and
        $node.Expression.VariablePath.UserPath -ieq 'PSCmdlet'
    },$false).Count -gt 0
    if($supported -and $guard){return 'ShouldProcess'}
    # A thin entry point forwards its standard parameters to one statically selected local command.
    if($supported -and $statements.Count -eq 2 -and [IO.Path]::GetExtension($Path) -eq '.ps1'){
        $imports=@($statements[0].FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Import-Module'},$false))
        $calls=@($statements[1].FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$false))
        if($imports.Count -eq 1 -and $calls.Count -eq 1 -and $imports[0].Extent.Text -match '^Import-Module \(\[IO\.Path\]::Combine\(\$PSScriptRoot,''lib/([A-Za-z0-9-]+\.psm1)''\)\) -DisableNameChecking -ErrorAction Stop$' -and $calls[0].Extent.Text -cmatch '^Invoke-QuietScript[A-Za-z]+ @PSBoundParameters$'){
            # Resolve only the literal local dependency, without importing the inspected code.
            $literal=[regex]::Match($imports[0].Extent.Text,"'lib/([A-Za-z0-9-]+\.psm1)'")
            $library=[IO.Path]::Combine([IO.Path]::GetDirectoryName($Path),'lib',$literal.Groups[1].Value)
            $libTokens=$null;$libErrors=$null
            $libAst=[Management.Automation.Language.Parser]::ParseFile($library,[ref]$libTokens,[ref]$libErrors)
            $target=@($libAst.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $calls[0].GetCommandName()})
            if(!$libErrors.Count -and $target.Count -eq 1){
                $declared=@($target[0].Body.ParamBlock.Attributes | Where-Object {$_.TypeName.Name -ieq 'CmdletBinding'} | ForEach-Object NamedArguments | Where-Object {$_.ArgumentName -ieq 'SupportsShouldProcess' -and ($_.ExpressionOmitted -or $_.Argument.SafeGetValue() -eq $true)})
                $targetGuard=@($target[0].Body.FindAll({param($n)
                    $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $n.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and
                    $n.Member.Value -ieq 'ShouldProcess' -and
                    $n.Expression -is [Management.Automation.Language.VariableExpressionAst] -and
                    $n.Expression.VariablePath.UserPath -ieq 'PSCmdlet'
                },$false))
                if($declared.Count -eq 1 -and $targetGuard.Count){return 'ShouldProcess'}
            }
        }
    }
    return 'Unclassified'
}
function Test-QuietScriptShouldProcessPolicy {
    <#
    .SYNOPSIS
    Applies the frozen legacy inventory and hash-bound reviewed read-only exceptions to new scripts.
    .PARAMETER WorkspaceRoot
    Repository to inspect, including its checked-in safety policy.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $policyPath=[IO.Path]::Combine($WorkspaceRoot,'build/script-shouldprocess.json')
    if(!(Test-Path -LiteralPath $policyPath)){throw 'ScriptShouldProcessPolicyMissing'}
    $policy=Get-Content -LiteralPath $policyPath -Raw -Encoding utf8|ConvertFrom-Json
    if($policy.SchemaVersion -ne 1){throw 'ScriptShouldProcessPolicyInvalid'}
    $legacy=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($path in $policy.LegacyPaths){
        if($path -match '(^/|\\|(^|/)\.\.(/|$))' -or $path -notmatch '\.ps(1|m1)$' -or !$legacy.Add($path)){throw 'ScriptShouldProcessLegacyPathInvalid'}
    }
    $exceptions=@{}
    foreach($exception in $policy.ReadOnlyExceptions){
        if($exception.Path -match '(^/|\\|(^|/)\.\.(/|$))' -or $exception.SHA256 -cnotmatch '^[A-F0-9]{64}$' -or $exception.Reason.Length -lt 30 -or $exceptions.ContainsKey($exception.Path)){throw 'ScriptShouldProcessExceptionInvalid'}
        $exceptions[$exception.Path]=$exception
    }
    $pending=[Collections.Generic.Stack[string]]::new();$pending.Push([IO.Path]::GetFullPath($WorkspaceRoot))
    $checked=0;$grandfathered=0;$readOnly=0;$libraries=0
    while($pending.Count){
        foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
            if($item.Name -in @('.git','bin','obj','artifacts','.profilers','.cache','.vs')){continue}
            if($item.PSIsContainer -and $item.Name -eq 'lib' -and $item.FullName -ne [IO.Path]::GetFullPath([IO.Path]::Combine($WorkspaceRoot,'scripts/lib'))){continue}
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ScriptSafetyLinkRejected'}
            if($item.PSIsContainer){$pending.Push($item.FullName);continue}
            if($item.Extension -notin @('.ps1','.psm1')){continue}
            $relative=[IO.Path]::GetRelativePath($WorkspaceRoot,$item.FullName).Replace('\','/')
            if($item.Extension -eq '.psm1' -and $relative -like 'scripts/*' -and $relative -notlike 'scripts/lib/*'){
                throw ('ScriptLibraryLocationRequired: '+$relative+'; place dependent script modules under scripts/lib/.')
            }
            if($legacy.Contains($relative)){$grandfathered++;continue}
            $kind=Get-QuietScriptShouldProcess $item.FullName
            if($kind -eq 'ShouldProcess'){$checked++;continue}
            if($kind -eq 'Library'){$libraries++;continue}
            if($exceptions.ContainsKey($relative)){
                if((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -cne $exceptions[$relative].SHA256){throw ('ScriptShouldProcessExceptionStale: '+$relative)}
                $readOnly++;continue
            }
            throw ('ScriptShouldProcessRequired: '+$relative+'; implement SupportsShouldProcess and a real $PSCmdlet.ShouldProcess guard, or document a reviewed read-only exception.')
        }
    }
    [pscustomobject]@{Check='ScriptShouldProcess';Guarded=$checked;Libraries=$libraries;ReviewedReadOnly=$readOnly;LegacyUnqualified=$grandfathered}
}

Export-ModuleMember -Function 'Get-QuietScriptShouldProcess','Test-QuietScriptShouldProcessPolicy'
