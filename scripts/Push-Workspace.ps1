# Objectif : Pousser explicitement la branche du monorepo sans force ni nouvelle tentative.
#requires -Version 7.6
<#
.SYNOPSIS
Pushes one monorepo branch to its configured remote; never commits or retries.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Remote
Configured remote name, origin by default.
.PARAMETER Branch
Explicit branch name, main by default.
.PARAMETER Repository
Only Workspace exists in the monorepo.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',[ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Branch='main',[ValidateSet('Workspace')][string]$Repository='Workspace')
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)
Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'push','--set-upstream',$Remote,$Branch) $WorkspaceRoot
