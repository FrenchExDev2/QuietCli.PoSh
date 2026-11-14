# Remove-QuietTags.ps1

## Purpose and usage

Delete every local and GitHub tag in one explicitly selected checkout. The configured
remote must identify the selected GitHub repository, and the checkout root must match.

```powershell
./scripts/Remove-QuietTags.ps1 -PlanOnly
./scripts/Remove-QuietTags.ps1 -WhatIf
./scripts/Remove-QuietTags.ps1 -Confirm
```

`WorkspaceRoot` defaults to this checkout, `Repository` to `FrenchExDev2/QuietCli.PoSh`,
and `Remote` to `origin`. `ReportPath` selects a new JSON file in an existing directory;
omitting it generates a unique receipt in the system temporary directory.

## Dependencies and side effects

Uses this checkout's built Core/Git modules and the `quiet` facade for every native call.
Git reads local refs; authenticated GitHub CLI enumerates and deletes remote refs through
the GitHub REST API. No release, branch, package or source commit is deleted.
WhatIf returns before imports, native calls, network access or writes. PlanOnly reads
metadata without writing a receipt or deleting refs. Metadata collection is bounded to
2 MiB per command; malformed/incomplete metadata fails before deletion.

Real execution saves original reference/object identities before deletion, records progress,
deletes GitHub refs first, then local refs using their expected old object IDs, and requires
both inventories to be empty. A failure preserves partial progress and is never retried.
The receipt contains metadata; it is not an archive of annotated tag objects or commits.

## Critical review and verdict

`scripts/Remove-QuietTags.ps1:25` guards execution before effects and validates the remote
identity before mutations. Local expected-object deletion rejects concurrent ref changes.
The GitHub deletion loop at `scripts/Remove-QuietTags.ps1:85` uses an endpoint with no compare-and-swap guard: concurrent remote changes
between enumeration and deletion are not isolated. Final enumeration detects remaining
tags but cannot prevent a later writer from creating new ones. No protection rule is disabled.

This is an explicitly destructive administrative operation. Preview execution is tested
against an absent checkout; real execution verifies both tag inventories after deletion.
That evidence does not qualify every authentication, protection or concurrency condition.

<!-- script-contract:begin -->
## Execution contract

Purpose: Removes all local and GitHub tags from one verified checkout, preserving a metadata receipt.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
