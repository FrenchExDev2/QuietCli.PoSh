# Watch-Tests.ps1

## Purpose

This is the shared, read-only visible-monitor UI for every test run, mutation campaign, container CI
job, GitHub run watch, gallery publish, and workstation smoke test in the repository. It solves the
problem AGENTS.md mandates directly: "every test run started by an agent also gets a visible
PowerShell Core (pwsh) monitoring window ... started in the background and opened at the same time."
Rather than every orchestration script re-implementing a resizable, bordered status table, they all
launch this one script in a new `pwsh -WindowStyle Normal` window pointed at their own `RunDirectory`.
It is launched by: `Common.ps1`'s `Wait-WorkspaceWorker` (restart path, line 89/98),
`Invoke-ContainerColdStart.ps1`, `Invoke-ContainerCi.ps1`, `Invoke-ContainerRuntimeDiagnosis.ps1`,
`Invoke-PublishedGallery.ps1`, `Invoke-WorkspaceCi.ps1`, `Watch-GitHubRun.ps1`,
`FrenchExDev2.QuietCli.Core.Tests.PoSh\audit\Invoke-Audit.ps1`,
`Invoke-DevelopmentWorkstationSmoke.ps1`, `Invoke-AlpineImageSmoke.ps1`,
`Invoke-PersistentShellBenchmark.ps1`, `native-tests\Invoke-PtyMutation.ps1`,
`native-tests\Invoke-PtyTests.ps1`, and `tools\Invoke-TelemetryQualification.ps1` (all confirmed by
grep) — i.e. essentially every test/CI launcher in the repository. It is also documented as a
stand-alone "reopen a finished report" tool: `docs/README-container-runtime-diagnosis.md:174` and
`docs/audits/2026-11-08-emit-listeners-and-vagrant.md:114` both show
`./scripts/Watch-Tests.ps1 -RunDirectory <path>` used to reopen a past run's saved result.

## Usage

```
[CmdletBinding()]param([Parameter(Mandatory)][string]$RunDirectory)
```

- `RunDirectory` (string, mandatory) — directory containing `status.json` (live/progress state) and,
  once terminal, `summary.json` (final saved result). No other parameters; everything else (interval,
  column widths, theme) is computed internally.

Example:

```powershell
pwsh -File ./scripts/Watch-Tests.ps1 -RunDirectory C:\...\artifacts\tests\host-stable-fixed
```

## Dependencies

- Dot-sources `Monitor.Time.ps1` (line 10) for `Get-QuietMonitorDuration` (the `Duration` column
  formatter: `1s`/`1m30s`/`1h`-style compact units, matching AGENTS.md's required format exactly).
- No module import, no external process, no network — purely reads JSON state files and writes to the
  console. This is consistent with AGENTS.md's stated exception: "The monitor is read-only and only
  reads the run's own output and progress files. This is the one exception to running CLI commands
  through `quiet`."
- Filesystem assumption: `RunDirectory/status.json`, written by *some other, already-running* worker
  process (not this script) using the same atomic-rename pattern as `Write-WorkspaceJson` — this
  script's `Read-RunState` (lines 11-22) explicitly opens the file with
  `FileShare.ReadWrite | FileShare.Delete` to tolerate the writer atomically replacing it mid-read on
  Windows.

## Side effects

- None on disk: this script only reads `status.json`/`summary.json`; it never writes any file.
- Mutates console state: sets the window `[Console]::Title`, disables the cursor
  (`[Console]::CursorVisible=$false`, restored in a `finally` block at line 61/98), and repeatedly
  repositions the cursor to `(0,0)` and rewrites lines in place (line 91) — this is a genuine in-place
  refresh, not a `Clear-Host`, matching the AGENTS.md "no Clear-Host, no blinking" rule.
- Terminates itself (`break` at line 93, then exits the script, closing the window since nothing keeps
  the host alive and there is no `-NoExit` anywhere in this file or its launchers) once `state.State`
  is one of `Success`/`Failed`/`Crash`/`Timeout`/`Cancelled` **and** `summary.json` exists — this
  double condition (terminal state *and* summary file present) correctly avoids closing the window on
  a transient terminal-looking status that hasn't been durably saved yet.

## Findings

- No bugs found in the headline AGENTS.md compliance checklist — and this script is, in fact, the
  single most AGENTS.md-compliant script in this review batch for its specific rule set:
  - First line identifies project and task exactly in the mandated format: `"Projet :
    $($state.Project) | Tâche : $($state.Task)"` (line 69), with a narrower fallback (`P:... | T:Tests`)
    under 75 columns (line 72).
  - Workspace path and project directory are shown as the next two lines (line 73).
  - The table uses literal `|` separators between every column (line 86: `'|'+($cells -join '|')+'|'`)
    and Unicode box-drawing borders (`┌┬┐├┼┤└┴┘─`, lines 76, 87) — genuinely bordered, not
    `Format-Table`.
  - A `Duration` column exists with compact units (`Get-QuietMonitorDuration` produces `1s`/`1m30s`/
    `1h5m`), exactly matching AGENTS.md's required format.
  - Column widths are recomputed every poll iteration from `[Console]::WindowWidth`/`WindowHeight`
    (lines 65-66), not just once at startup — satisfying the "recalculate even if data hasn't changed"
    dynamic-resize requirement.
  - Visible-width measurement (`Get-DisplayWidth`, lines 23-39) explicitly strips ANSI escape sequences
    via regex before measuring, and accounts for East-Asian-wide Unicode ranges and combining marks —
    matching the "do not count ANSI sequences as visible characters" / "measure actual Unicode display
    width" requirements precisely.
  - Cell truncation (`Fit-Cell`, lines 40-57) truncates on text-element (grapheme) boundaries and
    appends `…` rather than splitting a Unicode character or silently wrapping — matching "truncate
    explicitly with `…`" and "without causing automatic line wrap."
  - The cursor is disabled while interactive and explicitly restored in a `finally` block (lines 59-61,
    98) — matching "make cursor disabled when using/coding watchers."
  - Auto-closes on any terminal state once the summary is durably saved, with no `-NoExit` and no
    prompt for keyboard input — matching "Automatically close ... Do not ask the user ... or wait for
    keyboard input."
  - Redirected/non-interactive output produces one static, readable table at a fixed fallback width
    (110×20, lines 65-66, 95) with no cursor-repositioning loop — matching the "static table, explicit
    fallback width, no cursor-reposition sequences" rule for redirected output.
- DESIGN: for a multi-run report (`$state.Runs`, lines 81-84, used for combined Windows+Linux runs),
  the `Passed`/`Failed` columns are hardcoded to `'-'` for every row (line 83:
  `$rows.Add(@($run.Platform,$run.State,$elapsed,$run.Identity,'-','-'))`) regardless of whether the
  per-run object actually carries its own pass/fail counters. If `$run` does carry such counters (as
  the single-run branch does via `$state.Passed`/`$state.Failed`, lines 79, 85), this unconditionally
  discards them instead of falling back to `'-'` only when truly unknown — worth checking against the
  actual `$run` schema producers (outside this file) to confirm whether real data is being thrown away
  here, since AGENTS.md explicitly asks for "available test counters" to be shown, not suppressed.
- DESIGN: there is no self-imposed maximum run time or heartbeat-staleness check inside this script
  itself — if the writer process dies without ever reaching a terminal state (and without the external
  supervisor in `Wait-WorkspaceWorker` noticing, e.g. when this script is reopened standalone per the
  documented "reopen a report" use case against a directory whose writer has already vanished), the
  `do {...} while($true)` loop (lines 62-97) polls forever with no self-termination or staleness
  warning. In the supervised case this is fine (an external `Wait-WorkspaceWorker` manages the overall
  timeout per AGENTS.md's monitor-restart rules), but when a user runs this script by hand against a
  stale `RunDirectory` with no live writer, it will spin at a 400ms poll interval indefinitely with no
  "no update received in N seconds" indication to the viewer.
- CONVENTION: UI text is a mix of French (`"Projet : ... | Tâche : ..."`, `"Rapport : $RunDirectory"`)
  and English column headers (`Platform`, `State`, `Duration`, `Process`/`Job`, `Passed`, `Failed`) —
  this matches AGENTS.md's explicit example line ("Projet : AIWebsiteDetector | Tâche : mutation C# et
  PowerShell") and its "You can talk in UI in user language" allowance, so this is not a violation,
  just worth noting for consistency with sibling scripts that are entirely French in their UI output
  (e.g. `Test-SdkReadiness.ps1`).
- Testability gap: no Pester test exercises `Get-DisplayWidth` or `Fit-Cell` directly (searched both
  `*.Tests.PoSh` projects for both names — no hits). These are exactly the kind of small, pure,
  Unicode-edge-case-prone functions (combining marks, wide CJK ranges, ANSI-sequence stripping,
  grapheme-boundary truncation) that benefit most from property/fuzz testing per AGENTS.md's mandatory
  testing strategy, and currently have none — a targeted fuzz test feeding random Unicode strings
  (including surrogate pairs, zero-width joiners, and embedded ANSI sequences) through `Fit-Cell`/
  `Get-DisplayWidth` and asserting the result never exceeds the requested `Width` would directly
  exercise the two riskiest functions in this file.
- No security concern: this script only reads JSON it or a co-operating sibling script wrote into a
  caller-supplied directory; `RunDirectory` is not validated against path traversal, but since this is
  a local, developer/CI-supplied path (not external/untrusted input), that is low risk here.

## Verdict

This is the best AGENTS.md-compliance match in the whole batch for the monitoring-window and table
rules, and no correctness bug was found in its core rendering/closing logic. The two things worth
prioritizing are: (1) confirming whether the multi-run `Passed`/`Failed` columns are discarding real
per-run counters by hardcoding `'-'` (line 83), and (2) adding fuzz coverage for `Fit-Cell`/
`Get-DisplayWidth` given their Unicode-width-arithmetic complexity and current zero test coverage.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
