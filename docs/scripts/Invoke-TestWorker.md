# Invoke-TestWorker.ps1

Workers prefer the already-installed matching private SDK host when it supplies the fixture's stable runtime, then restore process PATH/DOTNET_ROOT. RunProfilesMutation skips engine cleanup as well as import, so command autoload cannot introduce a product dependency; it imports no product engine and verifies source identity without product binaries.

Tooling progress uses the same explicit Unit/Integration CI labels as product companions; no Unclassified fallback is emitted.

## Scoped CI execution

Tooling and Distribution load their independently owned catalogues and manifest-declared runners outside product All. Distribution runs all three package/architecture cases behind the single tooling build barrier. Binary identity uses Suite. RunProfiles mutation shares the configured budget with a cap of two isolated process workers. Ordered/exclusive measurements retain their barriers. Partial summaries are explicitly marked.

## Independent companion catalogues

Core, Git and Vagrant retain their own `.psm1` case metadata and manifest TestCatalogue/TestExecution declarations. The worker forwards run directories and applies Partial/Incomplete handling to every ordinary companion, not only Core. CaseWorker accepts a declared ordinary suite with an exact parent-selected filter, one internal slot and no profiler. It cannot launch All/focused tooling as a case worker. All divides the parent budget among Git/Vagrant suite slots; individual isolated cases still receive one. Each owner writes its own execution plan and classification/progress, with no central Core case list for siblings.

## Declarative Core case scheduling

Core consumes its test manifest's `PrivateData.QuietCli.TestExecution` policy and saves `core-execution-plan.json` before cases run. Only adjacent explicitly eligible cases enter a bounded process batch; Ordered/Exclusive stages preserve barriers. The same built checkout and image are reused. The CaseWorker switch is internal: it requires Core, a case filter, no profiler and MaxConcurrency one, prevents recursive case fan-out and clears inherited stop-on-first behavior so the parent can validate the exact single-case outcome. Child status reports remain available, while only the parent prints cumulative GitHub case counters.

Each child initializes its own configuration, SQLite, Recall root and reports. Host/runtime/RID and TTY scope checks remain active. The parent accepts a partial child only for the exact declared case and aggregates it into its own complete or explicitly partial result. Errors, missing/contradictory receipts and timeouts become failures. See [the scheduling library](lib/TestCaseScheduling.md) and [classification/concurrency](../README-test-classification-and-concurrency.md).

`All` executes Core first and requires complete successful integration evidence before fan-out. Other declared companions run in at most two isolated child processes through `lib/CiCompanionWorkers.psm1`, further bounded by MaxConcurrency. The exact current PSHOME, profile, RID/hosting and TTY scope are retained; each child has its own reports, database and configuration. The common build and Linux image are reused. Any failed/partial Core, failed child or missing/nonzero terminal result blocks All. Child reports remain in `companions/<Suite>` and are collected recursively by the evidence bundle.

The worker is shared by two entry points: a background process with a visible monitor for local
workstation tests, and direct execution in the current GitHub PowerShell process/container through
`Invoke-GitHubCi.ps1`. With `GITHUB_ACTIONS=true`, each ordinary companion case logs its name, state
and actual passed/failed counters while continuing to save the same progress and terminal reports.

Companion modules are imported with `-DisableNameChecking` on both ordinary suite and Recall paths. Before ordinary suites, Core.Tests is explicitly imported with the same option: Git.Tests and Vagrant.Tests declare it in `RequiredModules`, whose implicit imports do not inherit the caller's switch. The same worker serves local and GitHub runs, so their reports omit the repeated unapproved-verb warning while retaining other PowerShell warnings. The isolated companion-import regression asserts that its test-module import emits no warning.

## Purpose

This is the actual background worker that runs the companion test suites (Core, Git, Vagrant, Integration, RealStatus, Import, RunProfiles, GalleryPreview, Script, AgentInstructions, ConfigurationDelivery, Recall, etc.) in an isolated process, verifying environment/engine identity invariants before and after the run, and always persisting a terminal JSON report (`status.json`, `summary.json`) so a concurrent monitor and the launching process can observe progress and the final state. It solves the need for test execution that is simultaneously isolated (own process, own module imports, own engine), self-verifying (detects source drift during the run, mismatched runtime/engine identifiers), and observable (every state transition written atomically to disk for a separate monitor window to read). It is spawned by `Invoke-WorkspaceCi.ps1` via `Start-Process` (confirmed: `Invoke-WorkspaceCi.ps1` line 57/67–69 builds `$workerPath = Join-Path $PSScriptRoot 'Invoke-TestWorker.ps1'` and launches it hidden), which is itself called directly from `.github/workflows/ci.yml` and `.github/workflows/publish-psgallery.yml`. This script is never meant to be run by a human directly — it is the hidden half of the launcher/worker/monitor triad.

## Usage

For `.NET` automation, use the public `Invoke-DotNetTests.ps1` facade. Its shared worker
selection is `-Suite DotNet -DotNetSuite Readiness|Provisioning|Layout|Locks|All`.
The Locks campaign covers CI archive/base-image locks and source runtime pins. This branch
loads the tooling test scripts without importing the product or checking its engine identity;
it still records source identities, detects source drift and saves the shared terminal reports.
It qualifies the selected automation only, independently of native engine/image qualification.

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
- `MaxConcurrency` (`int`, `ValidateRange(1,32)`, default `min(4, processor count)`) — exported as `QUIETCLI_TEST_MAX_CONCURRENCY` for parallel-safe internal campaigns.
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
- Runs the mandatory Core integration-evidence assertion only after the Core suite itself has zero failures. A failed case therefore remains the terminal diagnostic instead of being replaced by `CoreIntegrationEvidenceMissing`.
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

## .NET tooling review

The DotNet branch in scripts/Invoke-TestWorker.ps1 dispatches Invoke-DotNetQualification before importing the product module. Its initial/final source identities omit binaries, and terminal handling does not query the engine. Offline fixtures retain independent property/fuzz/mutation counts and source hashes in dotnet-summary.json. The existing shared terminal report and crash handling remain authoritative.

<!-- script-contract:begin -->
## Execution contract

Purpose: Background worker for the companion suites; always persists a terminal report.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
