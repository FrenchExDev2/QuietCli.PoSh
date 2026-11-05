# Objectif : Créer explicitement un commit cohérent du monorepo, sans pousser.
#requires -Version 7.6
<#
.SYNOPSIS
Stages the monorepo and its refreshed project lock, then commits once; never pushes.
.PARAMETER Message
Required commit message.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Repository
Only Workspace exists; retained to reject accidental requests for independent module commits.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$Message,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Workspace')][string]$Repository='Workspace')
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)
$null=& (Join-Path $PSScriptRoot Update-WorkspaceLock.ps1) -WorkspaceRoot $WorkspaceRoot
$null=Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'add','--all','--') $WorkspaceRoot
Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'commit','-m',$Message) $WorkspaceRoot
