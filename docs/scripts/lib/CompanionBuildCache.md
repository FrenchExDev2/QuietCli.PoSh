# CompanionBuildCache.psm1

<!-- script-source:begin -->
Source file: [`lib/CompanionBuildCache.psm1`](../../../scripts/lib/CompanionBuildCache.psm1)
<!-- script-source:end -->

## Purpose and usage

Fingerprints selected compiled closures and validates reusable distributions.

```powershell
Get-QuietCompanionBuildKey -WorkspaceRoot $checkout -Suite Git -RuntimeIdentifier win-x64
```

## Dependencies and side effects

Cache presence is insufficient: source digests, payload hashes, configuration, RID and requested ReadyToRun slots must match. Invalidation keeps unrelated package entries outside effective package projections while retaining raw provenance.

## Critical review

- The implementation in scripts/lib/CompanionBuildCache.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- script-contract:begin -->
## Execution contract

Purpose: Computes a target-specific cache key from compiled source closures and effective package declarations.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
