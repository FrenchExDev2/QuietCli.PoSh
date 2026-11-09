#requires -Version 7.6
<#
.SYNOPSIS
Renders every cold-start A/B report found on disk (Windows and every Linux container run) as one table, without
rerunning any measurement. Repeatable: re-run any time after Invoke-ColdStartMatrix.ps1 (or any individual gate)
to see the current state of artifacts/coldstart and artifacts/coldstart-containers.

.DESCRIPTION
Invoke-ColdStartGate.ps1 writes one ab-*.json straight into -ArtifactsDirectory for a local (Windows) run.
Invoke-ContainerColdStart.ps1 writes one per container run instead, copied back under its own run directory as
<run>/guest/ab-*.json. This script finds every one of those across both locations, parses each independently
(a report that fails to parse or is missing an expected field is reported as a row-level error, not a hard
failure of the whole render), and prints one row per report — most recent first — plus a footprint table.

.PARAMETER ArtifactsDirectory
Directory holding local (Windows) ab-*.json reports, searched flat.

.PARAMETER ContainersDirectory
Directory holding one subdirectory per container run, each with its own guest/ab-*.json, searched recursively.

.PARAMETER Pattern
Filename glob applied in both locations.

.EXAMPLE
./scripts/Show-ColdStartMatrixReport.ps1
#>
using module ./lib/RunLog.psm1
[CmdletBinding()]
param(
    [string]$ArtifactsDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/coldstart'),
    [string]$ContainersDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/coldstart-containers'),
    [ValidateNotNullOrEmpty()][string]$Pattern = 'ab-*.json'
)
$ErrorActionPreference = 'Stop'
foreach ($module in 'RunEncoding', 'RunFormat') { Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") -Force }

function Get-ColdStartMatrixReportFiles {
    <#
    .SYNOPSIS
    Finds every local and containerized A/B report file on disk, each tagged with its originating target label.
    .PARAMETER ArtifactsDirectory
    Local (Windows) report directory, searched flat.
    .PARAMETER ContainersDirectory
    Container run root, searched recursively for guest/<Pattern>.
    .PARAMETER Pattern
    Filename glob.
    #>
    param([Parameter(Mandatory)][string]$ArtifactsDirectory, [Parameter(Mandatory)][string]$ContainersDirectory, [Parameter(Mandatory)][string]$Pattern)
    $found = @()
    if (Test-Path -LiteralPath $ArtifactsDirectory -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $ArtifactsDirectory -Filter $Pattern -File -ErrorAction SilentlyContinue) {
            $found += [pscustomobject]@{ Target = 'windows (local)'; Path = $file.FullName; WrittenUtc = $file.LastWriteTimeUtc }
        }
    }
    if (Test-Path -LiteralPath $ContainersDirectory -PathType Container) {
        foreach ($run in Get-ChildItem -LiteralPath $ContainersDirectory -Directory -ErrorAction SilentlyContinue) {
            $guest = Join-Path $run.FullName 'guest'
            if (-not (Test-Path -LiteralPath $guest -PathType Container)) { continue }
            foreach ($file in Get-ChildItem -LiteralPath $guest -Filter $Pattern -File -ErrorAction SilentlyContinue) {
                $found += [pscustomobject]@{ Target = $run.Name; Path = $file.FullName; WrittenUtc = $file.LastWriteTimeUtc }
            }
        }
    }
    return @($found | Sort-Object WrittenUtc -Descending)
}

function Format-RunMatrixVerdictCell {
    <#
    .SYNOPSIS
    Renders one phase's verdict and signed median difference as a single compact cell.
    .PARAMETER Entry
    One Summary.<phase> entry (Verdict + Difference.Median), or $null when the phase is missing from this report.
    #>
    param($Entry)
    if ($null -eq $Entry) { return '-' }
    $sign = if ($Entry.Difference.Median -ge 0) { '+' } else { '' }
    return "$($Entry.Verdict) ($sign$(Format-RunDuration $Entry.Difference.Median))"
}

$files = @(Get-ColdStartMatrixReportFiles -ArtifactsDirectory $ArtifactsDirectory -ContainersDirectory $ContainersDirectory -Pattern $Pattern)

''
"Project: QuietCli.Core.PoSh | Task: cold-start matrix report (every run on disk)"
"Local reports: $ArtifactsDirectory"
"Container reports: $ContainersDirectory"
''

if ($files.Count -eq 0) { "No report matching '$Pattern' found under either location."; return }

$summaryRows = @()
$footprintRows = @()
foreach ($file in $files) {
    try {
        $report = Read-RunTextFile -Path $file.Path | ConvertFrom-Json
        $baselineLabel = $report.Parameters.BaselineLabel
        $candidateLabel = $report.Parameters.CandidateLabel
        $rid = $report.Environment.RuntimeIdentifier
        $summary = $report.Summary
        $footprint = $report.Footprint
        $summaryRows += , @(
            $file.WrittenUtc.ToString('yyyy-MM-dd HH:mm'),
            $file.Target,
            "$baselineLabel vs. $candidateLabel",
            $(if ($rid) { $rid } else { '-' }),
            (Format-RunMatrixVerdictCell $summary.Import),
            (Format-RunMatrixVerdictCell $summary.'First call'),
            (Format-RunMatrixVerdictCell $summary.'Second call')
        )
        $footprintRows += , @(
            $file.Target,
            (Format-RunDataSize $footprint.DifferenceBytes -Signed),
            (Format-RunDataSize $footprint.HostedDifferenceBytes -Signed),
            (Format-RunDataSize $footprint.PackageDifferenceBytes -Signed)
        )
    }
    catch {
        $summaryRows += , @($file.WrittenUtc.ToString('yyyy-MM-dd HH:mm'), $file.Target, "unreadable: $_", '-', '-', '-', '-')
    }
}

Format-RunTable -Headers @('Run', 'Target', 'Baseline vs. candidate', 'RID', 'Import', 'First call', 'Second call') -Rows $summaryRows
''
"Footprint differences (candidate - baseline): on-disk, hosted path only, and .nupkg when measured."
Format-RunTable -Headers @('Target', 'On disk Δ', 'Hosted path Δ', 'Package Δ') -Rows $footprintRows -RightAligned @(1, 2, 3)
''
"$($files.Count) report(s) found."
