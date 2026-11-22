#requires -Version 7.6
<#
.SYNOPSIS
Pushes one monorepo branch and summarizes feature, fix, release and companion updates on its existing GitHub PR.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Remote
Configured remote name, origin by default.
.PARAMETER Branch
Explicit branch name, main by default.
.PARAMETER Repository
Only Workspace exists in the monorepo.
.PARAMETER ExpectedHead
Push this exact local branch SHA through a non-forced refspec and preserve the branch's tracking configuration.
.PARAMETER PrCommentBodyFile
Optional UTF-8 Markdown update with implementation details and validation. Otherwise list PR commits.
.PARAMETER PrDescriptionBodyFile
Optional reviewed UTF-8 Markdown replacing the existing PR description through GitHub CLI.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',[ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Branch='main',[ValidateSet('Workspace')][string]$Repository='Workspace',[ValidatePattern('\A[a-f0-9]{40}\z')][string]$ExpectedHead,[string]$PrCommentBodyFile,[string]$PrDescriptionBodyFile)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Push-Workspace')){return}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PullRequestUpdates.psm1')) -DisableNameChecking -ErrorAction Stop
$documents=@{Comment=$null;Description=$null}
foreach($entry in @(@{Name='Comment';Path=$PrCommentBodyFile},@{Name='Description';Path=$PrDescriptionBodyFile})){
    if(!$entry.Path){continue}
    $text=[IO.File]::ReadAllTextAsync([IO.Path]::GetFullPath($entry.Path,$PWD.Path),[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    if([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 60000){throw 'PullRequestUpdateBodyInvalid'}
    $documents[$entry.Name]=$text
}
if($ExpectedHead){
    $ref='refs/heads/'+$Branch
    $actual=Invoke-QuietPullRequestTool $WorkspaceRoot git @('rev-parse','--verify',$ref)
    if($actual -cne $ExpectedHead){throw 'PushWorkspaceHeadChanged: the selected branch no longer matches ExpectedHead.'}
    Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'push','--',$Remote,($ExpectedHead+':'+$ref)) $WorkspaceRoot
}else{
    Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'push','--set-upstream',$Remote,$Branch) $WorkspaceRoot
}
if($Branch -cmatch '^(feature|fix|release|companion)/'){
    try{
        $update=@{WorkspaceRoot=$WorkspaceRoot;Remote=$Remote;Branch=$Branch;Body=$documents.Comment;Confirm=$false}
        if($PrDescriptionBodyFile){$update.Description=$documents.Description}
        Send-QuietPullRequestUpdate @update
    }
    catch{Write-Warning ('Push succeeded; GitHub PR update failed: '+$_.Exception.Message)}
}
