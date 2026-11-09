#requires -Version 7.6
<#
.SYNOPSIS
Runs a named run profile, or lists the available ones.

.DESCRIPTION
Loads `<Name>.profile.ps1` (data only), overlays the caller arguments on its parameters, validates them against the
target script, forwards LogLevel/LogPath when the target accepts them, then runs the target. With -Profiler the target
runs under the pinned PSProfiler and a top-50 JSON report is written. Counters and a leveled log describe every step.

.PARAMETER Name
Profile to run.

.PARAMETER List
Lists the profiles of the profile directory instead of running one.

.PARAMETER Arguments
Overrides applied over the profile parameters, for example @{ CandidateModule = 'C:\x\Core.psd1' }.

.PARAMETER ProfilesDirectory
Profile directory; defaults to scripts/RunProfiles.

.PARAMETER ScriptDirectory
Directory holding target scripts; defaults to scripts/.

.PARAMETER LogLevel
Minimum level written to the console and forwarded to the target.

.PARAMETER LogPath
Optional log file, forwarded to the target when it accepts LogPath.

.PARAMETER Profiler
Runs the target under PSProfiler. The target's pipeline output is forwarded after the profile ends.

.PARAMETER ProfilerModulePath
Pinned Profiler manifest; found automatically in the QuietCli2 cache when omitted.

.PARAMETER ProfilerOutputDirectory
Directory receiving the profile JSON; defaults to a timestamped folder under the temp directory.

.EXAMPLE
./scripts/Invoke-RunProfile.ps1 coldstart-100 -Arguments @{ CandidateModule = 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh.psd1' }
#>
using module ./lib/RunLog.psm1
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Run')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Run')][string]$Name,
    [Parameter(Mandatory, ParameterSetName = 'List')][switch]$List,
    [Parameter(ParameterSetName = 'Run')][hashtable]$Arguments = @{},
    [string]$ProfilesDirectory,
    [string]$ScriptDirectory,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [string]$LogPath,
    [Parameter(ParameterSetName = 'Run')][switch]$Profiler,
    [Parameter(ParameterSetName = 'Run')][string]$ProfilerModulePath,
    [Parameter(ParameterSetName = 'Run')][string]$ProfilerOutputDirectory
)
$ErrorActionPreference = 'Stop'
foreach ($module in 'RunFormat', 'RunProfileStore', 'RunProfiler') { Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") -Force }

$logger = New-RunLogger -Level $LogLevel -Component 'run-profile' -LogPath $LogPath
$clock = [Diagnostics.Stopwatch]::StartNew()
try {
    if ($PSCmdlet.ParameterSetName -eq 'List') {
        $rows = [Collections.Generic.List[object]]::new()
        foreach ($profileName in (Get-RunProfileNames $ProfilesDirectory)) {
            $logger.Increment('profile.listed')
            try {
                $entry = $logger.Time('profile.load', { Read-RunProfile -Path (Get-RunProfilePath -Name $profileName -Directory $ProfilesDirectory) })
                $rows.Add(@($entry.Name, $entry.Script, [string]$entry.Parameters.get_Count(), [string]$entry.Description))
            }
            catch { $logger.Warn("skipping '$profileName': $($_.Exception.Message)"); $logger.Increment('profile.invalid') }
        }
        Format-RunTable -Headers @('Profile', 'Script', 'Params', 'Description') -Rows $rows -RightAligned @(2)
        return
    }

    $logger.Increment('profile.run.requested')
    $path = Get-RunProfilePath -Name $Name -Directory $ProfilesDirectory
    $logger.Debug("loading $path")
    $profile = $logger.Time('profile.load', { Read-RunProfile -Path $path })
    $target = Resolve-RunProfileTarget -Profile $profile -ScriptDirectory $ScriptDirectory
    $parameters = Merge-RunProfileArguments -Profile $profile -Arguments $Arguments
    $logger.Add('profile.parameters.fromProfile', $profile.Parameters.get_Count())
    $logger.Add('profile.parameters.overridden', @($Arguments.Keys | Where-Object { $profile.Parameters.ContainsKey($_) }).Count)
    $declared = (Get-Command -Name $target -CommandType ExternalScript).Parameters
    foreach ($forwarded in @(@{ Key = 'LogLevel'; Value = $LogLevel }, @{ Key = 'LogPath'; Value = $LogPath })) {
        if ($declared.ContainsKey($forwarded.Key) -and -not $parameters.ContainsKey($forwarded.Key) -and $forwarded.Value) {
            $parameters[$forwarded.Key] = $forwarded.Value
            $logger.Increment('profile.parameters.forwarded')
        }
    }
    Assert-RunTargetParameters -TargetPath $target -Parameters $parameters
    $logger.Info("profile '$Name' -> $($profile.Script) with: " + (($parameters.Keys | Sort-Object -CaseSensitive | ForEach-Object { "$_=$(ConvertTo-RunProfileLiteral $parameters[$_])" }) -join ' '))
    if (-not $PSCmdlet.ShouldProcess($target, "Run profile '$Name'")) { $logger.Info('skipped by ShouldProcess'); $logger.Increment('profile.run.skipped'); return }

    $logger.Increment('profile.run.started')
    if ($Profiler) {
        if (-not $ProfilerOutputDirectory) { $ProfilerOutputDirectory = Join-Path ([IO.Path]::GetTempPath()) ("QuietCli2-run-profiles/$Name-" + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')) }
        $captured = [Collections.Generic.List[object]]::new()
        $report = Invoke-RunProfiled -ScriptBlock { foreach ($item in (& $target @parameters)) { $captured.Add($item) } } `
            -OutputDirectory $ProfilerOutputDirectory -Label $Name -ProfilerModulePath $ProfilerModulePath -Logger $logger
        $captured
        $logger.Info("PSProfiler report: $report")
    }
    else { & $target @parameters }
    $logger.Increment('profile.run.succeeded')
    $logger.Info("profile '$Name' finished in $(Format-RunDuration $clock.Elapsed.TotalMilliseconds)")
}
catch {
    $logger.Increment('profile.run.failed')
    $logger.Error($_.Exception.Message)
    throw
}
finally {
    $logger.Add('profile.total.ms', [long]$clock.ElapsedMilliseconds)
    foreach ($line in (Format-RunCounters $logger.Snapshot())) { $logger.Info($line) }
}
