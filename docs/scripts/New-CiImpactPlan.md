# New-CiImpactPlan.ps1

Plans CI for an immutable Base/Revision pair using the complete `git diff --no-renames --name-only -z` path set. Native orchestration uses Ci.Process, without the product engine. It writes artifacts/ci-plan/plan.json and suite/run_products/run_tooling GitHub outputs.

For pull_request, lib/CiImpact selects affected suites through declared transitive dependencies. Shared/unknown sources require All. Multiple impacted companions share one All matrix. Documentation-only PR changes avoid product runs. Reviewed run-profile command/store/definition paths select tooling only; shared profiler/encoding/report helpers and unknown paths retain All. Mixed paths union requirements. For push, Get-DevelopQualification must verify identical-tree PR evidence before product replay is removed; a miss requires All.

## Critical review and verdict

scripts/New-CiImpactPlan.ps1:1 fails on incomplete/failed diffs instead of claiming no changes. Both rename sides remain visible. WhatIf performs no native/network/filesystem work. No branch protections or publications are changed. Zero/deleted bases fail rather than silently skipping qualification; normal develop updates use an existing before commit.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [CiImpact.psm1](lib/CiImpact.md), [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

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
