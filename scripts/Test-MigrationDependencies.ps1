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
.PARAMETER BuildDotNet
Runs an explicitly selected Release build assessment after static inspection.
.PARAMETER BuildTarget
Exact build entry paths relative to Net/FrenchExDev.
.PARAMETER NoRestore
Disables implicit restore in the optional Release build.
.PARAMETER BuildRunDirectory
New external build report directory.
.PARAMETER BuildJsonPath
Optional additional new JSON build result.
.PARAMETER OutputFormat
Object preserves the original report contract; Json emits JSON; Table shows the optional build table.
.PARAMETER BuildTimeoutSeconds
Per-target Release build deadline.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot,
    [string]$PolicyPath=(Join-Path $PSScriptRoot '../docs/requirements/migration-whitelist.json'),
    [string[]]$ItemId,[string]$OutputPath,[switch]$RequireGate,[switch]$BuildDotNet,
    [string[]]$BuildTarget,[switch]$NoRestore,[string]$BuildRunDirectory,[string]$BuildJsonPath,
    [ValidateRange(1,7200)][int]$BuildTimeoutSeconds=300,
    [ValidateSet('Object','Json','Table')][string]$OutputFormat='Object')
if(!$BuildDotNet -and ($BuildTarget -or $NoRestore -or $BuildRunDirectory -or $BuildJsonPath -or $OutputFormat -eq 'Table')){throw 'DotNetBuildOptionsRequireBuildDotNet'}
Import-Module (Join-Path $PSScriptRoot 'lib/Migration.Dependencies.psm1') -ErrorAction Stop
$arguments=@{SourceRoot=$SourceRoot;PolicyPath=$PolicyPath}
if($ItemId){$arguments.ItemId=$ItemId}
$report=Get-MigrationDependencyReport @arguments
if($BuildDotNet){
    Import-Module (Join-Path $PSScriptRoot 'lib/Migration.DotNet.psm1') -ErrorAction Stop
    $build=@{SourceRoot=$SourceRoot;PolicyPath=$PolicyPath;NoRestore=$NoRestore;TimeoutSeconds=$BuildTimeoutSeconds}
    if($ItemId){$build.ItemId=$ItemId};if($BuildTarget){$build.Target=$BuildTarget}
    if($BuildRunDirectory){$build.RunDirectory=$BuildRunDirectory};if($BuildJsonPath){$build.JsonPath=$BuildJsonPath}
    foreach($key in @('WhatIf','Confirm')){if($PSBoundParameters.ContainsKey($key)){$build[$key]=$PSBoundParameters[$key]}}
    $report | Add-Member NoteProperty DotNetBuild (Invoke-DotNetMigrationBuild @build)
}
if($OutputPath){
    $forward=@{Report=$report;Path=$OutputPath}
    foreach($key in @('WhatIf','Confirm')){if($PSBoundParameters.ContainsKey($key)){$forward[$key]=$PSBoundParameters[$key]}}
    Export-MigrationDependencyReport @forward
}
switch($OutputFormat){
    Object {$report}
    Json {ConvertTo-Json $report -Depth 64}
    Table {Format-DotNetMigrationBuildTable $report.DotNetBuild | ForEach-Object {Write-Host $_};if($report.DotNetBuild.ReportPath){Write-Host "JSON: $($report.DotNetBuild.ReportPath)"}}
}
if($RequireGate -and !$report.Passed){throw 'MigrationDependencyGateBlocked'}
