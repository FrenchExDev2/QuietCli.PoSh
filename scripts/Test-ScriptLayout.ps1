#requires -Version 7.6
<#
.SYNOPSIS
Checks automation entry-point names, function placement, imports and path composition without executing scripts.
.PARAMETER WorkspaceRoot
Checkout or exported staged snapshot to inspect.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=[IO.Path]::GetDirectoryName($PSScriptRoot))
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ScriptLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Test-QuietScriptLayout -WorkspaceRoot $WorkspaceRoot
