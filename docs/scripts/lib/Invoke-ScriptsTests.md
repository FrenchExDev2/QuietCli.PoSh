# Invoke-ScriptsTests.psm1

<!-- script-source:begin -->
Source file: [`lib/Invoke-ScriptsTests.psm1`](../../../scripts/lib/Invoke-ScriptsTests.psm1)
<!-- script-source:end -->

Implements [Invoke-ScriptsTests.ps1](../Invoke-ScriptsTests.md). It exports `Invoke-QuietScriptInvokeScriptsTests` (launcher) and `Invoke-QuietScriptsTestWorker` (worker body). Import defines both commands without running anything.

## Purpose and usage

The launcher performs these steps in order:
1. Validates the plan, the coverage targets and the monitor platform before any effect.
2. Prepares the pinned Pester through `Initialize-QuietTestTools`.
3. Creates a new run directory.
4. Writes `request.json` (plan, seed, roots, pinned module path and Pester configuration).
5. Hands the worker to [ScriptsWorker.psm1](ScriptsWorker.md). It starts a hidden UTF-8 `pwsh` worker with redirected `worker.stdout.log` and `worker.stderr.log`, opens the visible monitor unless `-Headless` is set, and supervises the worker through `Wait-WorkspaceWorker`.

It returns `{State, Passed, Failed, Partial, Seed, RunDirectory, Report, Incomplete, ExitCode}`.

The worker performs these steps:
1. Writes the `Running` status.
2. Sets `QUIETCLI_TEST_SEED`, `QUIETCLI_SCRIPTS_ROOT` and `QUIETCLI_WORKSPACE_ROOT`.
3. Imports Pester globally from its pinned path and requires exactly one loaded instance, version 6.2.0 (`ScriptsTestPesterVersionMismatch` otherwise).
4. Runs one `Invoke-Pester` from an empty dynamic module, not from this module.
5. Saves `report.json`, the terminal `status.json` and `summary.json`.

An exception becomes a `Crash` status. A timeout or a missing summary is recorded by `Wait-WorkspaceWorker` as `Timeout` or `Crash`.

## Dependencies and side effects

Imports ScriptsTests, RunToolCache, WorkspaceJson, ReportPaths and ScriptsWorker. Its side effects are those listed for [Invoke-ScriptsTests.ps1](../Invoke-ScriptsTests.md): the tool cache, the run directory, and the worker and monitor processes. The environment variables are set only inside the worker.

## Critical review and verdict

The worker command is passed as `-EncodedCommand` by ScriptsWorker, so paths with quotes or spaces cannot change the argument vector.

Pester runs the test files in its caller's session state. Called from this module, the trusted `ScriptsTests.psm1` imported here would shadow the copy the tests import from `QUIETCLI_SCRIPTS_ROOT`, and every mutant of that library would survive. The empty dynamic module's command lookup falls through to the global scope, so the tests see what they import. Pester is imported globally so that `Describe` in that scope resolves to the pinned instance instead of autoloading another Pester from `PSModulePath`, which would start a second, nested run. The integration test asserts both points: the copy is resolved and exactly one Pester is loaded.

The integration test drives the real entry point in a child process against fixture suites, so this library is covered end to end rather than by line coverage.

<!-- script-contract:begin -->
## Execution contract

Purpose: Plans, launches and supervises one scripts test run; returns its outcome and exit code.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
