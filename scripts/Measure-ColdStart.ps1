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
[CmdletBinding()]
param(
    [string]$BaselineModule = (Join-Path (Split-Path $PSScriptRoot -Parent) 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'),
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
    [string]$ProfileDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'QuietCli2-coldstart-profiles'),
    [string]$OutputPath,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [string]$LogPath
)
$ErrorActionPreference = 'Stop'
foreach ($module in 'RunFormat', 'RunStatistics', 'RunProfiler', 'RunEncoding', 'RunColdStart') { Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") }
$logger = New-RunLogger -Level $LogLevel -Component 'coldstart' -LogPath $LogPath
$clock = [Diagnostics.Stopwatch]::StartNew()

function Get-WorkerScript {
    <#
    .SYNOPSIS
    Builds the child script that imports one module and times its first and second quiet call.
    .PARAMETER Module
    Manifest path imported by the child.
    .PARAMETER Command
    Native command and arguments the child runs through quiet.
    #>
    param([string]$Module, [string[]]$Command)
    $commandJson = ConvertTo-RunSingleQuoted (ConvertTo-Json -InputObject @($Command) -Compress)
    return @"
`$ErrorActionPreference = 'Stop'
`$culture = [Globalization.CultureInfo]::InvariantCulture
`$watch = [Diagnostics.Stopwatch]::StartNew()
Import-Module $(ConvertTo-RunSingleQuoted $Module) -Force
`$import = `$watch.Elapsed.TotalMilliseconds
`$child = @(ConvertFrom-Json $commandJson)
`$watch.Restart()
`$first = quiet -AsObject -Output { param(`$event, `$runtime) } -Complete { param(`$runtime) } @child
`$firstMs = `$watch.Elapsed.TotalMilliseconds
`$watch.Restart()
`$second = quiet -AsObject -Output { param(`$event, `$runtime) } -Complete { param(`$runtime) } @child
`$secondMs = `$watch.Elapsed.TotalMilliseconds
if (`$first.Outcome -ne 'Success' -or `$second.Outcome -ne 'Success') { throw 'ChildCommandFailed' }
[string]::Format(`$culture, 'RESULT {0:F3} {1:F3} {2:F3}', `$import, `$firstMs, `$secondMs)
"@
}

function Get-ProfiledWorkerScript {
    <#
    .SYNOPSIS
    Builds the child script that imports one module under PSProfiler and prints the report path.
    .PARAMETER Module
    Manifest path imported under the profiler.
    .PARAMETER Label
    Report label.
    #>
    param([string]$Module, [string]$Label)
    $library = Join-Path $PSScriptRoot 'lib/RunProfiler.psm1'
    $importCode = ConvertTo-RunSingleQuoted "Import-Module $(ConvertTo-RunSingleQuoted $Module) -Force"
    return @"
`$ErrorActionPreference = 'Stop'
Import-Module $(ConvertTo-RunSingleQuoted $library)
`$path = Invoke-RunProfiled -ScriptBlock ([scriptblock]::Create($importCode)) -OutputDirectory $(ConvertTo-RunSingleQuoted $ProfileDirectory) -Label $(ConvertTo-RunSingleQuoted $Label) -ProfilerModulePath $(ConvertTo-RunSingleQuoted $ProfilerModulePath)
"PROFILE `$path"
"@
}

function Invoke-QuietChild {
    <#
    .SYNOPSIS
    Runs one fresh pwsh child through quiet and returns the whitespace-separated fields following its marker.
    .PARAMETER Worker
    Child script.
    .PARAMETER Marker
    Prefix of the output line carrying the result.
    #>
    param([string]$Worker, [string]$Marker)
    $logger.Increment('run.started')
    $result = quiet -AsObject -RecordDelimiter "`n" -TimeoutSeconds $RunTimeoutSeconds `
        -Data @{ Marker = $Marker; Line = $null; Fields = $null; Matches = 0 } `
        -Output {
            param($event, $runtime)
            if ($event.Stream -eq 'stdout' -and $event.Text.StartsWith($runtime.Data.Marker + ' ', [StringComparison]::Ordinal)) { $runtime.Data.Line = $event.Text.Trim(); $runtime.Data.Matches++ }
        } `
        -Complete {
            param($runtime)
            if ($null -ne $runtime.Data.Line) { $runtime.Data.Fields = @($runtime.Data.Line.Split(' ') | Select-Object -Skip 1) }
        } `
        pwsh -NoProfile -Command $Worker
    if ($result.Outcome -ne 'Success' -or $null -eq $result.Data.Fields -or $result.Data.Matches -ne 1) {
        $logger.Increment('run.failed')
        throw "ChildRunFailed: outcome=$($result.Outcome)"
    }
    $logger.Increment('run.succeeded')
    return $result.Data.Fields
}

function Invoke-ColdRun {
    <#
    .SYNOPSIS
    Measures one variant: returns import, first-call and second-call times in milliseconds.
    .PARAMETER Worker
    Child script produced by Get-WorkerScript.
    #>
    param([string]$Worker)
    $fields = Invoke-QuietChild -Worker $Worker -Marker 'RESULT'
    return ConvertFrom-RunColdSample $fields
}

foreach ($module in @($BaselineModule, $CandidateModule)) { if (-not (Test-Path -LiteralPath $module -PathType Leaf)) { throw "ModuleManifestNotFound: $module" } }
if (-not (Get-Command quiet -ErrorAction SilentlyContinue)) { Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') }

$variants = @(
    @{ Label = $BaselineLabel; Module = [IO.Path]::GetFullPath($BaselineModule) }
    @{ Label = $CandidateLabel; Module = [IO.Path]::GetFullPath($CandidateModule) }
)
foreach ($variant in $variants) { $variant.Worker = Get-WorkerScript $variant.Module $ChildCommand }
$logger.Info("baseline '$BaselineLabel' = $($variants[0].Module)")
$logger.Info("candidate '$CandidateLabel' = $($variants[1].Module)")
$logger.Info("plan: $Warmup warm-up + $Runs measured pairs, seed $Seed, child '$($ChildCommand -join ' ')'")

$random = [Random]::new($Seed)
$pairs = [Collections.Generic.List[object]]::new()
$total = $Warmup + $Runs
$reportEvery = [Math]::Max(1, [int][Math]::Floor($total / 20))
for ($pair = 1; $pair -le $total; $pair++) {
    $measured = $pair -gt $Warmup
    $order = if ($random.Next(2) -eq 0) { @(0, 1) } else { @(1, 0) }
    $logger.Trace("pair $pair order $($order -join ',')")
    try {
        $results = @{}
        foreach ($index in $order) { $results[$index] = Invoke-ColdRun $variants[$index].Worker }
        if ($measured) {
            $pairs.Add([pscustomobject]@{ Baseline = $results[0]; Candidate = $results[1] })
            $logger.Increment('pair.measured')
            $logger.Debug(('pair {0}: import {1:F0}/{2:F0}ms first {3:F0}/{4:F0}ms' -f $pair, $results[0].Import, $results[1].Import, $results[0].First, $results[1].First))
        }
        else { $logger.Increment('pair.warmup') }
    }
    catch {
        $logger.Increment('pair.discarded')
        $logger.Warn("pair $pair discarded: $($_.Exception.Message)")
        if ($logger.Get('pair.discarded') -gt $MaxFailedPairs) { $logger.Error("more than $MaxFailedPairs failed pairs, aborting"); throw }
    }
    if ($pair % $reportEvery -eq 0 -or $pair -eq $total) {
        $elapsedMs = $clock.Elapsed.TotalMilliseconds
        $logger.Info("pair $pair/$total, elapsed $(Format-RunDuration $elapsedMs), remaining about $(Format-RunDuration ($elapsedMs / $pair * ($total - $pair)))")
    }
}
if ($pairs.Count -lt 3) { throw "TooFewMeasuredPairs: $($pairs.Count)" }

$phases = [ordered]@{ 'Import' = 'Import'; 'First call' = 'First'; 'Second call' = 'Second' }
$distributionRows = [Collections.Generic.List[object]]::new()
$pairedRows = [Collections.Generic.List[object]]::new()
$summary = [ordered]@{}
foreach ($phase in $phases.GetEnumerator()) {
    $base = [double[]]@($pairs | ForEach-Object { $_.Baseline.($phase.Value) })
    $cand = [double[]]@($pairs | ForEach-Object { $_.Candidate.($phase.Value) })
    $differences = [double[]]::new($base.Length)
    for ($i = 0; $i -lt $base.Length; $i++) { $differences[$i] = $cand[$i] - $base[$i] }
    $baseStats = Get-RunSummary $base
    $candStats = Get-RunSummary $cand
    $interval = $logger.Time("bootstrap.$($phase.Key)", { Get-PairedBootstrapInterval -Differences $differences -Resamples $BootstrapResamples -Seed $Seed -Confidence $Confidence })
    $logger.Add('bootstrap.resamples', $BootstrapResamples)
    $verdict = Get-RunVerdict $interval
    $logger.Increment("verdict.$verdict")
    $logger.Debug("$($phase.Key): median difference $(Format-RunDuration $interval.Median), CI [$(Format-RunDuration $interval.Low), $(Format-RunDuration $interval.High)] -> $verdict")
    foreach ($row in @(@($BaselineLabel, $baseStats), @($CandidateLabel, $candStats))) {
        $distributionRows.Add(@($phase.Key, $row[0], $row[1].N, (Format-RunDuration $row[1].Median), (Format-RunDuration $row[1].Q1), (Format-RunDuration $row[1].Q3), (Format-RunDuration $row[1].Min)))
    }
    $pairedRows.Add(@($phase.Key, $interval.Pairs, (Format-RunDuration $interval.Median), (Format-RunDuration $interval.Low), (Format-RunDuration $interval.High), $verdict))
    $summary[$phase.Key] = [ordered]@{ Baseline = $baseStats; Candidate = $candStats; Difference = $interval; Verdict = $verdict }
}

$profileReports = @()
if ($ProfileImport) {
    foreach ($variant in $variants) {
        $logger.Info("profiling import of '$($variant.Label)'")
        $fields = Invoke-QuietChild -Worker (Get-ProfiledWorkerScript $variant.Module "import-$($variant.Label)") -Marker 'PROFILE'
        $profileReports += ($fields -join ' ')
        $logger.Increment('profile.exported')
    }
}

''
"Project: QuietCli.Core.PoSh | Task: cold-start A/B ($($pairs.Count) measured pairs, $Warmup warm-up, seed $Seed)"
"Workspace: $((Split-Path $PSScriptRoot -Parent))"
''
Format-RunTable -Headers @('Phase', 'Variant', 'N', 'Duration (median)', 'Duration (Q1)', 'Duration (Q3)', 'Duration (min)') -Rows $distributionRows -RightAligned @(2, 3, 4, 5, 6)
''
"Paired difference (candidate minus baseline), $($Confidence * 100)% bootstrap interval of the median, $BootstrapResamples resamples"
Format-RunTable -Headers @('Phase', 'Pairs', 'Duration (median)', 'Duration (CI low)', 'Duration (CI high)', 'Verdict') -Rows $pairedRows -RightAligned @(1, 2, 3, 4)
foreach ($report in $profileReports) { "PSProfiler report: $report" }
"Total Duration: $(Format-RunDuration $clock.Elapsed.TotalMilliseconds)"

if ($OutputPath) {
    $document = [ordered]@{
        Parameters  = [ordered]@{ BaselineModule = $variants[0].Module; CandidateModule = $variants[1].Module; BaselineLabel = $BaselineLabel; CandidateLabel = $CandidateLabel; Runs = $Runs; Warmup = $Warmup; ChildCommand = $ChildCommand; Seed = $Seed; BootstrapResamples = $BootstrapResamples; Confidence = $Confidence }
        Environment = [ordered]@{ PowerShell = $PSVersionTable.PSVersion.ToString(); Os = [Runtime.InteropServices.RuntimeInformation]::OSDescription; Clr = [Environment]::Version.ToString() }
        Counters    = $logger.Snapshot()
        Summary     = $summary
        Pairs       = $pairs
        Profiles    = $profileReports
    }
    Write-RunTextFile -Path ([IO.Path]::GetFullPath($OutputPath)) -Text ((ConvertTo-Json -InputObject $document -Depth 8) + "`n")
    $logger.Info("samples written to $([IO.Path]::GetFullPath($OutputPath))")
}
$logger.Add('total.ms', [long]$clock.ElapsedMilliseconds)
foreach ($line in (Format-RunCounters $logger.Snapshot())) { $logger.Info($line) }
