# ScriptsWorker.psm1

## Purpose and usage

Shared supervised launch for [Invoke-ScriptsTests.ps1](../Invoke-ScriptsTests.md) and [Invoke-ScriptsMutation.ps1](../Invoke-ScriptsMutation.md). `Invoke-QuietScriptsSupervisedWorker -ModulePath -WorkerFunction -RequestPath -RunDirectory -WorkspaceRoot [-Headless] -TimeoutSeconds` performs these steps:
1. Starts a hidden `pwsh -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand` that sets UTF-8 console output, imports `ModulePath` and calls `<WorkerFunction> -RequestPath <RequestPath>`. The worker's stdout and stderr go to `worker.stdout.log` and `worker.stderr.log`.
2. Opens the read-only `Watch-Tests.ps1` monitor on the run directory unless `-Headless` is set.
3. Returns the summary saved by `Wait-WorkspaceWorker`, which streams the logs, enforces the deadline and records `Timeout` or `Crash` when the worker ends without a summary.

## Dependencies and side effects

Imports Common (`ConvertTo-CiArgument`, `Wait-WorkspaceWorker`). It starts the worker and, unless headless, the monitor.

## Critical review and verdict

The supervisor decodes the logs as strict UTF-8. A worker that wrote in the OEM console code page, for example a localized error message, used to stop the supervisor, so the encoding is set in the worker command itself. The command is base64-encoded, so quotes and spaces in paths cannot change the argument vector. `WorkerFunction` is validated as a plain command name. Both callers' integration tests cover this library end to end.

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs a module's worker function in a hidden UTF-8 pwsh, opens the monitor unless headless, and returns the saved summary.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
