# New-CiImpactPlan.ps1

Plans CI for an immutable Base/Revision pair using the complete `git diff --no-renames --name-only -z` path set. Native orchestration uses Ci.Process, without the product engine. It writes artifacts/ci-plan/plan.json and suite/run_products/run_tooling GitHub outputs.

For pull_request, lib/CiImpact selects affected suites through declared transitive dependencies. Shared/unknown sources require All. Multiple impacted companions share one All matrix. Documentation-only changes avoid product runs. For push, Get-DevelopQualification must verify identical-tree PR evidence before product replay is removed; a miss requires All.

## Critical review and verdict

scripts/New-CiImpactPlan.ps1:1 fails on incomplete/failed diffs instead of claiming no changes. Both rename sides remain visible. WhatIf performs no native/network/filesystem work. No branch protections or publications are changed. Zero/deleted bases fail rather than silently skipping qualification; normal develop updates use an existing before commit.

<!-- script-contract:begin -->
## Execution contract

Purpose: Writes a conservative PR/develop CI plan from the complete Git diff and verified same-tree PR receipts.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
