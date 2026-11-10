#Objective: PSProfiler integration: runs a script block under the pinned Profiler module and exports the hottest lines and functions.
#requires -Version 7.6
<#
.SYNOPSIS
PSProfiler integration: runs a script block under the pinned Profiler module and exports the hottest lines and functions.

.DESCRIPTION
Only the checksum-pinned Profiler 4.3.0 installed by scripts/Initialize-Profilers.ps1 is accepted. PSProfiler traces
PowerShell code only; native child processes appear as the PowerShell line that waits for them.
#>

Import-Module (Join-Path $PSScriptRoot 'RunEncoding.psm1')

$script:PinnedVersion = '4.3.0'

function Resolve-RunProfilerModule {
    <#
    .SYNOPSIS
    Finds the pinned Profiler manifest: explicit path, then QUIETCLI_PROFILER_MODULE, then the QuietCli2 cache.
    .PARAMETER Path
    Optional explicit manifest path.
    #>
    param([string]$Path)
    $candidates = @()
    if ($Path) { $candidates += $Path }
    elseif ($env:QUIETCLI_PROFILER_MODULE) { $candidates += $env:QUIETCLI_PROFILER_MODULE }
    else {
        $cache = Join-Path ([IO.Path]::GetTempPath()) 'QuietCli2'
        if (Test-Path -LiteralPath $cache) {
            $candidates += @(Get-ChildItem -LiteralPath $cache -Recurse -Filter Profiler.psd1 -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -match '[\\/]profilers[\\/]pinned[\\/]Profiler[\\/]' } | Sort-Object LastWriteTimeUtc -Descending | ForEach-Object FullName)
        }
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $manifest = Import-PowerShellDataFile -LiteralPath $candidate
        if ($manifest.ModuleVersion -ne $script:PinnedVersion) { throw "RunProfilerVersionMismatch: expected $script:PinnedVersion, found $($manifest.ModuleVersion)" }
        return [IO.Path]::GetFullPath($candidate)
    }
    throw 'RunProfilerNotFound: run scripts/Initialize-Profilers.ps1 -OutputDirectory <cache>, then pass -ProfilerModulePath <cache>/Profiler/Profiler.psd1'
}

function Convert-RunTraceRows {
    <#
    .SYNOPSIS
    Projects Profiler line or function rows to plain, serializable records with millisecond durations.
    .PARAMETER Rows
    Rows from Top50SelfDuration or Top50FunctionSelfDuration.
    #>
    param($Rows)
    foreach ($row in @($Rows)) {
        $text = [string]$row.Text
        [pscustomobject][ordered]@{
            File       = [string]$row.File
            Line       = [int]$row.Line
            Function   = [string]$row.Function
            Module     = [string]$row.Module
            HitCount   = [long]$row.HitCount
            SelfMs     = [Math]::Round(([TimeSpan]$row.SelfDuration).TotalMilliseconds, 3)
            DurationMs = [Math]::Round(([TimeSpan]$row.Duration).TotalMilliseconds, 3)
            SelfPercent = [double]$row.SelfPercent
            Text       = $(if ($text.Length -gt 200) { $text.Substring(0, 199) + '…' } else { $text })
        }
    }
}

function Invoke-RunProfiled {
    <#
    .SYNOPSIS
    Runs a script block under PSProfiler, writes the top-50 report as JSON and returns the JSON path.
    .PARAMETER ScriptBlock
    Code to profile; its pipeline output is discarded.
    .PARAMETER OutputDirectory
    Directory receiving `<Label>.profile.json`.
    .PARAMETER Label
    File-name-safe label of the profiled activity.
    .PARAMETER ProfilerModulePath
    Optional pinned Profiler manifest path.
    .PARAMETER Logger
    Optional logger (duck-typed: Info, Increment) receiving progress and counters.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]{1,80}\z')][string]$Label,
        [string]$ProfilerModulePath,
        $Logger
    )
    $manifest = Resolve-RunProfilerModule $ProfilerModulePath
    Import-Module $manifest -Force
    if ($Logger) { $Logger.Info("profiling '$Label' with Profiler $script:PinnedVersion"); $Logger.Increment('profiler.runs') }
    $output = Trace-Script -ScriptBlock $ScriptBlock -DisableWarning 6>$null
    $trace = @($output | Where-Object { $_.GetType().FullName -eq 'Profiler.Trace' }) | Select-Object -Last 1
    if ($null -eq $trace) { if ($Logger) { $Logger.Increment('profiler.failed') }; throw 'RunProfilerNoTrace' }
    $report = [ordered]@{
        Label          = $Label
        ProfilerVersion = $script:PinnedVersion
        PowerShell     = $PSVersionTable.PSVersion.ToString()
        TotalMs        = [Math]::Round(([TimeSpan]$trace.TotalDuration).TotalMilliseconds, 3)
        TopLinesBySelfDuration     = @(Convert-RunTraceRows $trace.Top50SelfDuration)
        TopFunctionsBySelfDuration = @(Convert-RunTraceRows $trace.Top50FunctionSelfDuration)
    }
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $path = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "$Label.profile.json"
    Write-RunTextFile -Path $path -Text ((ConvertTo-Json -InputObject $report -Depth 6) + "`n")
    if ($Logger) { $Logger.Increment('profiler.exported'); $Logger.Info("profile written to $path") }
    return $path
}

Export-ModuleMember -Function Resolve-RunProfilerModule, Invoke-RunProfiled
