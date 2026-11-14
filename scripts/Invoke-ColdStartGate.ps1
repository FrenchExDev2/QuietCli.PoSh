#requires -Version 7.6
<#
.SYNOPSIS
Enforces a fresh A/A noise-floor control before running a cold-start A/B comparison, and persists both.

.DESCRIPTION
Measure-ColdStart.ps1's verdicts are only trustworthy once this machine's own measurement noise is known. This
script keeps one cached A/A control result per machine and run profile under -ArtifactsDirectory (git-ignored),
reuses it while it is fresh and still all-inconclusive, and otherwise reruns the A/A control before the A/B.
A stored or freshly measured A/A control whose phases are not all 'inconclusive' aborts the A/B outright: the
noise floor cannot be trusted, so a "faster"/"slower" verdict from the same machine would not be trustworthy either.

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
    [string]$BaselineModule = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')),
    [ValidateNotNullOrEmpty()][string]$ProfileName = 'coldstart-100',
    [string]$ArtifactsDirectory = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'artifacts/coldstart')),
    [ValidateRange(1, 365)][int]$MaxAgeDays = 14,
    [switch]$Force,
    [hashtable]$Arguments = @{},
    [switch]$MeasurePackageSize,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [string]$LogPath
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Invoke-ColdStartGate.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptInvokeColdStartGate @PSBoundParameters
