#requires -Version 7.6
<#
.SYNOPSIS
Inspects only whitelisted migration candidates and optionally enforces the dependency gate.
.PARAMETER SourceRoot
Existing i2 source root; no sources are modified or executed.
.PARAMETER PolicyPath
Explicit candidate whitelist with selection and external dependency decisions.
.PARAMETER ItemId
Optional exact policy identifiers; values are validated by the library against the selected policy.
.PARAMETER OutputPath
Optional new JSON evidence file. WhatIf suppresses this write.
.PARAMETER RequireGate
Throws if selected candidates do not satisfy the dependency gate.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot,
    [string]$PolicyPath=(Join-Path $PSScriptRoot '../docs/requirements/migration-whitelist.json'),
    [string[]]$ItemId,[string]$OutputPath,[switch]$RequireGate)
Import-Module (Join-Path $PSScriptRoot 'lib/Migration.Dependencies.psm1') -ErrorAction Stop
$arguments=@{SourceRoot=$SourceRoot;PolicyPath=$PolicyPath}
if($ItemId){$arguments.ItemId=$ItemId}
$report=Get-MigrationDependencyReport @arguments
if($OutputPath){
    $forward=@{Report=$report;Path=$OutputPath}
    foreach($key in @('WhatIf','Confirm')){if($PSBoundParameters.ContainsKey($key)){$forward[$key]=$PSBoundParameters[$key]}}
    Export-MigrationDependencyReport @forward
}
$report
if($RequireGate -and !$report.Passed){throw 'MigrationDependencyGateBlocked'}
