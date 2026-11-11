#requires -Version 7.6
<#
.SYNOPSIS
Renders an existing Measure-ColdStart.ps1 / Invoke-ColdStartGate.ps1 JSON report as console tables.

.DESCRIPTION
Reads one `ab-*.json` (or `aa-*.json`) cold-start report and prints its Summary verdicts and Footprint
(on-disk size and, when measured, .nupkg package size) as Unicode tables, without rerunning any measurement.
By default picks the most recently written `ab-*.json` under -ArtifactsDirectory.

.PARAMETER Path
Specific report JSON to render. When omitted, the newest file matching -Pattern under -ArtifactsDirectory is used.

.PARAMETER ArtifactsDirectory
Directory searched for the latest report when -Path is omitted.

.PARAMETER Pattern
Filename glob used to pick the latest report when -Path is omitted. Use 'aa-*.json' to inspect an A/A control
instead of an A/B result.

.EXAMPLE
./scripts/Show-ColdStartReport.ps1

.EXAMPLE
./scripts/Show-ColdStartReport.ps1 -Path artifacts/coldstart/ab-coldstart-100-readytorun-20261108T095226Z.json
#>
using module ./lib/RunLog.psm1
[CmdletBinding()]
param(
    [string]$Path,
    [string]$ArtifactsDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/coldstart'),
    [ValidateNotNullOrEmpty()][string]$Pattern = 'ab-*.json'
)
$ErrorActionPreference = 'Stop'
foreach ($module in 'RunEncoding', 'RunFormat') { Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") -Force }

function Get-LatestColdStartReport {
    <#
    .SYNOPSIS
    Finds the most recently written report file matching a glob under a directory.
    .PARAMETER Directory
    Directory to search (not recursive: reports are written flat).
    .PARAMETER Pattern
    Filename glob, for example 'ab-*.json'.
    #>
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Pattern)
    $candidate = Get-ChildItem -LiteralPath $Directory -Filter $Pattern -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $candidate) { throw "ColdStartReportNotFound: no file matching '$Pattern' under $Directory" }
    return $candidate.FullName
}

$reportPath = if ($Path) { [IO.Path]::GetFullPath($Path) } else { Get-LatestColdStartReport -Directory $ArtifactsDirectory -Pattern $Pattern }
$report = Read-RunTextFile -Path $reportPath | ConvertFrom-Json

$baselineLabel = $report.Parameters.BaselineLabel
$candidateLabel = $report.Parameters.CandidateLabel

''
"Project: QuietCli.Core.PoSh | Task: cold-start report ($baselineLabel vs. $candidateLabel)"
"Report: $reportPath"
"Machine: $($report.Environment.MachineName) | PowerShell $($report.Environment.PowerShell) | CLR $($report.Environment.Clr) | RID $($report.Environment.RuntimeIdentifier)"
''

$summaryRows = @(
    foreach ($phase in $report.Summary.PSObject.Properties) {
        $entry = $phase.Value
        , @($phase.Name, (Format-RunDuration $entry.Baseline.Median), (Format-RunDuration $entry.Candidate.Median), "$(Format-RunDuration $entry.Difference.Median) [$(Format-RunDuration $entry.Difference.Low), $(Format-RunDuration $entry.Difference.High)]", $entry.Verdict)
    }
)
Format-RunTable -Headers @('Phase', "Baseline ($baselineLabel)", "Candidate ($candidateLabel)", 'Difference (95% CI)', 'Verdict') -Rows $summaryRows -RightAligned @(1, 2)
''

$footprint = $report.Footprint
$footprintRows = @(
    , @($baselineLabel, (Format-RunDataSize $footprint.BaselineBytes), (Format-RunDataSize $footprint.BaselineHostedBytes), (Format-RunDataSize $footprint.BaselinePackageBytes))
    , @($candidateLabel, (Format-RunDataSize $footprint.CandidateBytes), (Format-RunDataSize $footprint.CandidateHostedBytes), (Format-RunDataSize $footprint.CandidatePackageBytes))
    , @('Difference (candidate - baseline)', (Format-RunDataSize $footprint.DifferenceBytes -Signed), (Format-RunDataSize $footprint.HostedDifferenceBytes -Signed), (Format-RunDataSize $footprint.PackageDifferenceBytes -Signed))
)
"Module footprint: 'On disk' is every file under the module root (every bundled RID, used or not); 'Hosted path' is only the CLR/RID slot this process actually loads, including a selected ReadyToRun child (Auto hosting)$(if ($null -eq $footprint.BaselineHostedBytes) { ', shown as - for reports predating this measurement' }); 'Package' is the .nupkg size Compress-PSResource$(if ($null -eq $footprint.BaselinePackageBytes) { ' (not measured for this report; rerun with -MeasurePackageSize to fill it)' }) would publish."
Format-RunTable -Headers @('Variant', 'On disk', 'Hosted path', 'Package (.nupkg)') -Rows $footprintRows -RightAligned @(1, 2, 3)
''
