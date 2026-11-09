# Objectif : Créer explicitement un commit cohérent du monorepo, sans pousser.
#requires -Version 7.6
<#
.SYNOPSIS
Stages the monorepo and its refreshed project lock, then commits once; never pushes.
.PARAMETER Message
Required commit message, without trailers.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Repository
Only Workspace exists; retained to reject accidental requests for independent module commits.
.PARAMETER CoAuthoredBy
Opt-in, no trailer by default. Co-Authored-By trailers appended after the message, one per
contributing agent explicitly named by the caller; each entry is either `Name <email>` or a known
agent name from `$knownCoAuthors` (see docs/agents/README.md for the documented list). Skips an
entry already present verbatim in Message so a caller-supplied trailer is never duplicated.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$Message,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Workspace')][string]$Repository='Workspace',[string[]]$CoAuthoredBy=$null)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)
$knownCoAuthors=@{Claude='Claude Sonnet 5 <noreply@anthropic.com>';Codex='Codex <noreply@openai.com>'}
$trailers=[Collections.Generic.List[string]]::new()
foreach($entry in $CoAuthoredBy){
    $resolved=if($knownCoAuthors.ContainsKey($entry)){$knownCoAuthors[$entry]}else{$entry}
    $trailer='Co-Authored-By: '+$resolved
    if($Message.Contains($trailer) -or $trailers.Contains($trailer)){continue}
    $trailers.Add($trailer)
}
$finalMessage=if($trailers.Count){$Message.TrimEnd()+"`n`n"+($trailers -join "`n")}else{$Message}
$null=& (Join-Path $PSScriptRoot Update-WorkspaceLock.ps1) -WorkspaceRoot $WorkspaceRoot
$null=Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'add','--all','--') $WorkspaceRoot
Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'commit','-m',$finalMessage) $WorkspaceRoot
