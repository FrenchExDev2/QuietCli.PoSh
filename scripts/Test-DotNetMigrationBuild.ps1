#requires -Version 7.6
<#
.SYNOPSIS
Builds discovered selected .NET solutions/projects in Release, with table and JSON output.
.PARAMETER SourceRoot
Source workspace containing Net/FrenchExDev.
.PARAMETER PolicyPath
Explicit migration candidate policy.
.PARAMETER ItemId
Optional configured candidate IDs.
.PARAMETER Target
Exact paths relative to Net/FrenchExDev; omit to build all selected entry points.
.PARAMETER AllDiscovered
Explicit assessment beyond whitelist entry points; does not authorize migration.
.PARAMETER NoRestore
Adds --no-restore.
.PARAMETER RunDirectory
New external directory retaining logs, progress and build-results.json.
.PARAMETER JsonPath
Optional additional new JSON result file.
.PARAMETER TimeoutSeconds
Per-target deadline.
.PARAMETER TotalTimeoutSeconds
Whole campaign deadline.
.PARAMETER OutputFormat
Table displays results and JSON path; Json emits only JSON; Object returns the typed report.
.PARAMETER RequireSuccess
Throws after reporting if the complete selected build batch did not pass.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$SourceRoot,
    [string]$PolicyPath=(Join-Path $PSScriptRoot '../docs/requirements/migration-whitelist.json'),
    [string[]]$ItemId,[string[]]$Target,[switch]$AllDiscovered,[switch]$NoRestore,
    [string]$RunDirectory,[string]$JsonPath,[ValidateRange(1,7200)][int]$TimeoutSeconds=300,
    [ValidateRange(1,86400)][int]$TotalTimeoutSeconds=1800,
    [ValidateSet('Table','Json','Object')][string]$OutputFormat='Table',[switch]$RequireSuccess)
Import-Module (Join-Path $PSScriptRoot 'lib/Migration.DotNet.psm1') -ErrorAction Stop
$forward=@{SourceRoot=$SourceRoot;PolicyPath=$PolicyPath;TimeoutSeconds=$TimeoutSeconds;TotalTimeoutSeconds=$TotalTimeoutSeconds}
foreach($key in $PSBoundParameters.Keys){if($key -notin @('OutputFormat','RequireSuccess')){$forward[$key]=$PSBoundParameters[$key]}}
$report=Invoke-DotNetMigrationBuild @forward
switch($OutputFormat){
    Json {ConvertTo-Json $report -Depth 32}
    Object {$report}
    Table {Format-DotNetMigrationBuildTable $report | ForEach-Object {Write-Host $_};if($report.ReportPath){Write-Host "JSON: $($report.ReportPath)"}}
}
if($RequireSuccess -and !$WhatIfPreference -and !$report.Passed){throw 'DotNetMigrationBuildFailed'}
