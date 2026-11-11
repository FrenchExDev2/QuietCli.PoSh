#requires -Version 7.6
<#
.SYNOPSIS
Checks the complete Core test classification without loading the engine or executing a case.
.PARAMETER WorkspaceRoot
Working tree or exported staged snapshot containing the Core runner.
.PARAMETER Plan
Returns the complete ordered scheduling plan without executing cases.
.PARAMETER MaxConcurrency
Shared worker budget used when resolving the optional plan.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Plan,[ValidateRange(1,32)][int]$MaxConcurrency=4)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/TestCaseMetadata.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'lib/TestCaseScheduling.psm1') -ErrorAction Stop
$inventory=Get-QuietTestCaseInventory -Path (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1')
$policy=Get-QuietTestExecutionPolicy -ManifestPath (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -CaseNames $inventory.CaseNames
if($Plan){Get-QuietTestExecutionPlan -CaseNames $inventory.CaseNames -Policy $policy -MaxConcurrency $MaxConcurrency}else{
    [pscustomobject]@{Check='TestCaseMetadata';Cases=$inventory.Count;Unit=@($inventory.Metadata.Values|Where-Object TestKind -CEQ Unit).Count;Integration=@($inventory.Metadata.Values|Where-Object TestKind -CEQ Integration).Count;IsolatedProcess=$policy.Cases.Values.Where({$_.Mode -ceq 'IsolatedProcess'}).Count;MaxParallelCases=$policy.MaxParallelCases}
}
