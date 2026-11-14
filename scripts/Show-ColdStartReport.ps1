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
    [string]$ArtifactsDirectory = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'artifacts/coldstart')),
    [ValidateNotNullOrEmpty()][string]$Pattern = 'ab-*.json'
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Show-ColdStartReport.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptShowColdStartReport @PSBoundParameters
