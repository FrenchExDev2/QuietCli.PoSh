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
    [string]$ArtifactsDirectory = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'artifacts/coldstart')),
    [string]$ContainersDirectory = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'artifacts/coldstart-containers')),
    [ValidateNotNullOrEmpty()][string]$Pattern = 'ab-*.json'
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Show-ColdStartMatrixReport.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptShowColdStartMatrixReport @PSBoundParameters
