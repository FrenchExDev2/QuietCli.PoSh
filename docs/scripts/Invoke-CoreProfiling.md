# Invoke-CoreProfiling.ps1

## Purpose

Runs a separate, dedicated PowerShell line-profiling pass and real CLR EventPipe collection for every
owned target process ID, against an already-completed integration test run's bulk fixture repository.
It exists to produce two complementary observations (PowerShell-level self/inclusive line timings and
native CLR sampled stacks) outside of the actual benchmark samples, so that profiling instrumentation
overhead never contaminates the timing numbers used elsewhere. It is invoked by `Invoke-TestWorker.ps1`
(line 151) when `-Profiler` is requested, after the integration suite's own `controlled-status/fixtures/bulk`
repository has already been created by that run.

## Usage

Parameters (standard ShouldProcess binding, no mandatory attributes on any parameter despite all four being
functionally required):
- `-WorkspaceRoot` (string) — local monorepo.
- `-RunDirectory` (string) — completed integration run containing its owned bulk fixture.
- `-ProfilerModulePath` (string) — pinned Profiler 4.3.0 manifest.
- `-ClrProfilerPath` (string) — pinned `dotnet-trace` 10.0.750501 DLL.

Example:
```powershell
./scripts/Invoke-CoreProfiling.ps1 -WorkspaceRoot C:\repo -RunDirectory C:\run\integration-1 -ProfilerModulePath C:\tools\Profiler\Profiler.psd1 -ClrProfilerPath C:\tools\clr\dotnet-trace.dll
```

## Dependencies

- Dot-sources `Common.ps1` (line 17) for `Write-WorkspaceJson`, `ConvertTo-CiArgument`, `Invoke-CiProcess`.
- Sets `$env:DOTNET_ROLL_FORWARD_TO_PRERELEASE='1'` (line 16).
- Starts `FrenchExDev2.QuietCli.Core.Tests.PoSh/Profiler.Target.ps1` as the profiled workload (line 25–28), waiting for it to signal readiness via `target-ready.json` (lines 30–34).
- Starts one `Invoke-ClrCollector.ps1` process per distinct target PID (PowerShell host + engine, if isolated) (lines 38–46).
- Shells out to `dotnet ... convert ... --format Speedscope` (line 64) for CLR trace post-processing.
- Resolves `pwsh`/`pwsh.exe` via `$PSHOME` (line 21), not via `Get-Command` like other sibling scripts — see Findings.
- Filesystem assumption: `$repository/.git`, `$ProfilerModulePath`, `$ClrProfilerPath` must all exist (checked, line 20) before anything is started.

## Side effects

- Writes `powershell-lines.json` (via `Profiler.Target.ps1`, not written by this script directly), `target-ready.json`, `target-result.json`, per-collector `.nettrace`/`.ready`/`.stdout.log`/`.stderr.log` files, a `release` signal file (line 54), per-collector `.collector.json`, Speedscope-converted JSON, and finally `summary.json` (line 88) under `$RunDirectory/profiling`.
- Starts and later force-kills (`$process.Kill($true)`, line 87, in `finally` for any not-yet-exited owned process) multiple background OS processes.
- Writes the `release` signal file as UTF-8-no-BOM via `[IO.File]::WriteAllTextAsync(...).GetAwaiter().GetResult()` (line 54) — correct async-then-block pattern per `AGENTS.md`.
- Re-throws (`throw`, line 85) on any failure after setting `$report.State='Failed'`, so callers see both a written `summary.json` *and* a terminating exception — the `finally` block (lines 86–89) still runs first via normal PowerShell semantics, so the summary is reliably written even on throw.

## Findings

- CONVENTION: line 21 resolves the `pwsh` runner via `Join-Path $PSHOME ...` instead of `Get-Command pwsh -CommandType Application` as used consistently elsewhere in this folder (e.g. `Invoke-ContainerCi.ps1` line 47, `Invoke-ContainerColdStart.ps1` line 47). `$PSHOME` points at the *currently running* PowerShell installation's home directory, which is correct when this script is itself already running under the desired `pwsh`, but is a different resolution strategy than its siblings and could diverge if this script were ever invoked from Windows PowerShell 5.1 or a different `pwsh` installation than the one on `PATH`. A minor DRY/consistency issue, not demonstrated to be an active bug given current invocation context (always via `Invoke-TestWorker.ps1` running under `pwsh` itself).
- Missing input validation: no `[Parameter(Mandatory)]` on any of the four parameters (line 14), despite the prerequisite check at line 20 implicitly requiring `$ProfilerModulePath`/`$ClrProfilerPath`/the fixture repo to all be truthy/exist — an omitted `-WorkspaceRoot` would pass `$null`/empty straight into `Join-Path $WorkspaceRoot ...` (line 25) and fail with a generic `Join-Path` error rather than a clear parameter-binding error.
- Hardcoded 120-second startup deadline (line 29) for the profiled target to signal readiness, and the same `$deadline` variable is later reused (lines 48–49, 56) as the ceiling for collector-attach and overall process completion — meaning the *total* budget for target startup + collector attach + the entire profiled workload + CLR trace completion is a single, non-extendable 120 seconds from script start. For anything beyond a small bulk fixture this could be tight; no parameter exists to extend it.
- DESIGN: the frame-name bucketing heuraistic (lines 70–76: regex-matching `FrenchExDev2\.QuietCli`, `System\.Management\.Automation|Microsoft\.PowerShell`, `System\.|CoreLib`, else `OtherOrUnresolved`) is explicitly caveated in the script's own `$report.Limits` text (line 82: "Frame-name buckets identify code origins, not additive CPU percentages") — this is an honest, self-documented limitation rather than a hidden one, which is a positive for anyone consuming `summary.json` downstream.
- Validation of collector/target identity is unusually thorough and a genuine strength: `ProfilerTargetIdentityMismatch` (line 36), `ClrCollectorAttachFailed`/`ClrCollectorEndedBeforeWorkload` (lines 49, 52), `ProfiledTargetFailed` including a check that `GitModuleLoaded` is falsy on the profiled target (line 60, presumably enforcing the same kind of "no product module contamination" independence guard seen in `Invoke-ContainerWorker.ps1`'s Mutation suite), and `IsolatedEngineClrTraceMissing`/`IntegratedClrTraceIdentityMismatch` (lines 79–80) cross-checking the expected number of CLR traces against the target's reported `EngineMode`.
- No companion Pester test found for `Invoke-CoreProfiling.ps1`.

## Verdict

Fit for purpose, with genuinely careful cross-checks between the profiled target's self-reported identity and the collectors actually attached. The highest-priority improvement is making the single, reused 120-second deadline (line 29) a parameter — the current fixed budget covers target startup, collector attach, workload execution, and trace completion all at once, which does not scale to a larger profiled workload without editing the script.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs separate PowerShell line profiling and real CLR EventPipe collectors for every owned target PID.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
