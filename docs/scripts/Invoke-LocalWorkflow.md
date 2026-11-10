# Invoke-LocalWorkflow.ps1

Runs a selected definition check or job with an existing verified **wrkflw 0.8.0** binary.
No installation, credentials, remote dispatch, hook or publication is implicit. `-WhatIf` performs
no native launch or report-directory creation. Execution requires an explicit `-Job` and uses Podman
unless `-Runtime docker` or `-Runtime emulation` is selected. Emulation executes host commands;
it is not a dry run. Neither Docker nor Podman is installed implicitly.

```powershell
./scripts/Invoke-LocalWorkflow.ps1 -WrkflwPath C:/tools/wrkflw.exe -Workflow .github/workflows/ci.yml
./scripts/Invoke-LocalWorkflow.ps1 -WrkflwPath C:/tools/wrkflw.exe -Mode Run -Job core -TimeoutSeconds 180
```

The Windows launcher opens the shared read-only monitor and prints its reopen command. The worker
uses the independent CI process helper, preserves the real exit code, bounds execution and saves
`status.json`, `summary.json` and `worker.*.log` under the shared temporary `local-workflows` root.
The monitor closes after the saved terminal result. The PowerShell profile is preserved.

Local results do not qualify GitHub Windows/ARM runners or ephemeral GitHub token permissions.
wrkflw 0.8.0 may reject expression-valued matrices even when GitHub accepts them. The workflow's
Podman commands also need Podman inside the chosen runner environment, beyond wrkflw's own runtime.

Parameters: `-WorkspaceRoot` defaults to the repository; `-WrkflwPath` is mandatory;
`-Workflow` defaults to `.github/workflows/core-ci.yml`; `-Mode` defaults to `Validate`.
`-Job` is mandatory in `Run` mode. `-Runtime` accepts `podman`, `docker` or `emulation`, defaulting
to `podman`. `-TimeoutSeconds` defaults to 180 (range 1–1800); `-RunDirectory` selects a new report
directory. `-Worker` is internal; use the monitored launcher. `-WhatIf` starts no process.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs one explicit local workflow operation with pinned wrkflw and the shared visible monitor.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
