#requires -Version 7.6
<#
.SYNOPSIS
Runs the source-only resource documentation gate.
.PARAMETER WorkspaceRoot
Repository whose declared resources and dependency inventory must match.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
& ([IO.Path]::Combine($PSScriptRoot,'Sync-ResourcesReadme.ps1')) -WorkspaceRoot $WorkspaceRoot
