# Sync-WorkspaceSolutions.ps1

<!-- script-source:begin -->
Source file: [`Sync-WorkspaceSolutions.ps1`](../../scripts/Sync-WorkspaceSolutions.ps1)
<!-- script-source:end -->

## Purpose and usage

Checks or regenerates the global solution and one local solution per declared SolutionGroup.

```powershell
./scripts/Sync-WorkspaceSolutions.ps1 -Apply -WhatIf
```

## Dependencies and side effects

Default mode fails on drift without writing. Apply writes deterministic UTF-8/LF solution XML; preview never creates directories or files.

## Critical review

- The implementation in scripts/Sync-WorkspaceSolutions.ps1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks or synchronizes generated workspace and companion solutions.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
