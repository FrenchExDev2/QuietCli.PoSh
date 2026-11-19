# Update-Packages.ps1

<!-- script-source:begin -->
Source file: [`Update-Packages.ps1`](../../scripts/Update-Packages.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [Update-Packages.psm1](lib/Update-Packages.md). See that library for the full operation, dependencies, examples, effects and validation limits.

```powershell
./scripts/Update-Packages.ps1 -WhatIf                 # package x framework table, no prompt, no write
./scripts/Update-Packages.ps1                         # interactive selection, then write + restore check
./scripts/Update-Packages.ps1 -Apply                  # every compatible update, then restore check
./scripts/Update-Packages.ps1 -Apply -IncludePrerelease -ParallelMax 8
```

The manual workflow [packages-update.yml](../ci/github/script-packages-update.md) runs it with `-WhatIf` and, on request, with `-Apply`.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptUpdatePackages`. The library retains the operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks and applies NuGet updates for Directory.Packages.props per package and target framework, honoring CPM conditions.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
