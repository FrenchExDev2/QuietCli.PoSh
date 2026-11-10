# Invoke-ClrCollector.ps1

## Purpose

Collects exactly one pinned EventPipe (`dotnet-trace`) trace against an already-running, owned
PowerShell/engine process, and signals when the trace has actually started recording (not just when the
collector process has launched) by writing a ready-file once its output matches a recording marker. This
exists because the profiling pipeline needs to know with certainty that sampling has begun before letting
the profiled workload run, rather than racing a fixed sleep. It is invoked by
`Invoke-CoreProfiling.ps1` (line 41) once per target process ID (PowerShell host and, if isolated, the
engine process), as part of the CLR+PowerShell dual-profiling pass triggered by `Invoke-TestWorker.ps1`
(line 151) when `-Profiler` is requested.

## Usage

Parameters (standard ShouldProcess binding; no mandatory flags):
- `-ClrProfilerPath` (string) — pinned `dotnet-trace` DLL path.
- `-TargetProcessId` (int) — owned PowerShell or engine process ID to sample.
- `-OutputPath` (string) — destination `.nettrace` artifact path.
- `-ReadyPath` (string) — file written only after the collector reports it is actually recording.

Example:
```powershell
./scripts/Invoke-ClrCollector.ps1 -ClrProfilerPath C:\tools\dotnet-trace.dll -TargetProcessId 12345 -OutputPath C:\run\clr-12345.nettrace -ReadyPath C:\run\clr-12345.ready
```

## Dependencies

- Dot-sources `Common.ps1` (line 16), which provides `Write-WorkspaceJson` and (transitively) `Invoke-CiProcess`.
- Shells out to `dotnet` (via `Invoke-CiProcess`, line 18) with `--roll-forward LatestMajor <ClrProfilerPath> collect --process-id ... --profile dotnet-sampled-thread-time --buffersize 64 --duration 00:00:00:30 --output ...` — a hardcoded 30-second trace duration.
- Sets `$env:DOTNET_ROLL_FORWARD_TO_PRERELEASE='1'` process-wide (line 15) as a side effect of being dot-sourced into the calling process, or set in its own process if run via `&`/`-File`.
- Assumes the target process ID is already running and owned by the caller (no validation that the PID exists or is reachable before invoking `dotnet-trace`).

## Side effects

- Writes the `.nettrace` output file at `-OutputPath`.
- Writes `<OutputPath>.collector.json` (line 25) via `Write-WorkspaceJson`, capturing execution result, readiness flag, and up to 200 captured log lines.
- Writes `-ReadyPath` with the literal text `'recording'` once the regex `'Recording trace|Output File\s*:'` matches collector output (lines 21–23), using `.GetAwaiter().GetResult()` on the async write per the repo's async convention.
- Calls `exit 1` (line 26) on any of: non-Success outcome, readiness never signaled, output file missing, or output file empty — this is a hard process exit, not a thrown exception, which matters for how callers must detect failure (exit code vs. `$Error`/try-catch).

## Findings

- DESIGN: ShouldProcess now guards the whole collector operation. The four parameters still lack mandatory attributes — all four are functionally required, yet none use `[Parameter(Mandatory)]`. Omitting `-TargetProcessId` passes `0`, so native failure remains less precise than parameter validation.
- Missing input validation: no check that `-TargetProcessId` refers to a live process, and no check that `-ClrProfilerPath` exists before invocation (line 18) — a nonexistent profiler DLL path would only surface as a generic `dotnet` failure inside `Invoke-CiProcess`.
- The trace `--duration` is hardcoded to `00:00:00:30` (30 seconds, line 18) with no parameter to override it — every profiling run is locked to exactly 30 seconds regardless of workload size; this should arguably be a parameter with a sensible default, per the "hardcoded values that should be parameters" guidance.
- `-TimeoutSeconds 90` (line 18) is also hardcoded; combined with the 30s fixed trace duration this leaves only 60s of margin for process startup/collector attach/shutdown, which could be tight on a loaded CI host — no evidence of this being configurable.
- The async write at line 22 correctly follows the repo's `.GetAwaiter().GetResult()` convention for sync PowerShell using async .NET APIs, and explicit UTF-8 (no BOM) encoding is used — this is a genuine positive, consistent with `AGENTS.md`'s "Asynchronous programming" and "UTF-8" sections.
- No companion Pester test found for `Invoke-ClrCollector.ps1` in the repo.
- The hard `exit 1` (line 26) rather than `throw` means a caller using `&` (call operator) must check `$LASTEXITCODE` explicitly rather than relying on `$ErrorActionPreference='Stop'`/try-catch to propagate failure — `Invoke-CoreProfiling.ps1` does not appear to check `$LASTEXITCODE` after invoking the collector indirectly via `Start-Process` (it instead polls for the ready/trace files and checks `$process.ExitCode` later), so this is consistent with how it's actually consumed, but it is a subtle, easy-to-miss contract for any future caller.

## Verdict

Functionally sound and consistent with its one caller's expectations, but fragile due to missing mandatory-parameter enforcement and hardcoded 30s/90s timing constants. Highest-priority fix: mark all four parameters `[Parameter(Mandatory)]` so misconfiguration fails fast and close to the cause.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Collects one pinned EventPipe trace, signals actual recording readiness and retains terminal diagnostics.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
