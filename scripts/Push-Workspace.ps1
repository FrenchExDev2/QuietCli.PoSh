#requires -Version 7.6
<#
.SYNOPSIS
Pushes one monorepo branch and summarizes feature/fix updates on its existing GitHub PR.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Remote
Configured remote name, origin by default.
.PARAMETER Branch
Explicit branch name, main by default.
.PARAMETER Repository
Only Workspace exists in the monorepo.
.PARAMETER PrCommentBodyFile
Optional UTF-8 Markdown update with implementation details and validation. Otherwise list PR commits.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',[ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Branch='main',[ValidateSet('Workspace')][string]$Repository='Workspace',[string]$PrCommentBodyFile)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Push-Workspace')){return}
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)
. (Join-Path $PSScriptRoot PullRequestUpdates.ps1)
$body=$null
if($PrCommentBodyFile){
    $body=[IO.File]::ReadAllTextAsync([IO.Path]::GetFullPath($PrCommentBodyFile,$PWD.Path),[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    if([string]::IsNullOrWhiteSpace($body) -or $body.Length -gt 60000){throw 'PullRequestUpdateBodyInvalid'}
}
Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'push','--set-upstream',$Remote,$Branch) $WorkspaceRoot
if($Branch -cmatch '^(feature|fix)/'){
    try{Send-QuietPullRequestUpdate -WorkspaceRoot $WorkspaceRoot -Remote $Remote -Branch $Branch -Body $body -Confirm:$false}
    catch{Write-Warning ('Push succeeded; GitHub PR update failed: '+$_.Exception.Message)}
}
