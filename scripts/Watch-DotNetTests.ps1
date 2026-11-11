#requires -Version 7.6
<#
.SYNOPSIS
Reopens the shared read-only monitor for a saved .NET tooling campaign.
.PARAMETER StatusPath
Saved status.json under the external run directory.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$StatusPath)
$ErrorActionPreference='Stop'
$status=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatusPath)
& (Join-Path $PSScriptRoot 'Watch-Tests.ps1') -RunDirectory (Split-Path $status -Parent)
