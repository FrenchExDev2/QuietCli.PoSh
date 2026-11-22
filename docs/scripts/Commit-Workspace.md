# Commit-Workspace.ps1

<!-- script-source:begin -->
Source file: [`Commit-Workspace.ps1`](../../scripts/Commit-Workspace.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [Commit-Workspace.psm1](lib/Commit-Workspace.md). See that library for the full operation, dependencies, examples, effects and validation limits.

## Dependencies and effects

After a successful commit, the entry point writes a CI forecast to `.artifacts/plan.md` in the selected checkout and prints its path. Use `-CiPlanPath` to choose another Markdown file. The default location is ignored by Git.

```powershell
./scripts/Commit-Workspace.ps1 -Message 'Update automation' -CiPlanPath .artifacts/review.md
```

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptCommitWorkspace`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Commits the monorepo once, either staging all changes or preserving a prepared index; never pushes.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
