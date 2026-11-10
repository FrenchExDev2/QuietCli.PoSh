# Measure-ColdStart.ps1


## Current hosted-path measurement

The hosted-path field follows scripts/lib/RunColdStart.psm1 and the module Protocol.ps1: actual CLR/RID slot when selected, otherwise portable IL, with unused RID children excluded. Whole-module bytes and compressed-package bytes remain separate measurements. The RunProfiles benchmark properties and real A/A smoke validate these fields; a format or size change does not establish a speedup.

## Purpose

Runs the actual A/B performance comparison between two QuietCli Core module builds (typically a baseline vs. a ReadyToRun-compiled candidate), answering "is the candidate's cold start (module import, first native call, second native call) measurably faster or slower, and at what on-disk/package-size cost?" Each sample is a brand-new `pwsh -NoProfile` child process (so OS/CLR-level cold-start effects are real, not simulated), baseline/candidate order is randomized per pair with a fixed seed so machine drift affects both variants equally, and the verdict comes from `RunStatistics.psm1`'s seeded bootstrap. This is the human-facing report generator referenced throughout `docs/README-ab_testing.md` and is the direct consumer of `RunProfiler.psm1`, `RunStatistics.psm1`, and the `RunColdStart`/`RunFormat`/`RunEncoding`/`RunLog` modules (imported line 112). It is run manually or from a profile (see `scripts/RunProfiles/coldstart-100.profile.ps1`, `coldstart-1000.profile.ps1`) via `scripts/Invoke-RunProfile.ps1`.

## Usage

Parameters (all optional except `-CandidateModule`):
- `-BaselineModule [string]` — default: `FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1` next to `scripts/`.
- `-CandidateModule [string]` (Mandatory) — e.g. a temp ReadyToRun build's manifest.
- `-BaselineLabel [string]` (default `'baseline'`), `-CandidateLabel [string]` (default `'candidate'`) — display names, `ValidateNotNullOrEmpty`.
- `-Runs [int]` (default `30`, range 3-100000) — measured pairs.
- `-Warmup [int]` (default `2`, range 0-1000) — discarded pairs executed first.
- `-ChildCommand [string[]]` — native command timed inside each child; default `cmd /c exit 0` on Windows, `true` elsewhere.
- `-Seed [int]` (default `20261107`) — pair-order and bootstrap seed.
- `-RunTimeoutSeconds [int]` (default `120`, range 10-3600).
- `-MaxFailedPairs [int]` (default `5`) — campaign aborts past this many discarded pairs.
- `-BootstrapResamples [int]` (default `2000`, range 100-1,000,000), `-Confidence [double]` (default `0.95`, range 0.5-0.9999).
- `-ProfileImport [switch]` — also profiles one import per variant with PSProfiler.
- `-ProfilerModulePath [string]`, `-ProfileDirectory [string]` (default `%TEMP%/QuietCli2-coldstart-profiles`).
- `-MeasurePackageSize [switch]` — also runs `Compress-PSResource` per variant (off by default: slower, requires a real publishable manifest).
- `-OutputPath [string]` — optional JSON dump of parameters/environment/counters/raw pairs.
- `-LogLevel` (`ValidateSet('Trace','Debug','Info','Warn','Error','Off')`, default `'Info'`), `-LogPath [string]`.

Example (from the file's own `.EXAMPLE`):
```powershell
./scripts/Invoke-RunProfile.ps1 coldstart-100 -Arguments @{ CandidateModule = 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh.psd1' }
```
Direct invocation:
```powershell
./scripts/Measure-ColdStart.ps1 -CandidateModule C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh.psd1 -Runs 50 -ProfileImport
```

## Dependencies

- `using module ./lib/RunLog.psm1` (line 88) plus `Import-Module` of `RunFormat`, `RunStatistics`, `RunProfiler`, `RunEncoding`, `RunColdStart` (line 112, all under `lib/`).
- Shells out to `pwsh -NoProfile -Command $Worker` for every sample (via `quiet`, line 186), i.e. depends on the `quiet` alias/cmdlet from `FrenchExDev2.QuietCli.Core.PoSh` being loadable (auto-imported at line 208 if `Get-Command quiet` fails).
- The generated child script itself (`Get-WorkerScript`, lines 116-143) calls `quiet -AsObject ... @child` where `$child` is the user-supplied `-ChildCommand`; this is a genuine external-process dependency (default `cmd`/`true`).
- `Get-ProfiledWorkerScript` depends on `Profiler` (pinned 4.3.0) transitively through `RunProfiler.psm1`.
- Filesystem assumption: both `-BaselineModule` and `-CandidateModule` manifests must exist (checked at line 207) or the whole run throws `ModuleManifestNotFound` before anything executes.

## Side effects

- Spawns `$Warmup + $Runs` pairs x 2 fresh `pwsh -NoProfile` child processes (potentially thousands for large `-Runs`), each with its own `RunTimeoutSeconds` deadline.
- Optionally (with `-ProfileImport`) spawns one more child per variant and writes a `<Label>.profile.json` under `-ProfileDirectory` (via `RunProfiler.psm1`, creating the directory if missing).
- Optionally (with `-MeasurePackageSize`) runs `Compress-PSResource`, which creates `.nupkg` files — the exact destination isn't shown in this file (delegated to `RunColdStart.psm1`'s `Get-RunModulePackageBytes`, not reviewed here).
- Writes `-OutputPath` (if given) as UTF-8 JSON via `Write-RunTextFile`.
- Writes to `-LogPath` (if given) via the `RunLog` logger.
- Prints a human-readable report (tables, verdicts, total duration) to standard output; leveled logs/counters go to standard error (per the module's own `.DESCRIPTION`).
- No git interaction, no network access beyond whatever the `-ChildCommand`/module import itself triggers.

## Findings

- No bug found in the pairing/randomization logic: `$order = if ($random.Next(2) -eq 0) { @(0, 1) } else { @(1, 0) }` (line 230) and the warm-up-vs-measured split (`$measured = $pair -gt $Warmup`, line 229) correctly separate discarded warm-up pairs from measured ones, and a pair with *any* failed run (lines 232-246) is discarded as a whole rather than partially recorded, matching the stated "never retried, discarded whole" design.
- No issue found in the abort threshold itself: `if ($logger.Get('pair.discarded') -gt $MaxFailedPairs) { ...; throw }` (line 245) tolerates exactly `$MaxFailedPairs` discarded pairs and aborts on the next one, which matches both the parameter's stated intent ("Failed pairs tolerated before the campaign aborts") and the logged message's own wording ("more than $MaxFailedPairs failed pairs, aborting") — behavior and documentation agree.
- CONVENTION: this script does not open a dedicated Start-Process monitoring window as AGENTS.md's "Test runs" section requires for test/mutation campaigns ("Every test run started by an agent also gets a visible PowerShell Core (`pwsh`) monitoring window..."). This script is a performance *measurement* campaign, not a test run in the Pester sense, so it's arguably out of scope for that rule, but it does spawn potentially thousands of child processes over a long wall-clock duration with only textual `$logger.Info` progress lines (line 249) as visibility — an agent running this unattended for a large `-Runs` value has no bordered Unicode-box live table as the repo's UI conventions elsewhere mandate for long-running monitored work.
- CONVENTION: table rendering (`Format-RunTable`, called at lines 301, 303, 306) is delegated to `RunFormat.psm1` (not reviewed in this pass) rather than built inline here — this is good separation of concerns, assuming that module itself honors the Unicode-box/`|`-separator/`Duration` column conventions; this file's own column headers (`'Duration (median)'`, `'Duration (CI low)'`, etc., lines 303/306) use parenthetical suffixes rather than the literal single-word `Duration` column-name convention from the user's memory note ("printed durations go in a column named Time... wait, this repo's own convention names it `Duration`" per AGENTS.md) — worth checking whether `Format-RunTable`'s renderer or the header text itself should be the exact literal word `Duration`.
- No obvious unhandled error path: `$ErrorActionPreference = 'Stop'` (line 111) plus explicit `try/catch` around the per-pair execution (lines 232-246) and top-level manifest existence checks (line 207) cover the main failure surfaces; the `finally`-less `$client`-style pattern isn't used here since there's no unmanaged resource held across the whole script.
- Testability: no dedicated Pester test file for `Measure-ColdStart.ps1` itself was found (its dependencies `RunStatistics.psm1`, `RunProfiler.psm1`, `RunToolCache.psm1` are well-covered, but this orchestrating script's own worker-script generation, pairing loop, and off-by-one in the abort threshold are not directly asserted by any test found in this review). Given its complexity (child-process orchestration, two generated inline script templates, randomized ordering), a Pester test exercising at least the abort-threshold boundary and the warm-up/measured split with fake `Invoke-ColdRun` results would close a real gap.

## Verdict

Functionally solid and methodologically careful (randomized pairing, whole-pair discard, seeded bootstrap verdicts), but needs two small fixes: correct the off-by-one in the `-MaxFailedPairs` abort comparison (line 245, use `-ge` instead of `-gt`, or document the intended off-by-one), and add a script-level Pester test for the pairing/abort logic since none currently exists.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Compares the cold-start cost of two QuietCli Core module builds with interleaved, fresh-process, paired runs.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
