# Get-DevelopQualification.ps1

Reads GitHub PRs associated with an immutable develop Revision and successful companions-ci.yml PR runs. Uses GH_TOKEN only as an HTTP authorization header. Requires a merged PR targeting develop, exact merge commit, successful authoritative workflow run/attempt, a bounded nonexpired qualification artifact and an identical Git tree.

Returns Reused=false on missing credentials, stale/mismatched evidence or an API failure. Callers then run full qualification. The artifact is read in memory; no ZIP extraction, publication, retry or profile modification occurs. WhatIf performs no HTTP or native work.

## Critical review and verdict

scripts/Get-DevelopQualification.ps1:1 deliberately accepts only a supported original repository and bounded API pages/artifacts. API metadata establishes run success; lib/CiImpact checks receipt fields independently. Legacy receipts without Tree/tooling fields are rejected. Publication continues to require an exact current-run revision receipt; this develop optimization cannot authorize a release.

<!-- script-contract:begin -->
## Execution contract

Purpose: Finds successful merged-PR qualification for the exact develop tree; any miss requires full validation.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
