#requires -Version 7.6
<#
.SYNOPSIS
Read-only workflow documentation gate; fails for missing, stale or inconsistent contracts.
.PARAMETER WorkspaceRoot
Repository whose workflow documents and generated index must match.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
& ([IO.Path]::Combine($PSScriptRoot,'Sync-GitHubWorkflowsReadme.ps1')) -WorkspaceRoot $WorkspaceRoot
