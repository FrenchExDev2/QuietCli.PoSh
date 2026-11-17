#requires -Version 7.6
<#
.SYNOPSIS
Blocking ratchet: every export of scripts/lib must be referenced by a script test, except the shrink-only legacy list in test/scripts/coverage.inventory.json.
.PARAMETER WorkspaceRoot
Workspace to inventory; defaults to the parent of this scripts directory.
.PARAMETER UpdateBaseline
Prunes entries that are now tested or no longer exported; never adds one.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))),[switch]$UpdateBaseline)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Execute automation: Test-ScriptsInventory')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Test-ScriptsInventory.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $WorkspaceRoot -UpdateBaseline:$UpdateBaseline
