#requires -Version 7.6
<#
.SYNOPSIS
Requires dependency freshness, qualified validation tooling, actual module exports and product acceptance evidence.
.PARAMETER DependencyReportPath
Saved whitelisted dependency report.
.PARAMETER ToolingSummaryPath
Complete monitored tooling qualification summary.
.PARAMETER AcceptanceReceiptPath
Receipt binding product tests, isolated restore and recovery artifacts to the dependency report.
.PARAMETER ExportSummaryPath
Actual import/Get-Module export summaries for the selected module entries.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$DependencyReportPath,
    [Parameter(Mandatory)][string]$ToolingSummaryPath,[string]$AcceptanceReceiptPath,[string[]]$ExportSummaryPath)
Import-Module (Join-Path $PSScriptRoot 'lib/Migration.Dependencies.psm1') -ErrorAction Stop
$report=Test-MigrationQualification @PSBoundParameters
$report
if(!$report.Passed){throw 'MigrationQualificationBlocked'}
