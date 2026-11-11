# Common.ps1

`Write-WorkspaceFailureDiagnostics -Summary $summary -RunDirectory $run` prints the saved terminal
state and at most eight failed companion cases, each capped at 2048 characters. It emits no pipeline
objects and starts no process. Full evidence remains in the selected run directory.

## Purpose

`Resolve-QuietVirtEngine -WorkspaceRoot $root [-ContainerRuntime docker|podman] [-Available]`
uses the explicit selection, then `QUIET_CONTAINER_RUNTIME` from the selected checkout's `.env`,
then Get-Command discovery: Podman before Docker on Windows and Linux.
Invalid, empty or duplicate assignments fail explicitly. A configured engine never silently falls
back to another one. Available
also verifies an explicit engine exists as an application. It starts no daemon, performs no network
operation and makes no health claim. Container launchers resolve once and forward the engine;
image PlanOnly remains offline and does not require discovery. AutomationContracts.Tests.ps1
covers every availability/explicit-selection combination, the platform-independent preference, configuration precedence and a preference-order mutant. See the
[environment contract](../ci/environment.md) for deterministic Local/GitHub initialization.

The shared, load-bearing operational layer most other scripts in this folder depend on. It supplies the one approved way to shell out to a native tool with bounded failure diagnostics (`Invoke-WorkspaceNative`), the one approved way to publish JSON state atomically for a read-only monitor to observe (`Write-WorkspaceJson`), the supervisor loop that owns a background worker process together with its dedicated visible monitor window, restarting that monitor (bounded to 3 attempts) if it dies before the run reaches a terminal state (`Wait-WorkspaceWorker`), and a single reusable parser for human-readable size thresholds (`ConvertTo-QuietByteCount`, added for `Commit-Workspace.ps1`'s binary/oversized-file sniffer, but not special-cased to it — any script needing a size threshold, such as `Test-WorkspacePackage.ps1`'s hardcoded archive limits, can reuse it instead of duplicating the parsing). It is dot-sourced by at least 28 other scripts in this folder (confirmed by search), making it the single most depended-upon file in the set. It is itself a hub: it dot-sources `ReportPaths.ps1`, `Ci.Process.ps1`, `SourceIdentity.ps1`, and `RuntimeTargets.ps1` (lines 1, 3, 4, 5), so every caller gets that whole chain for free with one dot-source.

## Usage

A function library; no script-level params.

| Function | Key parameters |
|---|---|
| `Invoke-WorkspaceNative` | `FilePath`, `Arguments`, `WorkingDirectory`, `TimeoutSeconds` (`ValidateRange(1,3600)`, default 600), `LogPath` (optional) |
| `Write-WorkspaceJson` | `Path`, `Value` |
| `Wait-WorkspaceWorker` | `Worker` (`Diagnostics.Process`), `RunDirectory`, `WorkspaceRoot`, `Runner`, `Monitor` (`Diagnostics.Process`), `TimeoutSeconds` |
| `ConvertTo-QuietByteCount` | `Size` (`string`, mandatory) — a bare integer (bytes), or a number with a decimal (`KB`/`MB`/`GB`/`TB`, powers of 1000) or binary (`KiB`/`MiB`/`GiB`/`TiB`, powers of 1024) unit suffix, case-insensitive, optional whitespace before the unit |

```powershell
. ./scripts/Common.ps1
Invoke-WorkspaceNative dotnet @('build', $csproj, '-c', 'Release') $WorkspaceRoot -LogPath (Join-Path $run 'build.log')
ConvertTo-QuietByteCount '500KB'   # 500000
ConvertTo-QuietByteCount '1 MiB'   # 1048576
```

## Dependencies

The Core test companion dot-sources this library in its private module scope. Loading it only in a
worker's script scope does not make the helpers available to functions defined in that module.
The companion's clean-process import regression checks helper source paths and prevents accidental
helper exports; CI test execution remains independent of workstation profile initialization.

- Dot-sources `ReportPaths.ps1`, `Ci.Process.ps1`, `SourceIdentity.ps1`, `RuntimeTargets.ps1` and `EnvFile.ps1`.
- Shells out indirectly through `Invoke-CiProcess` (from `Ci.Process.ps1`).
- `Wait-WorkspaceWorker` directly references a fixed sibling script path, `Join-Path $PSScriptRoot 'Watch-Tests.ps1'` (line 89), and reuses `ConvertTo-CiArgument` (also from `Ci.Process.ps1`) to rebuild a monitor-restart command line (line 98).

## Side effects

- `Invoke-WorkspaceNative` optionally creates and appends to a UTF-8 log file (lines 25-29) in addition to echoing every line to the console.
- `Write-WorkspaceJson` creates missing destination directories, then writes UTF-8 without a BOM through a sibling temp file and an atomic rename, with a bounded Windows sharing-violation retry loop. Temporary-file cleanup covers write and rename failures. Callers own the operation's WhatIf/Confirm guard; dot-sourcing this library creates no directories.
- `Wait-WorkspaceWorker` can `Start-Process` a new monitor window up to 3 times (line 98), can `Kill($true)` the owned worker process tree on timeout or exhausted monitor restarts (lines 96, 101), and always writes `summary.json`/`status.json` for a worker that ends abnormally (line 113).

## Findings

- Good: `Write-WorkspaceJson`'s write-temp-then-atomic-rename-with-retry pattern (lines 57-68) is a genuinely careful implementation — it retries only on the three specific Windows sharing-violation HRESULT codes (5, 32, 33; line 64), only on Windows, re-checking the target still exists before each retry, and always deletes the temp file in a `finally` (line 68) even on an unretryable failure.
- DESIGN: `Wait-WorkspaceWorker`'s monitor-restart check (lines 90-100) reads `status.json` off disk and inline-hardcodes the terminal-state vocabulary `'Success','Failed','Crash','Timeout','Cancelled'` (line 94) — the exact set `AGENTS.md`'s "Test runs" policy defines. If that vocabulary is ever extended, this is one of potentially several places across the scripts folder carrying the identical literal array rather than one shared constant.
- DESIGN: the crash-fallback `$state` construction (used only when a worker died without ever writing `status.json`) hardcodes a specific project identity directly into this otherwise-generic worker-supervision helper — `Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh'` at line 106, and again `Project='FrenchExDev2.QuietCli.Core.Tests.PoSh'` in the fallback-fill loop at line 109. A caller supervising some other worker (e.g. a future module's own test run) would get this Core/Git project identity baked into its crash report unless its worker happened to write a correctly-identified `status.json` before dying. This is a reusability smell: a function billed as generic worker supervision silently assumes it is only ever supervising the Core+Git companion test run.
- The comment at line 109 ("Preserve valid monitor identity even if a faulty worker replaced its status with a progress DTO") documents a real, previously-hit failure mode — a good comment, but the mitigation is itself coupled to the hardcoded project names noted above.
- Testability: `GitHubCi.Tests.ps1` directly checks missing-parent publication, 64 seeded Unicode create/overwrite round trips, relative paths, an invalid parent that is a regular file, temporary-file cleanup, and a missing-directory-creation mutant. It also executes the real matrix selector for Core/Git/All with offline image adapters, including WhatIf no-write checks. These filesystem integration checks do not simulate Windows sharing-violation retries or monitor-restart exhaustion.
- `ConvertTo-QuietByteCount` is pure and stateless (no filesystem/process access), so it is covered directly by `CommitWorkspace.Tests.ps1`'s `Test-QuietByteCountParsing` (decimal and binary units, a bare integer, and invalid input throwing `QuietByteCountInvalid`) rather than only incidentally through a caller.

## Verdict

Solid, carefully-written infrastructure that the whole folder depends on, but `Wait-WorkspaceWorker`'s hardcoded Core/Git project identity in its crash-fallback path (lines 106, 109) is the highest-priority fix — a "common" worker supervisor should not assume which project it supervises, and as written it would misreport unrelated future workers' crashes under the wrong project name.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## Live administrative reporting

Invoke-WorkspaceNative prints operation progress and a terminal outcome/line summary. Wait-WorkspaceWorker streams bounded tails of the owned stdout/stderr logs through ReportStreaming.ps1, with an elapsed/observed-line heartbeat and the saved terminal state. No objective announcement is printed when this library is loaded. Diagnostic activity is distinct from test counters and never enables product event collection.

## Explicit local cancellation

Stop-WorkspaceWorker -WorkspaceRoot <root> -RunDirectory <printed-run-directory> verifies the recorded workspace, pwsh PID, worker script, run path and process creation time before stopping that owned Windows process tree. ShouldProcess protects cancellation; WhatIf leaves the worker and reports unchanged. It saves Cancelled evidence before termination so the read-only monitor closes normally. Status timestamps are read as ISO strings to avoid culture-dependent PID ownership checks. A cancelled run never qualifies a delivery; existing logs and fixtures remain available.

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves an explicit engine, checkout dotenv configuration, then Podman before Docker on every host.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 1.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
