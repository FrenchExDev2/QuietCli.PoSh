# WorkspaceSolutions.psm1

<!-- script-source:begin -->
Source file: [`lib/WorkspaceSolutions.psm1`](../../../scripts/lib/WorkspaceSolutions.psm1)
<!-- script-source:end -->

## Purpose and usage

Builds inert global/local solution definitions from module manifests and source files.

```powershell
Get-QuietWorkspaceSolutions -WorkspaceRoot $checkout
```

## Dependencies and side effects

Only grouped workspaces generate solutions. Legacy flat manifest fixtures remain readable without creating or enforcing generated solution membership.

Multiple modules share a SolutionGroup without a one-to-one source/test constraint. Actual csproj files become Project entries; PowerShell sources and Markdown become File entries. Generated libraries and build output are excluded.

## Critical review

- The implementation in scripts/lib/WorkspaceSolutions.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
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

Purpose: Creates deterministic solution definitions from discovered modules without executing them.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
