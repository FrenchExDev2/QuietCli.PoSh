# Start-QuietWorkBranch.ps1

## Purpose and usage

Move pending work onto a new work branch based on an updated local base branch.

```powershell
./scripts/Start-QuietWorkBranch.ps1 -Branch fix/tag-administration -WhatIf
./scripts/Start-QuietWorkBranch.ps1 -Branch fix/tag-administration
```

`Branch` must be a new `fix/*` or `feature/*` branch. `WorkspaceRoot` defaults to this
checkout, `BaseBranch` to `develop`, and `Remote` to `origin`. `ShelfName` overrides
the generated Git stash message. Git still validates both branch names.

## Dependencies and side effects

Uses the checkout's built Core/Git modules and the `quiet` facade for every native
operation. WhatIf returns before imports, filesystem reads, Git calls or network access.

Pending tracked and untracked files are stashed together. The local base is switched
to and pulled with `--ff-only --no-tags`; its resulting commit must equal the remote
branch. A new work branch is created without tracking the base's upstream. The stash
is applied by object ID with `--index`, preserving staging, and is retained as a backup.
The script verifies the restored file hashes and status codes against the initial work.
It does not commit, push, open a PR, reset an existing branch or recreate tags.

## Critical review and verdict

`scripts/Start-QuietWorkBranch.ps1:24` guards all effects. The preflight at
`scripts/Start-QuietWorkBranch.ps1:53` rejects existing work branches and conflicted,
detached or unborn starting states before shelving. Native failures are not retried;
the stash is printed immediately after creation and remains available if a later step
fails. The fast-forward-only pull at `scripts/Start-QuietWorkBranch.ps1:73` and
restore conflicts require explicit resolution on failure.

The remote-base comparison is an observation, not a lock against subsequent remote
changes. Submodule worktree changes are not recursively shelved. The final byte/status
comparison intentionally fails when an automatic merge changes the shelved work;
the retained stash supplies the original. Preview execution is checked with an absent
checkout, and real transfers verify their own restored content. This is not exhaustive
qualification of every repository topology or concurrent writer.

<!-- script-contract:begin -->
## Execution contract

Purpose: Shelves pending work, fast-forwards the base branch and restores the shelf on a new work branch.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
