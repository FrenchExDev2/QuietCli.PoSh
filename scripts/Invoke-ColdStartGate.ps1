#requires -Version 7.6
<#
.SYNOPSIS
Runs a cold-start A/B comparison with an optional A/A control.

.DESCRIPTION
The default local mode validates a cached or newly measured A/A control before running A/B. The control
must give an 'inconclusive' verdict for every phase. Use -SkipAaControl to run the paired A/B directly.

.PARAMETER CandidateModule
Module manifest of the compared build, forwarded to the A/B run's CandidateModule.

.PARAMETER CandidateLabel
Display name of the compared build, forwarded to the A/B run's CandidateLabel.

.PARAMETER BaselineModule
Module manifest of the reference build, used as both sides of the A/A control and as the A/B baseline.

.PARAMETER ProfileName
Run profile executed for both the A/A control and the A/B comparison (see scripts/RunProfiles).

.PARAMETER ArtifactsDirectory
Directory receiving the per-machine A/A cache and every A/B result; created if missing. Must stay git-ignored.

.PARAMETER MaxAgeDays
Cached A/A control older than this is treated as stale and remeasured.

.PARAMETER Force
Remeasures the A/A control even when a fresh, clean cache entry exists.

.PARAMETER SkipAaControl
Runs the A/B without measuring or reading the A/A control.

.PARAMETER Arguments
Extra overrides forwarded to both the A/A and the A/B profile run, for example @{ Runs = 1000 }. Never set
CandidateModule, CandidateLabel or OutputPath here; the gate controls those.

.PARAMETER MeasurePackageSize
Forwards MeasurePackageSize=$true to both runs via -Arguments, without requiring a hashtable literal. Useful from
a plain command line (for example inside a container's pwsh -File invocation), where -Arguments @{ ... } cannot
be passed as a literal argument.

.PARAMETER LogLevel
Minimum level written to the console log.

.PARAMETER LogPath
Optional log file.

.EXAMPLE
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh\FrenchExDev2.QuietCli.Core.PoSh.psd1' -CandidateLabel readytorun
#>
using module ./lib/RunLog.psm1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CandidateModule,
    [ValidateNotNullOrEmpty()][string]$CandidateLabel = 'candidate',
    [string]$BaselineModule = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')),
    [ValidateNotNullOrEmpty()][string]$ProfileName = 'coldstart-100',
    [string]$ArtifactsDirectory = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'artifacts/coldstart')),
    [ValidateRange(1, 365)][int]$MaxAgeDays = 14,
    [switch]$Force,
    [switch]$SkipAaControl,
    [hashtable]$Arguments = @{},
    [switch]$MeasurePackageSize,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [string]$LogPath
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Invoke-ColdStartGate.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptInvokeColdStartGate @PSBoundParameters
