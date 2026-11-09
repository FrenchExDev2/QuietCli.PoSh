# Invoke-TestWorker.ps1

## Purpose

This is the actual background worker that runs the companion test suites (Core, Git, Vagrant, Integration, RealStatus, Import, RunProfiles, GalleryPreview, Script, AgentInstructions, ConfigurationDelivery, Recall, etc.) in an isolated process, verifying environment/engine identity invariants before and after the run, and always persisting a terminal JSON report (`status.json`, `summary.json`) so a concurrent monitor and the launching process can observe progress and the final state. It solves the need for test execution that is simultaneously isolated (own process, own module imports, own engine), self-verifying (detects source drift during the run, mismatched runtime/engine identifiers), and observable (every state transition written atomically to disk for a separate monitor window to read). It is spawned by `Invoke-WorkspaceCi.ps1` via `Start-Process` (confirmed: `Invoke-WorkspaceCi.ps1` line 57/67–69 builds `$workerPath = Join-Path $PSScriptRoot 'Invoke-TestWorker.ps1'` and launches it hidden), which is itself called directly from `.github/workflows/ci.yml` and `.github/workflows/publish-psgallery.yml`. This script is never meant to be run by a human directly — it is the hidden half of the launcher/worker/monitor triad.

## Usage

This is an `end`-block script with a `dynamicparam` block (so `-Suite` validated values depend on `New-QuietWorkspaceSuiteParameter`, resolved at parse time from `WorkspaceProjects.ps1`).

Parameters:
- `WorkspaceRoot` (`string`, **mandatory**) — QuietCli2 workspace root.
- `RunDirectory` (`string`, **mandatory**) — private output directory for this run.
- `ExpectedRuntimeIdentifier` (`string`, optional) — required native RID for both host and engine; mismatches throw.
- `RepositoryConfig` (`string`, optional) — UTF-8 JSON array of existing repository roots; required when `-Suite RealStatus`.
- `SkipTty` (`switch`, optional) — excludes native TTY/PTY execution; local runs include it by default. Comment at line 35 explicitly says this is "development-only... never set by CI or the pre-commit gate."
- `Profiler` (`switch`, optional) — enables a separate PowerShell/CLR profiling pass.
- `ProfilerModulePath`, `ClrProfilerPath` (`string`, optional) — explicit pinned profiler artifacts.
- `Case` (`string`, optional) — development-only wildcard case filter (sets `$env:QUIETCLI_TEST_CASE`).
- `StopOnFirstFailure` (`switch`, optional) — development-only; stops the Core run at first failure (sets `$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE`).
- `-Suite` (dynamic, default `'All'`) — `Core`, `Git`, `Vagrant`, `All`, `Import`, `Integration`, `RealStatus`, `RunProfiles`/`RunProfilesMutation`, `GalleryPreview`, `Script`, `AgentInstructions`, `ConfigurationDelivery`, `Recall`/`RecallMutation`/`RecallLarge`.

Example (as actually invoked by `Invoke-WorkspaceCi.ps1`):
```powershell
pwsh -File ./scripts/Invoke-TestWorker.ps1 -WorkspaceRoot . -RunDirectory ./artifacts/run-xyz -Suite Core
```

## Dependencies

- Dot-sources `WorkspaceProjects.ps1` (dynamicparam, line 27), `Common.ps1` (line 34), `TestConfiguration.ps1` (line 40).
- Imports `FrenchExDev2.QuietCli.Core.PoSh.psd1` (line 55) and, depending on `-Suite`, dot-sources or imports numerous test-companion modules/scripts from `FrenchExDev2.QuietCli.Core.Tests.PoSh/` (e.g. `Invoke-RunProfileQualification.ps1`, `GalleryPreview.Tests.ps1`, `Script.Tests.ps1`, `AgentInstructions.Tests.ps1`, `ConfigurationDelivery.Tests.ps1`, `Integration.Tests.ps1`, `Status.Real.Tests.ps1`, `Import.Tests.ps1`, `Recall.Mutation.ps1`, or `FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1`).
- Calls `Get-QuietWorkspaceIdentity`, `Get-QuietEngine`, `Stop-QuietEngine`, `Get-QuietWorkspaceSuiteSelection` — all presumably from `Common.ps1`'s chain or the Core module, not defined here.
- Calls `Assert-CoreIntegrationEvidence.ps1` as a child script (line 145) and `Invoke-CoreProfiling.ps1` (line 151).
- Mutates `$env:PSModulePath`, `$env:QUIETCLI_TEST_SKIP_TTY`, `$env:QUIETCLI_TEST_CASE`, `$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE`, `$env:QUIETCLI_RECALL_TEST_ROOT` (lines 36–43).
- Reads several `$env:QUIETCLI_EXPECT_*` variables as pre-set expectations from the caller.

## Side effects

- Writes `status.json` continuously via `Write-WorkspaceJson` as case-by-case progress updates (many call sites, e.g. line 46, 65, 71, 76...), plus `source-identity.json`, `source-identity-final.json`, `summary.json`, and per-selected-suite `<suite>-suite.json` files, all under `$RunDirectory`.
- On any uncaught exception, writes `worker-failure.json` with message/stack/position (line 154).
- Imports modules with `-Force`, which can reload/replace already-loaded module state in the process.
- Calls `Stop-QuietEngine` unconditionally in the `finally` block (line 166), swallowing any error from it (`catch{}`), which stops whatever engine process the Core module may have started.
- `exit 1` (line 171) if the final state isn't `'Success'` — this is a hard process exit, appropriate for a background worker whose exit code is consumed by the launcher/CI.

## Findings

- BUG: Line 166, `try{Stop-QuietEngine}catch{}` silently discards *any* exception from stopping the engine, including ones that might indicate a leaked or still-running native child process. Given the repository's own emphasis elsewhere (`Wait-WorkspaceWorker` in `Common.ps1`, which explicitly notes "owned native processes may need explicit cleanup"), silently swallowing an engine-stop failure here seems inconsistent — a failed cleanup should at least increment a counter or get logged, not vanish.
- DESIGN: The function is a very large single `end` block (~140 executable lines, lines 31–173) with an `if/elseif` chain covering 10+ suite kinds (lines 61–147), each with its own project/task bookkeeping and progress-callback wiring that is nearly identical boilerplate (`$state.Project=...;$state.ProjectDirectory=...;$state.Task=...;$summary=Invoke-X ... -OnProgress {...};$summaries.Add($summary)`). This violates DRY and would benefit from extracting a small "run one named suite and record its summary" helper, especially since AGENTS.md explicitly calls out avoiding duplicated logic.
- CONVENTION: Lines 158–159 use a non-async LINQ-style loop with `Where-Object` inside a `foreach` to find matching projects for drift detection — functionally fine, but combined with the file's general synchronous style, there is no async use anywhere despite AGENTS.md's "always prefer async methods... even in sync PowerShell use `.GetAwaiter().GetResult()`" guidance. To be fair, most of the I/O in this file is delegated to `Write-WorkspaceJson` (which *does* use `.GetAwaiter().GetResult()` internally per `Common.ps1`), so the violation is more about the file's own direct file reads, e.g. `Get-Content -LiteralPath $currentStatus` patterns are not present here directly, but the module imports and `Get-Content`-less design means this file mostly delegates rather than violates — worth flagging as borderline rather than a clear violation.
- Testability: No Pester test exercises `Invoke-TestWorker.ps1` directly (unsurprising, since it's the test runner itself — testing the test-runner-of-test-runners would need a meta-test harness, which doesn't exist). Its correctness is implicitly validated by every CI run succeeding, but a targeted unit test of, say, the drift-detection logic (lines 158–160) or the `ExpectedRuntimeIdentifier`/`QUIETCLI_EXPECT_*` mismatch throws, is absent.
- No input validation on `$RepositoryConfig`'s JSON content happens in this file (it is handed to `Status.Real.Tests.ps1`'s `Invoke-QuietRealStatusIntegration` as a raw string) — acceptable layering, but worth noting the trust boundary is pushed one level down with no local sanity check (e.g. is it valid JSON, does it parse to an array) before the suite starts.

## Verdict

The script is dense but internally coherent and clearly battle-tested as the backbone of the whole companion-suite CI run; its biggest real risk is the swallowed `Stop-QuietEngine` failure in the `finally` block, which should at minimum be logged rather than silently discarded, since a leaked engine process would otherwise go unnoticed.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
