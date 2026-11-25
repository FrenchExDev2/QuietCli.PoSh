# Watch-GitHubRun.ps1

<!-- script-source:begin -->
Source file: [`Watch-GitHubRun.ps1`](../../scripts/Watch-GitHubRun.ps1)
<!-- script-source:end -->

Observe an existing GitHub Actions run by ID. The watcher reads run and job status through GitHub CLI. It uses a separate PowerShell window by default on Windows. On other platforms, it prints job-state counts and progress in the current terminal.

```powershell
./scripts/Watch-GitHubRun.ps1 -RunId 123456789 -Repository myorg/myrepo
./scripts/Watch-GitHubRun.ps1 -RunId 123456789 -Repository myorg/myrepo -InTerminal
```

| Parameter | Use |
| --- | --- |
| `-RunId` | Required GitHub Actions run ID. |
| `-Repository` | GitHub owner and repository. Defaults to `FrenchExDev2/QuietCli.PoSh`. |
| `-WorkspaceRoot` | Workspace used for diagnostic files. Defaults to the repository root. |
| `-InTerminal` | Display progress in the current terminal, including on Windows. |
| `-WhatIf` | Preview without starting the worker or creating files. |

The watcher stores reports under `artifacts/github/<run-id>-<suffix>` and waits up to one hour. It emits the recorded terminal state and fails if the run did not succeed. The separate window opens the read-only [report monitor](Watch-Tests.md); the launcher prints the command for reopening it. The terminal heartbeat reports remote job states independently of test counters.

Use [Invoke-RemoteWorkflow.ps1](Invoke-RemoteWorkflow.md) to dispatch workflows explicitly. The watcher only observes existing runs.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Monitors one explicitly selected existing GitHub run; does not dispatch, retry or cancel it.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
