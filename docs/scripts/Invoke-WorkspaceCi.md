# Invoke-WorkspaceCi.ps1

Core/All invocations validate the complete case catalogue and manifest scheduling declarations before profiler preparation, builds, worker/report creation or case execution. Invalid classifications/policies therefore fail early even for a filtered run. WhatIf still returns before orchestration effects. The Core runner saves its plan and enforces declared Ordered/Exclusive barriers and bounded isolated batches; `MaxConcurrency` combines with the manifest cap, with one internal slot per case child. See [classification and concurrency](../README-test-classification-and-concurrency.md).

## Purpose

The top-level CI/local-test launcher: it (optionally) builds the workspace, then starts `Invoke-TestWorker.ps1` as a background process plus (unless `-Headless`) a dedicated, visible `pwsh` monitor window (`Watch-Tests.ps1`), and waits for both to reach a terminal state via `Wait-WorkspaceWorker`. It solves the need for one consistent command — used identically by a developer running tests locally with a visible window, and by CI running headless — that builds, runs, supervises, and reports on the companion test suites, satisfying the repository's mandatory "every test run gets a visible monitoring window" rule while still working unattended in CI. It is the documented and actually-used CI entry point: `.github/workflows/ci.yml` calls it at least three times (`./scripts/Invoke-WorkspaceCi.ps1 @parameters` line 141; `-Suite RunProfiles ...` line 145; `-Suite RunProfilesMutation ...` line 149) and `.github/workflows/publish-psgallery.yml` calls it twice (`-Suite All ...` line 76; `-Suite GalleryPreview ...` line 108).

## Usage

Parameters (plus the same dynamic `-Suite` parameter mechanism as `Invoke-TestWorker.ps1`, via `New-QuietWorkspaceSuiteParameter`):
- `WorkspaceRoot` (`string`, optional, default: parent of `$PSScriptRoot`).
- `RunDirectory` (`string`, optional) — new output directory; generated (timestamp+GUID) under `Get-QuietReportRoot ... 'tests'` when omitted; throws `TestRunDirectoryExists` if it already exists (line 54).
- `Headless` (`switch`, optional) — CI-only mode without a desktop monitor process or a monitor reopen instruction. GitHub Actions uses this mode. The test worker still runs in the selected `$PSHOME` process for assembly isolation and bounded timeout supervision. **On non-Windows, omitting `-Headless` kills the worker and throws** ("Use the Windows host launcher for a visible local monitor").
- `SkipBuild` (`switch`, optional) — uses an already-built engine/test fixture, skipping `Build-Workspace.ps1`.
- `TimeoutSeconds` (`int`, `ValidateRange(1,7200)`, default `1800`) — maximum worker wall-clock time.
- `ExpectedRuntimeIdentifier` (`string`, `ValidatePattern('^[a-z0-9-]+$')`, optional) — forwarded to the worker for runtime-identity verification.
- `RepositoryConfig` (`string`, optional) — required (throws `RealStatusRequiresRepositoryConfig`, line 60) when `-Suite RealStatus`.
- `SkipTty`, `Profiler`, `ProfilerModulePath`, `ClrProfilerPath`, `Case`, `StopOnFirstFailure` — forwarded verbatim to the worker.
- `MaxConcurrency` (`int`, `ValidateRange(1,32)`, default `min(4, processor count)`) — bounds parallel-safe internal test campaigns and is forwarded to the worker.

Example (as used in `.github/workflows/publish-psgallery.yml` line 76):
```powershell
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild -Headless -SkipTty -ExpectedRuntimeIdentifier win-x64
```
Local developer example (visible monitor):
```powershell
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core
```

## Dependencies

- Dot-sources `WorkspaceProjects.ps1` (dynamicparam) and `Common.ps1` (line 44), which supplies `Get-QuietReportRoot`, `ConvertTo-CiArgument`, `Wait-WorkspaceWorker`.
- Calls `Initialize-Profilers.ps1` (line 48) when `-Profiler` is set without explicit profiler paths.
- Calls `Build-Workspace.ps1` (line 52) unless `-SkipBuild`.
- Shells out to `pwsh`/`pwsh.exe` (resolved via `$PSHOME`, line 56) twice: once to launch `Invoke-TestWorker.ps1` as the hidden worker, once to launch `Watch-Tests.ps1` as the visible monitor (lines 69–74).
- Filesystem: creates `$RunDirectory` and writes `worker.stdout.log`/`worker.stderr.log`/`monitor.stderr.log` into it.

## Side effects

On failure, the job log includes the terminal state and up to eight failed companion cases (2048
characters each) before the launcher throws. Full reports stay in the run directory and CI artifacts.
The script-generation regression retains `scripts/live-diagnostics.json` with named direct/generated
results, fixture byte counts/hex and child encodings. The CI stream regression retains
`ci-process-encoding-diagnostics.json` on a Unicode mismatch; decoded-text hex is explicitly separate
from the raw fixture bytes. These records contain synthetic test data, not environment dumps.

- Creates a new run directory (throws if a caller-specified one already exists — line 54).
- Starts a test worker, plus a visible monitor only for local runs without `-Headless`.
- Prints the exact monitor reopen command only when starting a local monitor. Headless CI does not ask the operator to launch another PowerShell process; its reports remain in the run directory.
- Propagates failure as a thrown exception referencing the run directory (line 78) rather than a plain nonzero exit, so CI logs retain a human-readable pointer to the evidence.
- Indirectly, through `Build-Workspace.ps1` (unless skipped) and `Invoke-TestWorker.ps1`, triggers compilation and potentially broader filesystem/process activity outside this script's own direct control.

## Findings

- BUG: Line 72, `if(!$IsWindows){$worker.Kill($true);throw '...'}` — this check happens *after* the worker process has already been started (`$worker=Start-Process @options` at line 69) and *after* the `if(!$Headless){ ... }` block has begun, meaning on a non-Windows host without `-Headless`, a real worker process (potentially already doing meaningful background work, including file writes) is started and then forcibly killed. This is wasted work and a race: the worker could have already written partial files to `$RunDirectory` before being killed, leaving a half-populated run directory behind for a directory that `TestRunDirectoryExists` will treat as pre-existing on the next attempt with the same explicit `-RunDirectory`.
- DESIGN: The headless/non-Windows-requires-headless invariant (lines 71–73) could be checked once, at the very top of the script (before any `Build-Workspace.ps1` or `Start-Process` call), rather than after the worker has already launched — this would avoid the wasted process spin-up and kill entirely.
- CONVENTION: No explicit UTF-8 encoding is applied to the `RedirectStandardOutput`/`RedirectStandardError`/`monitor.stderr.log` file redirections (lines 67, 73) — same gap as noted in `Invoke-PublishedGallery.ps1`, which shares this pattern; worth fixing in both places (or, better, in a shared helper) for consistency with the UTF-8-everywhere repository rule.
- DESIGN: The script duplicates nearly the entire worker-argument-building and monitor-launch logic already present in `Invoke-PublishedGallery.ps1` (`$runner=...`, `$options=@{FilePath=...;ArgumentList=...;PassThru=$true;RedirectStandardOutput=...}`, `$monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @(...)`). This is a DRY violation across two files in the same `scripts/` folder; a shared `Start-WorkspaceWorkerWithMonitor` helper in `Common.ps1` (which already hosts `Wait-WorkspaceWorker`) would remove the duplication and reduce the chance of the two copies drifting (as they already have — this file's non-Windows headless check does not exist in `Invoke-PublishedGallery.ps1`'s equivalent code path, which throws before starting anything, lines 21 there vs. line 72 here).
- Testability: No Pester test found exercising `Invoke-WorkspaceCi.ps1` directly; being the literal CI entry point, its correctness is validated only by every real CI run, which means a regression here would most likely be discovered by a broken pipeline rather than a fast local test.

## Verdict

This is the load-bearing CI entry point and is functionally sound for the common case, but the non-Windows headless check runs too late and wastes a process start/kill cycle, and it duplicates worker/monitor launch logic that already exists almost verbatim in `Invoke-PublishedGallery.ps1`. Highest-priority fix: move the `!$IsWindows -and !$Headless` guard to the top of the script, before `Build-Workspace.ps1` and `Start-Process` run, so a doomed invocation fails immediately instead of after side effects have begun.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## .NET tooling review

The DotNet host suite accepts DotNetSuite Readiness|Provisioning|Layout|Locks|All and always skips product compilation. It still uses the shared worker, visible monitor, owned timeout and external report root. This focused automation scope is not Core/All release qualification; scripts/Invoke-WorkspaceCi.ps1 passes the selected DotNetSuite to its worker explicitly.

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs companion suites with a dedicated local monitor; CI uses the same saved state.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
