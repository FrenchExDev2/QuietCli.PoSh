#requires -Version 7.6
<#
.SYNOPSIS
Checks or removes objective boilerplate and reviews executable entry-point ShouldProcess guards.
.PARAMETER WorkspaceRoot
Repository containing scripts.
.PARAMETER Apply
Removes objective headers/announcements, applies missing guards and regenerates the complete review.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Apply)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ScriptReview.psm1')) -DisableNameChecking -ErrorAction Stop
$entries=@(Get-QuietScriptReview $WorkspaceRoot)
$changes=0
foreach($entry in $entries){
    $path=[IO.Path]::Combine($WorkspaceRoot,$entry.Path)
    $before=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $text=$before.Replace("`r`n","`n");$name=[IO.Path]::GetFileNameWithoutExtension($path)
    if([IO.Path]::GetExtension($path) -eq '.ps1'){
        $text=[regex]::Replace($text,'(?im)^#\s*Objecti(?:f|ve)\s*:[^\r\n]*(?:\n|$)','')
        $text=[regex]::Replace($text,"(?m)^[ \t]*Write-Host '#Objective: (?:''|[^'\r\n])*'[ \t]*\n",'')
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
        $announcements=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Host' -and $node.Extent.Text.Contains('#Objective:')},$true)|Sort-Object { $_.Extent.StartOffset } -Descending)
        foreach($command in $announcements){$replacement=$command.Extent.Text.Replace('#Objective:','Progress:');$text=$text.Remove($command.Extent.StartOffset,$command.Extent.EndOffset-$command.Extent.StartOffset).Insert($command.Extent.StartOffset,$replacement)}
    }
    if($entry.NeedsGuard){
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
        $binding=@($ast.ParamBlock.Attributes|Where-Object {$_.TypeName.Name -ieq 'CmdletBinding'})
        if(!$ast.ParamBlock -or $binding.Count -gt 1){throw ('ScriptGuardReviewRequired: '+$entry.Path)}
        if(!$binding.Count){$text=$text.Insert($ast.ParamBlock.Extent.StartOffset,"[CmdletBinding(SupportsShouldProcess)]`n")}else{
            $attribute=$binding[0];$replacement=if($attribute.Extent.Text -match '\(\s*\)'){'[CmdletBinding(SupportsShouldProcess)]'}else{$attribute.Extent.Text -replace '(?i)CmdletBinding\(','CmdletBinding(SupportsShouldProcess, '}
            $text=$text.Remove($attribute.Extent.StartOffset,$attribute.Extent.EndOffset-$attribute.Extent.StartOffset).Insert($attribute.Extent.StartOffset,$replacement)
        }
        $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
        $offset=$ast.EndBlock.Statements[0].Extent.StartOffset
        $guard="if(!`$PSCmdlet.ShouldProcess(`$PSCommandPath,'Execute automation: "+$name+"')){return}`n"
        if($name -in @('New-CiImage','New-CiModuleImage')){
            $match=[regex]::Match($text,'if\(\$PlanOnly\)\{return \$plan\}')
            if(!$match.Success){throw 'ImagePlanGuardAnchorMissing'}
            $offset=$match.Index+$match.Length;$guard="`n"+$guard
        }
        $text=$text.Insert($offset,$guard)
    }
    if($text -cne $before){
        $changes++
        if(!$Apply){throw ('ScriptContractStale: '+$entry.Path)}
        if($PSCmdlet.ShouldProcess($path,'Remove objective boilerplate and normalize preview contract')){[void][IO.File]::WriteAllTextAsync($path,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
    }
}
$reviewed=@(Get-QuietScriptReview $WorkspaceRoot)
foreach($entry in $reviewed){
    $document=[IO.Path]::Combine($WorkspaceRoot,('docs/'+($entry.Path -replace '\.ps(?:m)?1$','.md')))
    if(!(Test-Path -LiteralPath $document)){throw ('ScriptContractDocMissing: '+$entry.Path)}
    $text=[IO.File]::ReadAllTextAsync($document,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Replace("`r`n","`n")
    $block=@('<!-- script-contract:begin -->','## Execution contract','',('Purpose: '+$entry.Purpose),'',('Boundary: **'+$entry.Mode+'**. Preview API: **'+$entry.PreviewContract+'**. Guarded functions: '+$entry.GuardedFunctions+'.'),'','See [the complete review](~/preview-support.md) for orchestration guards, delegated effects and static-analysis limits.','<!-- script-contract:end -->') -join "`n"
    $relative=[IO.Path]::GetRelativePath((Split-Path $document -Parent),([IO.Path]::Combine($WorkspaceRoot,'docs/scripts/preview-support.md'))).Replace('\','/')
    $block=$block.Replace('~/preview-support.md',$relative)
    $pattern='(?s)<!-- script-contract:begin -->.*?<!-- script-contract:end -->'
    $expected=if($text -match $pattern){[regex]::Replace($text,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($match)$block})}else{$text.TrimEnd()+"`n`n"+$block+"`n"}
    if($expected -cne $text){
        if(!$Apply){throw ('ScriptContractDocStale: '+$entry.Path)}
        if($PSCmdlet.ShouldProcess($document,'Update generated script execution contract')){[void][IO.File]::WriteAllTextAsync($document,$expected,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
    }
}
$review=Get-QuietScriptReviewReadme $WorkspaceRoot
$path=[IO.Path]::Combine($WorkspaceRoot,'docs/scripts/preview-support.md')
$footer=@('<!-- credits:begin -->','## Credits','',"This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).",'<!-- credits:end -->') -join "`n"
$review+="`n"+$footer+"`n"
$current=if(Test-Path $path){Get-Content $path -Raw -Encoding utf8}else{$null}
if($current -cne $review){
    if(!$Apply){throw 'ScriptPreviewReviewStale'}
    if($PSCmdlet.ShouldProcess($path,'Write complete script preview review')){[void][IO.File]::WriteAllTextAsync($path,$review,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
}
[pscustomobject]@{Check='ScriptContracts';Scripts=$entries.Count;Updated=$changes;RemainingGaps=@(Get-QuietScriptReview $WorkspaceRoot|Where-Object NeedsGuard).Count}
