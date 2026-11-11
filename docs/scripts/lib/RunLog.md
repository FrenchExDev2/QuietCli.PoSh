# RunLog.psm1 (lib)

## Purpose

Provides leveled logging with named counters for the run-profile tooling, separating the event model (`RunLogger`), the destinations (`RunLogSink` strategy classes: console/file/memory), and the factory (`New-RunLogger`). It solves the need for consistent, filterable, multi-destination logging where every emitted event is counted (even when suppressed by the level filter), so a run's final counters table accurately reflects what the code actually did regardless of verbosity — this is exactly what `Invoke-RunProfile.ps1` relies on for its `profile.*` counters and final `Format-RunCounters` summary (confirmed: `Invoke-RunProfile.ps1` line 44 does `using module ./lib/RunLog.psm1` and uses `$logger.Increment`/`.Time`/`.Snapshot` throughout).

## Usage

Exported function (`Export-ModuleMember`, line 154): `New-RunLogger`. (The `RunLogLevel` enum and `RunLogger`/`RunLogSink`/`ConsoleLogSink`/`FileLogSink`/`MemoryLogSink` classes are module-scoped PowerShell classes, consumable by a caller that does `using module` on this file, as `Invoke-RunProfile.ps1` does.)

Key signatures:
- `New-RunLogger [-Level <RunLogLevel> = Info] [-Component <string> = 'run'] [-LogPath <string>] [-NoConsole] [-ExtraSinks <RunLogSink[]>]` — builds a `RunLogger` with a console sink (stderr) by default, an optional file sink, and any extra sinks (e.g. `MemoryLogSink` for tests).
- `RunLogger.Child([string]$component)` — creates a sub-logger sharing the same sinks/counters, with `Component` suffixed as `parent.child`.
- `RunLogger.Add/Increment/Get` — counter manipulation; `Write`/`Trace`/`Debug`/`Info`/`Warn`/`Error` — leveled emission; every call increments `log.<level>` regardless of filtering, and increments `log.suppressed` when filtered out (line 84).
- `RunLogger.Time([string]$name, [scriptblock]$body)` — runs `$body`, recording `<name>.ok`/`.failed`, `<name>.count`, `<name>.ms`.
- `RunLogger.Snapshot()` — returns an ordinal-sorted `OrderedDictionary` copy of all counters.

Example:
```powershell
using module ./scripts/lib/RunLog.psm1
$logger = New-RunLogger -Level Info -Component 'my-tool'
$logger.Info('starting')
$result = $logger.Time('step', { Do-Something })
```

## Dependencies

- `Import-Module (Join-Path $PSScriptRoot 'RunEncoding.psm1')` (line 12) — used by `FileLogSink.Write` via `Add-RunTextLine` (line 35), ensuring file-sink output is UTF-8-without-BOM/LF-terminated.
- `[Console]::Error.WriteLine` for `ConsoleLogSink` (line 24) — note: synchronous, not async.
- `[DateTime]::Now` (line 85, local time, not UTC) formatted with `InvariantCulture`.

## Side effects

- `ConsoleLogSink.Write` writes to stderr.
- `FileLogSink`'s constructor creates the log file's parent directory if missing (line 32) and `.Write` appends a line to it (line 35) for every non-suppressed log call.
- `MemoryLogSink` only mutates its own in-memory `Lines` list — no external effect, by design, for test use.

## Findings

- DESIGN: `RunLogger.Write` (lines 82–90) wraps each sink's `.Write($line)` call in its own `try { } catch { $this.Add('log.sinkfailed', 1) }` (line 88) — a failing sink (e.g. a `FileLogSink` whose directory became unwritable mid-run) is counted but the actual exception message/detail is discarded entirely, with no way for the caller to ever learn *why* a sink failed, only that one did (via the `log.sinkfailed` counter, which doesn't even distinguish which sink or how many distinct failures vs. repeated single-sink failures). A `Warn`-to-remaining-sinks-with-the-exception-message (while still not throwing, to preserve "logging must never crash the run") would preserve the fail-safe behavior while keeping the failure diagnosable.
- CONVENTION: `ConsoleLogSink.Write` (line 24) uses the synchronous `[Console]::Error.WriteLine($Line)` rather than `.Error.WriteLineAsync(...).GetAwaiter().GetResult()`, which several other files in this review *do* use for console output (e.g. `Common.ps1`'s `Invoke-WorkspaceNative`: `[void][Console]::Error.WriteLineAsync($record.Text).GetAwaiter().GetResult()`). This is a direct, concrete inconsistency with the "always prefer async methods... even in sync PowerShell use `.GetAwaiter().GetResult()`" rule as applied elsewhere in the very same `scripts/` tree, on the exact same `[Console]::Error` API that has an async overload available.
- CONVENTION: `[DateTime]::Now.ToString('HH:mm:ss.fff', ...)` (line 85) uses local time rather than UTC for the log timestamp, while the rest of the tooling (`Common.ps1`, `PreviewTag.psm1`, `Invoke-GitQualification.ps1`) consistently uses `[DateTimeOffset]::UtcNow`. For a local developer run this is a minor readability choice, but it is inconsistent with the rest of the codebase's UTC-first discipline and would make correlating a log line's wall-clock time against a UTC-stamped `status.json`/`summary.json` (written by `Invoke-TestWorker.ps1`/`Common.ps1`) require manual timezone translation.
- No bug found in the counter semantics themselves: `Add`/`Increment`/`Get` (lines 64–79) correctly use `TryGetValue` with a `[ref]` out-parameter rather than a dictionary-indexer default, avoiding a `KeyNotFoundException` path, and `Time` (lines 99–114) correctly records `.failed`/`.ok`/`.count`/`.ms` in all paths including the exception path via its `finally` block.
- Testability: Plausibly covered by the `RunProfiles.*` suites given `Invoke-RunProfile.ps1`'s direct dependency, and the module's own `MemoryLogSink` class exists specifically to make this testable without touching the filesystem/console — a strong design signal that testing was considered — but no test file named specifically for `RunLog.psm1`/`RunLogger` was found, so the `log.sinkfailed`/`Child`/`Snapshot` behaviors in particular have no confirmed dedicated test.

## Verdict

A well-designed, test-friendly logging abstraction (the `MemoryLogSink` strategy alone shows real testability intent) with two concrete, fixable convention inconsistencies — synchronous `[Console]::Error.WriteLine` instead of the async-then-block pattern used elsewhere in the same tree, and local-time rather than UTC timestamps; the console-write async inconsistency is the smaller of the two in practice, so the higher-priority fix is switching the timestamp to UTC for correlation with the rest of the run's UTC-stamped artifacts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Leveled logging with named counters for the run-profile tooling.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
