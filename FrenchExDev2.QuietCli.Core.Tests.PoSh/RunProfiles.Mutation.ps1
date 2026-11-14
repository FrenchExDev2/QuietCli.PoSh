#requires -Version 7.6
<#
.SYNOPSIS
Mutation campaign for the run-profile tooling: proves that the RunProfiles tests detect meaningful behavior changes.

.DESCRIPTION
For every mutant, a fresh sandbox copy of scripts/ (lib modules and the two profile scripts) and of the test suite is
created, exactly one source substitution is applied, and the suite runs in an owned child process through the engine-independent Ci.Process helper
(only SUMMARY counters are retained). Outcomes:
Killed (at least one case failed), Survived (all cases passed: a missing assertion or an equivalent mutant to justify),
Crashed (no summary: the mutant does not parse or the suite aborted; detected but not a valid behavioral mutant),
Timeout, Invalid (the substitution target does not occur exactly once). The baseline must pass first.
The exit code counts Survived, Crashed, Timeout and Invalid mutants; only Killed is accepted.

.PARAMETER Seed
Seed forwarded to the suite.

.PARAMETER Iterations
Generated inputs per property case during the campaign.

.PARAMETER MutantName
Restricts the campaign to the named mutants.

.PARAMETER MutantTimeoutSeconds
Deadline of one suite run.
.PARAMETER MaxConcurrency
Maximum isolated mutation processes. The green baseline always finishes before any mutant starts.
.PARAMETER ShardIndex
Zero-based independent shard; the default executes the complete catalogue locally.
.PARAMETER ShardCount
Number of nonempty shards. Every shard runs its own baseline and remains partial evidence.

.PARAMETER OutputPath
Optional UTF-8 JSON file receiving every outcome.

.PARAMETER LogLevel
Minimum level written to the console log.

.EXAMPLE
pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.ps1 -OutputPath ./mutation.json
#>
using module ../scripts/lib/RunLog.psm1
[CmdletBinding()]
param(
    [int]$Seed = 61207,
    [ValidateRange(10, 100000)][int]$Iterations = 120,
    [string[]]$MutantName = @(),
    [ValidateRange(30, 3600)][int]$MutantTimeoutSeconds = 300,
    [ValidateRange(1,32)][int]$MaxConcurrency = 2,
    [ValidateRange(0,31)][int]$ShardIndex = 0,
    [ValidateRange(1,32)][int]$ShardCount = 1,
    [string]$OutputPath,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [ValidateSet('utf-8', 'oem')][string]$ConsoleEncoding = 'utf-8'
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scripts = Join-Path $workspace 'scripts'
Import-Module ([IO.Path]::Combine($scripts,'lib/Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
foreach ($module in 'RunEncoding', 'RunFormat') { Import-Module (Join-Path $scripts "lib/$module.psm1") -Force }
[void](Set-RunConsoleEncoding -Name $ConsoleEncoding)
$logger = New-RunLogger -Level $LogLevel -Component 'mutation'
$clock = [Diagnostics.Stopwatch]::StartNew()
$utf8 = [Text.UTF8Encoding]::new($false)

# Each mutant substitutes exactly one occurrence of From by To inside File (relative to scripts/).
$catalogue = @((Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'RunProfiles.Mutation.Catalogue.psd1')).Mutants)
$totalCatalogue=$catalogue.Count
Import-Module (Join-Path $scripts 'lib/MutationShards.psm1') -ErrorAction Stop
$sourceSHA256=Get-QuietRunProfileMutationIdentity $workspace
if(!$MutantName.Count -and $env:QUIETCLI_TEST_CASE){$MutantName=@($catalogue|Where-Object Name -Like $env:QUIETCLI_TEST_CASE|ForEach-Object Name)}
if($env:QUIETCLI_TEST_CASE -and !$MutantName.Count){throw 'MutationFilterMatchedNoCases'}
if ($MutantName.Count -gt 0) { $catalogue = @($catalogue | Where-Object { $_.Name -in $MutantName }) }
if ($catalogue.Count -eq 0) { throw 'MutationCatalogueEmpty' }
if($ShardCount -gt 1 -and $MutantName.Count){throw 'MutationShardsCannotUseCaseFilters'}
$catalogue=@(Get-QuietMutationShard -Catalogue $catalogue -Index $ShardIndex -Count $ShardCount)
$logger.Info("catalogue: $($catalogue.Count) mutants, $Iterations iterations per property case, seed $Seed")


function New-MutationSandbox {
    <#
    .SYNOPSIS
    Copies the scripts under test and the test suite into a fresh temporary tree and returns its root.
    #>
    $root = Join-Path ([IO.Path]::GetTempPath()) ('RunProfilesMutation-' + [Guid]::NewGuid().ToString('N'))
    $tests = Join-Path $root 'FrenchExDev2.QuietCli.Core.Tests.PoSh'
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'scripts'))
    [void][IO.Directory]::CreateDirectory($tests)
    Copy-Item -LiteralPath (Join-Path $scripts 'lib') -Destination (Join-Path $root 'scripts/lib') -Recurse
    foreach ($name in 'New-RunProfile.ps1', 'Invoke-RunProfile.ps1', 'Measure-ColdStart.ps1', 'Initialize-Profilers.ps1') { Copy-Item -LiteralPath (Join-Path $scripts $name) -Destination (Join-Path $root "scripts/$name") }
    foreach ($name in 'RunProfiles.Tests.ps1', 'RunProfiles.Benchmark.Tests.ps1', 'RunProfiles.Profiler.Tests.ps1') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $tests }
    return $root
}

function Invoke-SandboxSuite {
    <#
    .SYNOPSIS
    Runs the baseline through the engine-independent process helper and returns bounded counters.
    .PARAMETER Root
    Owned sandbox containing the test suite.
    #>
    param([string]$Root)
    $logger.Increment('suite.started')
    $capture=@{Summary=$null;Diagnostics=[Collections.Generic.Queue[string]]::new()}
    $result=Invoke-CiProcess -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -ArgumentList @('-File',(Join-Path $Root 'FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1'),'-Seed',"$Seed",'-Iterations',"$Iterations",'-ConsoleEncoding',$ConsoleEncoding,'-Skip','profiler:,console:,coldstart-live:,tool-cache-live:') -WorkingDirectory $Root -TimeoutSeconds $MutantTimeoutSeconds -State $capture -OnOutput {
        param($record,$state)
        if($record.Stream -eq 'stdout' -and $record.Text -match '^SUMMARY Passed=(\d+) Failed=(\d+) Skipped=(\d+)$'){
            $state.Summary=[pscustomobject]@{Passed=[int]$Matches[1];Failed=[int]$Matches[2];Skipped=[int]$Matches[3]}
        }
        if($record.Stream -eq 'stderr' -or $record.Text -match 'FAILED:'){
            if($state.Diagnostics.Count -ge 8){[void]$state.Diagnostics.Dequeue()}
            $state.Diagnostics.Enqueue($record.Text.Substring(0,[Math]::Min(1000,$record.Text.Length)))
        }
    }
    [pscustomobject]@{Outcome=$result.Outcome;Summary=$capture.Summary;Diagnostics=$capture.Diagnostics.ToArray();ErrorCode=$(if($result.Outcome -ne 'Success'){'SuiteProcessFailed'}else{''})}
}

function Remove-MutationSandbox {
    <#
    .SYNOPSIS
    Deletes a sandbox tree, ignoring failures.
    .PARAMETER Root
    Sandbox root.
    #>
    param([string]$Root)
    $resolved = [IO.Path]::GetFullPath($Root)
    $temporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($temporary, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'RunProfilesMutation-*') { throw 'MutationSandboxPathRejected' }
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}

$baselineRoot = New-MutationSandbox
try {
    $baseline = $logger.Time('baseline', { Invoke-SandboxSuite $baselineRoot })
    if ($baseline.Outcome -ne 'Success' -or $null -eq $baseline.Summary -or $baseline.Summary.Failed -ne 0) {
        $hint = if ($baseline.ErrorCode -eq 'DecodeOrFramingFailed') { " (the suite output is not valid UTF-8 for quiet: console encoding '$ConsoleEncoding' does not match its strict UTF-8 decoding; use -ConsoleEncoding utf-8)" } else { '' }
        $logger.Error("baseline is not green: outcome $($baseline.Outcome), error '$($baseline.ErrorCode)'$hint")
        foreach($diagnostic in $baseline.Diagnostics){$logger.Error('baseline: '+$diagnostic)}
        throw 'MutationBaselineFailed'
    }
    $logger.Info("baseline green: $($baseline.Summary.Passed) cases passed, $($baseline.Summary.Skipped) skipped")
}
finally { Remove-MutationSandbox $baselineRoot }

$results = [Collections.Generic.List[object]]::new()
Import-Module (Join-Path $workspace 'scripts/lib/Ci.Process.psm1') -DisableNameChecking -ErrorAction Stop
$workerPath=Join-Path $PSScriptRoot 'RunProfiles.MutationWorker.ps1'
$runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$active=[Collections.Generic.List[object]]::new()
$completed=@{};$next=0;$peak=0
try {
    while($next -lt $catalogue.Count -or $active.Count){
        while($next -lt $catalogue.Count -and $active.Count -lt $MaxConcurrency){
            $mutant=$catalogue[$next];$ordinal=$next;$next++
            $root=New-MutationSandbox
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $path=Join-Path $root ("scripts/"+$mutant.File)
            $text=Read-RunTextFile -Path $path
            $occurrences=[regex]::Matches($text,[regex]::Escape($mutant.From)).Count
            if($occurrences -ne 1){
                $completed[$ordinal]=[pscustomobject]@{Name=$mutant.Name;File=$mutant.File;Outcome='Invalid';Detail=("target occurs $occurrences times");DurationMs=[long]$watch.ElapsedMilliseconds;Sandbox=$root}
                continue
            }
            Write-RunTextFile -Path $path -Text $text.Replace($mutant.From,$mutant.To)
            $process=Start-CiProcess -FilePath $runner -WorkingDirectory $workspace -ArgumentList @('-File',$workerPath,'-WorkspaceRoot',$workspace,'-Sandbox',$root,'-Seed',"$Seed",'-Iterations',"$Iterations",'-TimeoutSeconds',"$MutantTimeoutSeconds",'-ConsoleEncoding',$ConsoleEncoding)
            $active.Add([pscustomobject]@{Process=$process;Root=$root;Mutant=$mutant;Ordinal=$ordinal;Clock=$watch})
            $peak=[Math]::Max($peak,$active.Count)
        }
        foreach($job in @($active.ToArray())){
            if(!$job.Process.HasExited -and $job.Clock.Elapsed.TotalSeconds -le $MutantTimeoutSeconds+30){continue}
            $outcome='Crashed';$detail='worker exited without a valid summary'
            if(!$job.Process.HasExited){$job.Process.Kill($true);$job.Process.WaitForExit();$outcome='Timeout';$detail="no result within $MutantTimeoutSeconds s"}
            else{
                $receipt=Join-Path $job.Root 'mutation-worker-result.json'
                if([IO.File]::Exists($receipt)){
                    try{
                        $run=Read-RunTextFile -Path $receipt|ConvertFrom-Json
                        if($run.Sandbox -cne $job.Root -or $run.ProcessId -ne $job.Process.Id){throw 'MutationWorkerIdentityMismatch'}
                        if($run.Outcome -eq 'Timeout'){$outcome='Timeout';$detail="no result within $MutantTimeoutSeconds s"}
                        elseif($null -ne $run.Summary -and $run.Summary.Passed -ge 0 -and $run.Summary.Failed -ge 0){
                            if($run.Summary.Failed -gt 0){$outcome='Killed';$detail="$($run.Summary.Failed) failing case(s)"}
                            elseif($run.Outcome -eq 'Success' -and $job.Process.ExitCode -eq 0){$outcome='Survived';$detail='all cases passed'}
                        }
                    }catch{$detail=$_.Exception.Message}
                }
            }
            $completed[$job.Ordinal]=[pscustomobject]@{Name=$job.Mutant.Name;File=$job.Mutant.File;Outcome=$outcome;Detail=$detail;DurationMs=[long]$job.Clock.ElapsedMilliseconds;Sandbox=$(if($outcome -ne 'Killed'){$job.Root}else{$null})}
            if($outcome -eq 'Killed'){Remove-MutationSandbox $job.Root}
            $job.Process.Dispose();$null=$active.Remove($job)
        }
        # Persisted parent progress is deterministic; workers never share a logger, engine or sandbox.
        while($completed.ContainsKey($results.Count)){
            $row=$completed[$results.Count];$completed.Remove($results.Count);$results.Add($row)
            $logger.Increment("mutant.$($row.Outcome.ToLowerInvariant())")
            $logger.Info(('[{0}/{1}] {2,-30} {3,-9} {4} ({5})' -f $results.Count,$catalogue.Count,$row.Name,$row.Outcome,$row.Detail,(Format-RunDuration $row.DurationMs)))
        }
        if($active.Count){[void][Threading.Tasks.Task]::Delay(100).GetAwaiter().GetResult()}
    }
}finally{
    foreach($job in $active){if(!$job.Process.HasExited){$job.Process.Kill($true);$job.Process.WaitForExit()};$job.Process.Dispose()}
}
if($results.Count -ne $catalogue.Count){throw 'MutationCatalogueCoverageIncomplete'}

$killed = $logger.Get('mutant.killed'); $survived = $logger.Get('mutant.survived'); $crashed = $logger.Get('mutant.crashed'); $invalid = $logger.Get('mutant.invalid'); $timeouts = $logger.Get('mutant.timeout')
$score = if (($killed + $survived) -gt 0) { [Math]::Round(100.0 * $killed / ($killed + $survived), 1) } else { 0 }
''
"Project: QuietCli.Core.Tests.PoSh | Task: run-profile mutation campaign ($($catalogue.Count) mutants, seed $Seed)"
"Workspace: $workspace"
''
$rows = [Collections.Generic.List[object]]::new()
foreach ($row in $results) { $rows.Add(@($row.Name, $row.File, $row.Outcome, (Format-RunDuration $row.DurationMs), $row.Detail)) }
Format-RunTable -Headers @('Mutant', 'File', 'Outcome', 'Duration', 'Detail') -Rows $rows -RightAligned @(3)
''
$summaryRows = [Collections.Generic.List[object]]::new()
$summaryRows.Add(@([string]$catalogue.Count, [string]$killed, [string]$survived, [string]$crashed, [string]$timeouts, [string]$invalid, "$score%", (Format-RunDuration $clock.Elapsed.TotalMilliseconds)))
Format-RunTable -Headers @('Mutants', 'Killed', 'Survived', 'Crashed', 'Timeout', 'Invalid', 'Score', 'Duration') -Rows $summaryRows -RightAligned @(0, 1, 2, 3, 4, 5, 6, 7)
if ($OutputPath) {
    $document = [ordered]@{ Seed = $Seed; Iterations = $Iterations; MaxConcurrency=$MaxConcurrency; MaxActive=$peak; ShardIndex=$ShardIndex; ShardCount=$ShardCount; BaselinePassed=$true; SourceSHA256=$sourceSHA256; Revision=$env:GITHUB_SHA; Partial=($catalogue.Count -ne $totalCatalogue); TotalCatalogue=$totalCatalogue; Score = $score; Counters = $logger.Snapshot(); Results = $results }
    Write-RunTextFile -Path ([IO.Path]::GetFullPath($OutputPath)) -Text ((ConvertTo-Json -InputObject $document -Depth 5) + "`n")
}
exit ($survived + $crashed + $timeouts + $invalid)
