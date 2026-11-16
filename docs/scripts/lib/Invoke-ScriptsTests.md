# Invoke-ScriptsTests.psm1

Implements [Invoke-ScriptsTests.ps1](../Invoke-ScriptsTests.md). It exports `Invoke-QuietScriptInvokeScriptsTests` (launcher) and `Invoke-QuietScriptsTestWorker` (worker body). Import defines both commands without running anything.

## Purpose and usage

The launcher performs these steps in order:
1. Validates the plan, the coverage targets and the monitor platform before any effect.
2. Prepares the pinned Pester through `Initialize-QuietTestTools`.
3. Creates a new run directory.
4. Writes `request.json` (plan, seed, roots, pinned module path and Pester configuration).
5. Starts a hidden `pwsh -NoProfile -NonInteractive -EncodedCommand` worker with redirected `worker.stdout.log` and `worker.stderr.log`.
6. Opens the visible monitor unless `-Headless` is set.
7. Supervises the worker through `Wait-WorkspaceWorker`.

It returns `{State, Passed, Failed, Partial, Seed, RunDirectory, Report, Incomplete, ExitCode}`.

The worker performs these steps:
1. Writes the `Running` status.
2. Sets `QUIETCLI_TEST_SEED`, `QUIETCLI_SCRIPTS_ROOT` and `QUIETCLI_WORKSPACE_ROOT`.
3. Imports Pester from its pinned path and requires exactly version 6.2.0 (`ScriptsTestPesterVersionMismatch` otherwise).
4. Runs one `Invoke-Pester`.
5. Saves `report.json`, the terminal `status.json` and `summary.json`.

An exception becomes a `Crash` status. A timeout or a missing summary is recorded by `Wait-WorkspaceWorker` as `Timeout` or `Crash`.

## Dependencies and side effects

Imports ScriptsTests, RunToolCache, WorkspaceJson, ReportPaths and, at run time, Common. Its side effects are those listed for [Invoke-ScriptsTests.ps1](../Invoke-ScriptsTests.md): the tool cache, the run directory, and the worker and monitor processes. The environment variables are set only inside the worker.

## Critical review and verdict

The worker command is passed as `-EncodedCommand`, so paths with quotes or spaces cannot change the argument vector. The integration test drives the real entry point in a child process against fixture suites, so this library is covered end to end rather than by line coverage.

<!-- script-contract:begin -->
## Execution contract

Purpose: Plans, launches and supervises one scripts test run; returns its outcome and exit code.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
