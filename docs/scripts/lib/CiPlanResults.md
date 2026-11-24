# CiPlanResults.psm1

<!-- script-source:begin -->
Source file: [`lib/CiPlanResults.psm1`](../../../scripts/lib/CiPlanResults.psm1)
<!-- script-source:end -->

## Purpose and usage

Checks that every actual workflow result agrees with the exact selective plan.

```powershell
Assert-QuietCiPlanResults -Needs $needs
```

## Dependencies and side effects

Planning outputs are closed boolean strings. The stable gate requires success from `plan` and `source-checks`, then success for each selected job and skipped for each unselected one.

| Job | Plan flag |
| --- | --- |
| `layout-tests` | `run_layout` |
| `products` | `run_products` |
| `smokes` | `run_smokes` |
| `tooling-only` | `run_tooling` |
| `companion-checks` | `run_companion_checks` |
| `distribution` | `run_distribution` |

`run_layout` is false only for a plan whose sole work is the script tests (see [`New-CiImpactPlan.md`](../New-CiImpactPlan.md)). `scripts-docs-check.yml` still runs every workspace check for such a change.

Failure diagnostics collect every missing prerequisite, invalid planning flag, absent job and
scope/result mismatch in deterministic order. A failed product, tooling and distribution job
therefore appear together instead of hiding behind the first rejected result. Any issue still
throws before producing a successful receipt; skipped or incomplete required work never qualifies.

Image preparation must succeed when the plan requests a cache renewal. For other plans, the aggregated check accepts an omitted execution scope with a successful or skipped result and rejects a failed or cancelled job (`CiPlanJobFailed: images`). Product and ReadyToRun consumers also require successful preparation before running.

## Critical review

- The implementation in scripts/lib/CiPlanResults.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Rejects failed, cancelled, missing or wrongly skipped jobs required by the selective plan.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
