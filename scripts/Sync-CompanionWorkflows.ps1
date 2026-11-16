#requires -Version 7.6
<#
.SYNOPSIS
Checks or synchronizes explicit companion workflow entry points.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER Apply
Writes generated YAML; default checks only.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Apply)
if($Apply -and !$PSCmdlet.ShouldProcess($WorkspaceRoot,'Synchronize companion workflows')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
Sync-QuietCompanionWorkflows -WorkspaceRoot $WorkspaceRoot -Apply:$Apply -WhatIf:$WhatIfPreference -Confirm:$false
