# Initialize-Workspace.ps1

## Purpose and usage

Verifies a single monorepo checkout and optionally restores checksum-pinned third-party resources. It never clones child repositories, selects a branch or compiles the product.

```powershell
./scripts/Initialize-Workspace.ps1 -Restore
```

WorkspaceRoot defaults to the script checkout. Every discovered project must have its matching manifest and no nested .git. The root may use normal Git metadata or a linked worktree's .git file.

Restore requires the existing schema-3 Monorepo lock to match the repository and every discovered project's source hashes before restoring Core resources. Without Restore, Update-WorkspaceLock refreshes that source lock instead. WhatIf returns before both paths.

## Dependencies and side effects

Loads Common and its workspace/resource helpers. Restore-CoreResources can fetch/extract verified missing resources or reuse existing ones; the default path writes repositories.lock.json. This is source/resource readiness, not NuGet compilation, test execution or hosted qualification. See [resources](../../README-resources.md).

## Critical review and verdict

`scripts/Initialize-Workspace.ps1:24` validates committed source hashes before resource preparation. Its final object currently reports Restored=false unconditionally, including successful Restore invocations. Read the resource operation's own Restored/Reused counts rather than using that summary flag to infer download activity. No code correction is included in this documentation review.



<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Verifies the monorepo structure; Restore checks committed source hashes instead of cloning child repositories, then restores Core's pinned third-party resources (see Restore-CoreResources.ps1) so a fresh clone is read...

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
