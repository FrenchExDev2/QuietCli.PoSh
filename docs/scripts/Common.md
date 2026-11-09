# Common.ps1

## Purpose

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

- Dot-sources `ReportPaths.ps1`, `Ci.Process.ps1`, `SourceIdentity.ps1`, `RuntimeTargets.ps1` (lines 1, 3-5).
- Shells out indirectly through `Invoke-CiProcess` (from `Ci.Process.ps1`).
- `Wait-WorkspaceWorker` directly references a fixed sibling script path, `Join-Path $PSScriptRoot 'Watch-Tests.ps1'` (line 89), and reuses `ConvertTo-CiArgument` (also from `Ci.Process.ps1`) to rebuild a monitor-restart command line (line 98).

## Side effects

- `Invoke-WorkspaceNative` optionally creates and appends to a UTF-8 log file (lines 25-29) in addition to echoing every line to the console.
- `Write-WorkspaceJson` always writes through a temp file plus an atomic rename, with a bounded Windows sharing-violation retry loop (lines 56-68) — it never leaves a partially-written target file.
- `Wait-WorkspaceWorker` can `Start-Process` a new monitor window up to 3 times (line 98), can `Kill($true)` the owned worker process tree on timeout or exhausted monitor restarts (lines 96, 101), and always writes `summary.json`/`status.json` for a worker that ends abnormally (line 113).

## Findings

- Good: `Write-WorkspaceJson`'s write-temp-then-atomic-rename-with-retry pattern (lines 57-68) is a genuinely careful implementation — it retries only on the three specific Windows sharing-violation HRESULT codes (5, 32, 33; line 64), only on Windows, re-checking the target still exists before each retry, and always deletes the temp file in a `finally` (line 68) even on an unretryable failure.
- DESIGN: `Wait-WorkspaceWorker`'s monitor-restart check (lines 90-100) reads `status.json` off disk and inline-hardcodes the terminal-state vocabulary `'Success','Failed','Crash','Timeout','Cancelled'` (line 94) — the exact set `AGENTS.md`'s "Test runs" policy defines. If that vocabulary is ever extended, this is one of potentially several places across the scripts folder carrying the identical literal array rather than one shared constant.
- DESIGN: the crash-fallback `$state` construction (used only when a worker died without ever writing `status.json`) hardcodes a specific project identity directly into this otherwise-generic worker-supervision helper — `Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh'` at line 106, and again `Project='FrenchExDev2.QuietCli.Core.Tests.PoSh'` in the fallback-fill loop at line 109. A caller supervising some other worker (e.g. a future module's own test run) would get this Core/Git project identity baked into its crash report unless its worker happened to write a correctly-identified `status.json` before dying. This is a reusability smell: a function billed as generic worker supervision silently assumes it is only ever supervising the Core+Git companion test run.
- The comment at line 109 ("Preserve valid monitor identity even if a faulty worker replaced its status with a progress DTO") documents a real, previously-hit failure mode — a good comment, but the mitigation is itself coupled to the hardcoded project names noted above.
- Testability: `Write-WorkspaceJson` and `Invoke-WorkspaceNative` are exercised indirectly by 12+ test files, but this is all incidental integration coverage through other suites' use of these helpers, not a focused unit test of, e.g., the Windows sharing-violation retry path (lines 61-66) or the monitor-restart-exhaustion path (line 96) in `Wait-WorkspaceWorker`. No test was found that specifically simulates "the monitor window dies 4 times in a row" to confirm the bounded-3-restarts-then-kill behavior actually triggers.
- `ConvertTo-QuietByteCount` is pure and stateless (no filesystem/process access), so it is covered directly by `CommitWorkspace.Tests.ps1`'s `Test-QuietByteCountParsing` (decimal and binary units, a bare integer, and invalid input throwing `QuietByteCountInvalid`) rather than only incidentally through a caller.

## Verdict

Solid, carefully-written infrastructure that the whole folder depends on, but `Wait-WorkspaceWorker`'s hardcoded Core/Git project identity in its crash-fallback path (lines 106, 109) is the highest-priority fix — a "common" worker supervisor should not assume which project it supervises, and as written it would misreport unrelated future workers' crashes under the wrong project name.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
