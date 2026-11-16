#requires -Version 7.6
<#
.SYNOPSIS
Checks or synchronizes generated workspace and companion solutions.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER Apply
Writes generated definitions; default only checks.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Apply)
if($Apply -and !$PSCmdlet.ShouldProcess($WorkspaceRoot,'Synchronize workspace solutions')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceSolutions.psm1')) -DisableNameChecking -ErrorAction Stop
Sync-QuietWorkspaceSolutions -WorkspaceRoot $WorkspaceRoot -Apply:$Apply -WhatIf:$WhatIfPreference -Confirm:$false
