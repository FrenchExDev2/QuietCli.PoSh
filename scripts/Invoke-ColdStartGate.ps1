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
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CandidateModule,
    [ValidateNotNullOrEmpty()][string]$CandidateLabel = 'candidate',
    [string]$BaselineModule = (Join-Path (Split-Path $PSScriptRoot -Parent) 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'),
    [ValidateNotNullOrEmpty()][string]$ProfileName = 'coldstart-100',
    [string]$ArtifactsDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'artifacts/coldstart'),
    [ValidateRange(1, 365)][int]$MaxAgeDays = 14,
    [switch]$Force,
    [hashtable]$Arguments = @{},
    [switch]$MeasurePackageSize,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [string]$LogPath
)
$ErrorActionPreference = 'Stop'
foreach ($module in 'RunEncoding', 'RunFormat') { Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") -Force }
$logger = New-RunLogger -Level $LogLevel -Component 'coldstart-gate' -LogPath $LogPath
$runProfileScript = Join-Path $PSScriptRoot 'Invoke-RunProfile.ps1'

function Get-ColdStartMachineKey {
    <#
    .SYNOPSIS
    Builds a filesystem-safe cache key identifying this machine and run profile.
    .PARAMETER ProfileName
    Run profile the cache entry belongs to.
    #>
    param([Parameter(Mandatory)][string]$ProfileName)
    $safeMachine = [Environment]::MachineName.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
    return "aa-$ProfileName-$safeMachine"
}

function Get-ColdStartAaVerdicts {
    <#
    .SYNOPSIS
    Reads an A/A control's JSON output and returns its phase verdicts.
    .PARAMETER Path
    JSON file written by Measure-ColdStart.ps1's -OutputPath.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $document = Read-RunTextFile -Path $Path | ConvertFrom-Json
    return @($document.Summary.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Phase = $_.Name; Verdict = $_.Value.Verdict } })
}

function Test-ColdStartAaCacheFresh {
    <#
    .SYNOPSIS
    Decides whether a cached A/A control can be reused instead of remeasured.
    .PARAMETER Path
    Candidate cache file.
    .PARAMETER MaxAgeDays
    Maximum age tolerated before the cache is considered stale.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int]$MaxAgeDays)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $age = [DateTime]::UtcNow - (Get-Item -LiteralPath $Path).LastWriteTimeUtc
    if ($age.TotalDays -gt $MaxAgeDays) { return $false }
    $verdicts = @(Get-ColdStartAaVerdicts -Path $Path)
    return @($verdicts | Where-Object Verdict -NE 'inconclusive').Count -eq 0
}

function Get-ColdStartAaDisplayVerdict {
    <#
    .SYNOPSIS
    Maps a raw phase verdict to what it means specifically for an A/A control.
    .DESCRIPTION
    Both sides of an A/A control are the same binary, so there is no real difference to detect by construction.
    'inconclusive' is therefore not an ambiguous non-result here the way it is for an A/B comparison: it is the
    proof that the protocol did not manufacture a phantom difference, i.e. the noise floor check concluded cleanly.
    Displaying it as 'conclusive' in the gate's own output avoids reading a passing noise-floor check as a failed
    measurement. 'faster'/'slower'/'too-few-pairs' are real problem states and are shown unchanged.
    .PARAMETER Verdict
    Raw verdict from Get-RunVerdict (stored as-is in the A/A control's JSON; only this display label changes).
    #>
    param([Parameter(Mandatory)][string]$Verdict)
    if ($Verdict -eq 'inconclusive') { return 'conclusive' }
    return $Verdict
}

function Assert-ColdStartNoiseFloor {
    <#
    .SYNOPSIS
    Throws with the offending phases when an A/A control is not all-inconclusive.
    .PARAMETER Path
    A/A control JSON to validate.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $verdicts = @(Get-ColdStartAaVerdicts -Path $Path)
    $bad = @($verdicts | Where-Object Verdict -NE 'inconclusive')
    if ($bad.Count -gt 0) {
        $phases = ($bad | ForEach-Object { "$($_.Phase)=$($_.Verdict)" }) -join ', '
        throw "ColdStartNoiseFloorUnstable: A/A control is not conclusive on this machine ($phases); fix noise before trusting any A/B result from it. See $Path"
    }
}

[void][IO.Directory]::CreateDirectory($ArtifactsDirectory)
$baselineFull = [IO.Path]::GetFullPath($BaselineModule)
$aaPath = Join-Path $ArtifactsDirectory ((Get-ColdStartMachineKey -ProfileName $ProfileName) + '.json')
if ($MeasurePackageSize) { $Arguments = (@{} + $Arguments); $Arguments['MeasurePackageSize'] = $true }

if ($Force -or -not (Test-ColdStartAaCacheFresh -Path $aaPath -MaxAgeDays $MaxAgeDays)) {
    $logger.Info("A/A control missing, stale or Force requested; measuring into $aaPath")
    $aaArguments = @{} + $Arguments
    $aaArguments['CandidateModule'] = $baselineFull
    $aaArguments['CandidateLabel'] = 'aa-control'
    $aaArguments['OutputPath'] = $aaPath
    & $runProfileScript $ProfileName -Arguments $aaArguments -LogLevel $LogLevel -LogPath $LogPath | Out-Host
    $logger.Increment('aa.measured')
}
else {
    $logger.Info("reusing fresh A/A control: $aaPath")
    $logger.Increment('aa.cached')
}

Assert-ColdStartNoiseFloor -Path $aaPath
$aaDisplay = (@(Get-ColdStartAaVerdicts -Path $aaPath) | ForEach-Object { "$($_.Phase)=$(Get-ColdStartAaDisplayVerdict $_.Verdict)" }) -join ', '
$logger.Info("A/A control is conclusive on every phase ($aaDisplay); noise floor validated, proceeding to A/B")

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$safeLabel = $CandidateLabel -replace '[^a-zA-Z0-9-]', '-'
$abPath = Join-Path $ArtifactsDirectory "ab-$ProfileName-$safeLabel-$stamp.json"
$abArguments = @{} + $Arguments
$abArguments['CandidateModule'] = $CandidateModule
$abArguments['CandidateLabel'] = $CandidateLabel
$abArguments['BaselineModule'] = $baselineFull
$abArguments['OutputPath'] = $abPath
& $runProfileScript $ProfileName -Arguments $abArguments -LogLevel $LogLevel -LogPath $LogPath | Out-Host
$logger.Info("A/B result written to $abPath")
foreach ($line in (Format-RunCounters $logger.Snapshot())) { $logger.Info($line) }
