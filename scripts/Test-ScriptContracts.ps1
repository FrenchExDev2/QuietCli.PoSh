#requires -Version 7.6
<#
.SYNOPSIS
Checks absent objective boilerplate and the preview-support review without applying changes.
.PARAMETER WorkspaceRoot
Repository to inspect.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot Sync-ScriptContracts.ps1) -WorkspaceRoot $WorkspaceRoot
