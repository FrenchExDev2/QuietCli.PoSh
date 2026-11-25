# Get-CompanionBuildKey.ps1

<!-- script-source:begin -->
Source file: [`Get-CompanionBuildKey.ps1`](../../scripts/Get-CompanionBuildKey.ps1)
<!-- script-source:end -->

## Purpose and usage

Computes a suite/target cache key from compiled project dependency closures and effective central package declarations.

```powershell
./scripts/Get-CompanionBuildKey.ps1 -Suite Git -RuntimeIdentifier win-x64
```

## Dependencies and side effects

Optional OutputPath appends cache_key to a GitHub output file through ShouldProcess. SmokeBatch accepts an explicit SuitesJson array. Raw package-file provenance is retained independently of effective dependency hashes.

## Critical review

- The implementation in scripts/Get-CompanionBuildKey.ps1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- script-contract:begin -->
## Execution contract

Purpose: Computes the selected suite build cache key and optionally writes a GitHub output.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
