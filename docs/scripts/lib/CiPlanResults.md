# CiPlanResults.psm1

## Purpose and usage

Checks that every actual workflow result agrees with the exact selective plan.

```powershell
Assert-QuietCiPlanResults -Needs $needs
```

## Dependencies and side effects

Planning outputs are closed boolean strings. The stable gate requires success for selected jobs and skipped for unselected jobs, while preserving source and layout checks independently of expensive product campaigns.

Failure diagnostics collect every missing prerequisite, invalid planning flag, absent job and
scope/result mismatch in deterministic order. A failed product, tooling and distribution job
therefore appear together instead of hiding behind the first rejected result. Any issue still
throws before producing a successful receipt; skipped or incomplete required work never qualifies.

A job outside the plan's selection, such as the develop image warm-up `images` of companions-ci.yml (skipped on pull requests), may succeed or be skipped. A failed or cancelled one is still rejected (`CiPlanJobFailed: images`).

## Critical review

- The implementation in scripts/lib/CiPlanResults.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Rejects failed, cancelled, missing or wrongly skipped jobs required by the selective plan.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
