#requires -Version 7.6
<#
.SYNOPSIS
Checks PowerShell syntax and function help using inert source analysis, including during commit preview.
.PARAMETER WorkspaceRoot
Checkout or exported staged snapshot to inspect without executing its sources.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=[IO.Path]::GetDirectoryName($PSScriptRoot))
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PowerShellSources.psm1')) -DisableNameChecking -ErrorAction Stop
Test-QuietPowerShellSources -WorkspaceRoot $WorkspaceRoot
