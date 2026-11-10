#requires -Version 7.6
<#
.SYNOPSIS
Runs a monitored import/Get-Module observation for one explicitly selected whitelist module.
.PARAMETER SourceRoot
Source workspace containing the selected candidate.
.PARAMETER PolicyPath
Explicit whitelist policy, defaulting to the canonical migration selection.
.PARAMETER ItemId
Exact selected policy identifier.
.PARAMETER EntryPath
Explicit psd1 or psm1 path relative to that candidate's directory.
.PARAMETER ExpectedFunctions
Optional exact function export contract; omission produces observation only.
.PARAMETER ExpectedCmdlets
Optional exact cmdlet export contract, including an explicitly empty set.
.PARAMETER RunDirectory
New external report directory.
.PARAMETER StageCopy
Imports a verified owned copy; reports the location-sensitive scope explicitly.
.PARAMETER TimeoutSeconds
Owned worker deadline.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$SourceRoot,
    [string]$PolicyPath=(Join-Path $PSScriptRoot '../docs/requirements/migration-whitelist.json'),
    [Parameter(Mandatory)][string]$ItemId,[Parameter(Mandatory)][string]$EntryPath,
    [AllowEmptyCollection()][string[]]$ExpectedFunctions,[AllowEmptyCollection()][string[]]$ExpectedCmdlets,[switch]$StageCopy,[string]$RunDirectory,
    [ValidateRange(1,600)][int]$TimeoutSeconds=60)
Import-Module (Join-Path $PSScriptRoot 'lib/Migration.Exports.psm1') -ErrorAction Stop
$forward=@{};foreach($key in $PSBoundParameters.Keys){$forward[$key]=$PSBoundParameters[$key]}
$forward.SourceRoot=$SourceRoot;$forward.PolicyPath=$PolicyPath;$forward.ItemId=$ItemId;$forward.EntryPath=$EntryPath;$forward.TimeoutSeconds=$TimeoutSeconds
Migration.Exports\Test-PowerShellModuleExports @forward
