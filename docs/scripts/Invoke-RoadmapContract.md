# Invoke-RoadmapContract.ps1

The current baseline includes the execution-recipes model as well as roadmap/requirement JSON. Apply generates per-roadmap production/verification means and downstream dependencies. [Get-RoadmapExecutionPlan](Get-RoadmapExecutionPlan.md) computes the matching parallel waves; no Proposed command is invoked by either planner.

Checks the proposed planning baseline. `-Apply` regenerates only the managed delivery-contract blocks and work-item delivery references. It never provisions i3, executes a product acceptance scenario, installs a module, or publishes a package.

```powershell
$report = ./scripts/Invoke-RoadmapContract.ps1
$report.Errors
$report.ReadinessGaps
./scripts/Invoke-RoadmapContract.ps1 -Apply -WhatIf
./scripts/Invoke-RoadmapContract.ps1 -Apply
```

`WorkspaceRoot` selects the monorepo, defaulting to the script's parent. `Apply`, `WhatIf` and `Confirm` are forwarded to the reusable [contract module](lib/Roadmap.Contracts.md); business validation and writes belong to that function. The default call returns one assessment and throws on a failed PlanConsistent gate. `-Apply -WhatIf` previews writes without returning a misleading post-apply assessment. Optional `-PlanPath <explicit.md>` requires Apply and mirrors the master plan to the selected destination with absolute local links. It has no default external destination.

Dependencies: PowerShell Core 7.6+, `scripts/lib/Roadmap.Contracts.psm1`, the two canonical JSON files under `docs/requirements`, the classified ROADMAP files and the archived original plan. No native executable, engine, SDK or network is required. Code and comments are English; generated roadmap prose follows the existing French planning documents.

Side effects: explicit Apply writes UTF-8 without BOM and LF, preserving human prose outside managed blocks. Legacy requirement tables are replaced by a pointer to the generated canonical table in the delivery block. Work-item `deliverableRef` is a generated `roadmap:<family>/<kind>` reference into the canonical roadmap model. Requirement statements, ACs, owners and product evidence are preserved. An invalid model or mirror destination is refused before writes. A process crash during the multi-file update may leave stale views; the subsequent check fails and an explicit reapply repairs them. This is not a filesystem-wide transaction.

Critical review: the facade delegates common parameters without suppressing an explicit confirmation request ([source](../../scripts/Invoke-RoadmapContract.ps1)). Product ownership/versions/API decisions and campaign budgets are intentionally unresolved, so ImplementationReady is always withheld by this planning-only tool. Structural completeness is not a semantic assessment of SOLID or a claim of ISO conformity. Tests cover the reusable function and projection behavior; the facade is a thin parameter-forwarding entry point.

Verdict: suitable for checking this planning contract; not a product requirements evaluator. Run the complete [monitored tooling campaign](Invoke-RoadmapTests.md) after changes to its semantics. See the [common roadmap contract](../ROADMAP-Requirements-As-Code.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
