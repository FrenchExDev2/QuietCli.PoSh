# Remove-QuietMergedBranches.ps1

<!-- script-source:begin -->
Source file: [`Remove-QuietMergedBranches.ps1`](../../scripts/Remove-QuietMergedBranches.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [Remove-QuietMergedBranches.psm1](lib/Remove-QuietMergedBranches.md). See that library for the full operation, dependencies, examples, effects and validation limits.

```powershell
./scripts/Remove-QuietMergedBranches.ps1 -PlanOnly
./scripts/Remove-QuietMergedBranches.ps1
```

A local branch is deleted only when the latest pull request merged from it into `develop` on GitHub contains its tip. Squash merges are therefore recognized, and a branch with unpushed commits is kept. Checked-out and protected branches are always kept. Remote branches are never touched. Each deletion prints the `git branch <name> <oid>` command that restores it.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptRemoveQuietMergedBranches`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Deletes the local branches whose pull request was merged into develop on GitHub, and lists the branches it keeps.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
