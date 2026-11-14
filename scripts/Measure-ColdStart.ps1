#requires -Version 7.6
<#
.SYNOPSIS
Compares the cold-start cost of two QuietCli Core module builds with interleaved, fresh-process, paired runs.

.DESCRIPTION
Every sample starts a new `pwsh -NoProfile` child through `quiet`, using the -Output and -Complete callbacks to receive
the child's measurement line. The child imports the module under test, then times a first and a second `quiet` call
of a light native command. Baseline and candidate runs alternate (the order inside each pair is randomized with a
fixed seed) so machine drift hits both variants. A pair with a failed run is discarded whole (never retried).

The verdict uses a seeded percentile bootstrap of the median of paired differences (candidate minus baseline): the
difference is "faster" or "slower" only when the confidence interval excludes zero. Results go to standard output,
leveled logs and counters to standard error. With -ProfileImport, one extra child per variant imports the module
under the pinned PSProfiler and a top-50 JSON report is written (profiled runs are never part of the samples).

Also reports each variant's on-disk footprint: the total size, in bytes, of every file under its manifest's
directory, plus a narrower hosted-path size covering only the CLR/RID slot this process actually loads,
including a matching ReadyToRun child when selected, since the full footprint includes every bundled RID whether or not it is
used. This is a static build-artifact measurement, not a timed sample — it exists because a ReadyToRun build
trades a larger on-disk footprint (embedded native code) for a smaller first-call cost, and that tradeoff should be
visible next to the timing verdict, not just assumed. With -MeasurePackageSize, also packages each variant with
Compress-PSResource and reports the resulting .nupkg size, since compression does not always track the raw
on-disk difference.

.PARAMETER BaselineModule
Module manifest of the reference build.

.PARAMETER CandidateModule
Module manifest of the compared build, for example a temporary copy holding a ReadyToRun engine.

.PARAMETER BaselineLabel
Display name of the reference build.

.PARAMETER CandidateLabel
Display name of the compared build.

.PARAMETER Runs
Measured pairs.

.PARAMETER Warmup
Discarded pairs executed first.

.PARAMETER ChildCommand
Native command and arguments timed by the child, executable first.

.PARAMETER Seed
Seed of the pair-order generator and of the bootstrap.

.PARAMETER RunTimeoutSeconds
Deadline of one child run.

.PARAMETER MaxFailedPairs
Failed pairs tolerated before the campaign aborts.

.PARAMETER BootstrapResamples
Bootstrap resamples per phase.

.PARAMETER Confidence
Two-sided confidence level of the interval.

.PARAMETER ProfileImport
Also profiles one import per variant with PSProfiler.

.PARAMETER ProfilerModulePath
Pinned Profiler manifest; found automatically in the QuietCli2 cache when omitted.

.PARAMETER ProfileDirectory
Directory receiving the PSProfiler reports.

.PARAMETER MeasurePackageSize
Also packages each variant with Compress-PSResource and reports the resulting .nupkg size. Off by default: it
requires a real, publishable module manifest (name, version, GUID, author), which a minimal test fixture manifest
is not, and it is slower than the raw on-disk footprint that is always reported.

.PARAMETER OutputPath
Optional UTF-8 JSON file receiving parameters, environment, counters and every raw pair.

.PARAMETER LogLevel
Minimum level written to the console log.

.PARAMETER LogPath
Optional log file.

.EXAMPLE
./scripts/Invoke-RunProfile.ps1 coldstart-100 -Arguments @{ CandidateModule = 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh.psd1' }
#>
using module ./lib/RunLog.psm1
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BaselineModule = ([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')),
    [Parameter(Mandatory)][string]$CandidateModule,
    [ValidateNotNullOrEmpty()][string]$BaselineLabel = 'baseline',
    [ValidateNotNullOrEmpty()][string]$CandidateLabel = 'candidate',
    [ValidateRange(3, 100000)][int]$Runs = 30,
    [ValidateRange(0, 1000)][int]$Warmup = 2,
    [ValidateNotNullOrEmpty()][string[]]$ChildCommand = $(if ($IsWindows) { @('cmd', '/c', 'exit', '0') } else { @('true') }),
    [int]$Seed = 20261107,
    [ValidateRange(10, 3600)][int]$RunTimeoutSeconds = 120,
    [ValidateRange(0, 100000)][int]$MaxFailedPairs = 5,
    [ValidateRange(100, 1000000)][int]$BootstrapResamples = 2000,
    [ValidateRange(0.5, 0.9999)][double]$Confidence = 0.95,
    [switch]$ProfileImport,
    [string]$ProfilerModulePath,
    [string]$ProfileDirectory = ([IO.Path]::Combine(([IO.Path]::GetTempPath()),'QuietCli2-coldstart-profiles')),
    [switch]$MeasurePackageSize,
    [string]$OutputPath,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [string]$LogPath
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Measure-ColdStart.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptMeasureColdStart @PSBoundParameters
