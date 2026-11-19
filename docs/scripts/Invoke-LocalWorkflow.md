# Invoke-LocalWorkflow.ps1

<!-- script-source:begin -->
Source file: [`Invoke-LocalWorkflow.ps1`](../../scripts/Invoke-LocalWorkflow.ps1)
<!-- script-source:end -->

Runs a selected definition check or job with an existing verified **wrkflw 0.8.0** binary.
No installation, credentials, remote dispatch, hook or publication is implicit. `-WhatIf` performs
no native launch or report-directory creation. Execution requires an explicit `-Job` and uses Podman
unless `-Runtime docker` or `-Runtime emulation` is selected. Emulation executes host commands;
it is not a dry run. Neither Docker nor Podman is installed implicitly.

```powershell
./scripts/Invoke-LocalWorkflow.ps1 -WrkflwPath C:/tools/wrkflw.exe -Workflow .github/workflows/ci.yml
./scripts/Invoke-LocalWorkflow.ps1 -WrkflwPath C:/tools/wrkflw.exe -Mode Run -Job companions -TimeoutSeconds 180
```

The Windows launcher opens the shared read-only monitor and prints its reopen command. The worker
uses the independent CI process helper, preserves the real exit code, bounds execution and saves
`status.json`, `summary.json` and `worker.*.log` under the shared temporary `local-workflows` root.
The monitor closes after the saved terminal result. The PowerShell profile is preserved.

Local results do not qualify GitHub Windows/ARM runners or ephemeral GitHub token permissions.
wrkflw 0.8.0 may reject expression-valued matrices even when GitHub accepts them. The workflow's
Podman commands also need Podman inside the chosen runner environment, beyond wrkflw's own runtime.

Parameters: `-WorkspaceRoot` defaults to the repository; `-WrkflwPath` is mandatory;
`-Workflow` defaults to `.github/workflows/companions-ci.yml`; `-Mode` defaults to `Validate`.
`-Job` is mandatory in `Run` mode. `-Runtime` accepts `podman`, `docker` or `emulation`, defaulting
to `podman`. `-TimeoutSeconds` defaults to 180 (range 1–1800); `-RunDirectory` selects a new report
directory. `-Worker` is internal; use the monitored launcher. `-WhatIf` starts no process.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs one explicit local workflow operation with pinned wrkflw and the shared visible monitor.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Invoke-LocalWorkflow.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
