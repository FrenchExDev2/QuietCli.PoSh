# Assert-CiPlanResults.ps1

<!-- script-source:begin -->
Source file: [`Assert-CiPlanResults.ps1`](../../scripts/Assert-CiPlanResults.ps1)
<!-- script-source:end -->

## Purpose and usage

Verifies actual jobs against the selective execution plan and saves a scoped receipt behind the stable QuietCli required CI check.

```powershell
./scripts/Assert-CiPlanResults.ps1 -NeedsJson $needsJson -WhatIf
```

## Dependencies and side effects

Requires planning, source checks and layout tests. Each selected product/smoke/tooling/distribution job must succeed; unselected jobs must be skipped. Missing, failed or cancelled results reject the decision. The receipt explicitly has PublicationQualified=false.

## Critical review

- The implementation in scripts/Assert-CiPlanResults.ps1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks workflow results against the selected plan and saves a scoped receipt.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
