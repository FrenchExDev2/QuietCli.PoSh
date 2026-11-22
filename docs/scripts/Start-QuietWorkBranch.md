# Start-QuietWorkBranch.ps1

<!-- script-source:begin -->
Source file: [`Start-QuietWorkBranch.ps1`](../../scripts/Start-QuietWorkBranch.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [Start-QuietWorkBranch.psm1](lib/Start-QuietWorkBranch.md). See that library for the full operation, dependencies, examples, effects and validation limits.

```powershell
./scripts/Start-QuietWorkBranch.ps1 -Kind doc -Name multi-version
```

Use `doc` for documentation branches. The other kinds are `fix`, `feature`, `chore` and `companion`. `-Branch doc/multi-version` is equivalent to the example above. The script starts from the freshly pulled delivery branch, `develop` by default, and restores pending work from a retained stash. Release branches belong to `Invoke-QuietRelease.ps1`.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptStartQuietWorkBranch`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Shelves pending work, fast-forwards the base branch and restores the shelf on a new work branch.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
