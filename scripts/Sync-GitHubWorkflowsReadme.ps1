#requires -Version 7.6
<#
.SYNOPSIS
Checks workflow documentation receipts, generated job graphs and the regenerable GitHub index.
.PARAMETER WorkspaceRoot
Repository containing .github/workflows and docs/ci/github.
.PARAMETER Apply
Regenerates graph blocks and README after all authored documents match their source receipt.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Apply)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WorkflowDocumentation.ps1')
$entries=@(Get-QuietWorkflowDocumentation $WorkspaceRoot)
$updates=[Collections.Generic.List[object]]::new()
foreach($entry in $entries){
    $path=Join-Path $WorkspaceRoot $entry.DocRelativePath
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw ('WorkflowDocumentationMissing: '+$entry.RelativePath)}
    $text=[IO.File]::ReadAllTextAsync($path,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult().Replace("`r`n","`n")
    $receipt=[regex]::Match($text,'(?m)^<!-- workflow-source-sha256: ([A-F0-9]{64}) -->$')
    if(!$receipt.Success -or $receipt.Groups[1].Value -cne $entry.SourceSHA256){throw ('WorkflowDocumentationStale: review '+$entry.DocRelativePath+' against '+$entry.RelativePath)}
    foreach($heading in @('Purpose','Triggers','Scripts and effects','Validation and limits')){
        if($text -notmatch ('(?m)^## '+[regex]::Escape($heading)+'$')){throw ('WorkflowDocumentationSectionMissing: '+$entry.DocRelativePath+'/'+$heading)}
    }
    $pattern='(?s)<!-- workflow-generated:begin -->.*?<!-- workflow-generated:end -->'
    if([regex]::Matches($text,$pattern).Count -ne 1){throw ('WorkflowDocumentationGraphMissing: '+$entry.DocRelativePath)}
    $expected=[regex]::Replace($text,$pattern,[Text.RegularExpressions.MatchEvaluator]{param($m)$entry.Generated})
    if($expected -cne $text){$updates.Add(@{Path=$path;Content=$expected})}
}
$readme=Join-Path $WorkspaceRoot 'docs/ci/github/README.md'
$expected=Get-QuietWorkflowReadme $entries
# Credits are shared with the existing documentation generator, and remain part of the index contract.
$relative=[IO.Path]::GetRelativePath((Split-Path $readme -Parent),(Join-Path $WorkspaceRoot CREDITS.md)).Replace('\','/')
$credits=@('<!-- credits:begin -->','## Credits','',"This document is covered by the mandatory [CREDITS.md]($relative), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).",'<!-- credits:end -->') -join "`n"
$expected+="`n"+$credits+"`n"
$current=if(Test-Path -LiteralPath $readme){[IO.File]::ReadAllTextAsync($readme,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Replace("`r`n","`n")}else{$null}
if($current -cne $expected){$updates.Add(@{Path=$readme;Content=$expected})}
if(!$Apply -and $updates.Count){throw ('WorkflowDocumentationGeneratedContentStale: '+($updates.Path -join ', '))}
foreach($update in $updates){
    if($PSCmdlet.ShouldProcess($update.Path,'Regenerate workflow documentation graph/index')){
        [void][IO.Directory]::CreateDirectory((Split-Path $update.Path -Parent))
        [void][IO.File]::WriteAllTextAsync($update.Path,$update.Content,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
}
[pscustomobject]@{Check='GitHubWorkflowDocs';Workflows=$entries.Count;Changes=$updates.Count;Applied=[bool]$Apply -and !$WhatIfPreference}
