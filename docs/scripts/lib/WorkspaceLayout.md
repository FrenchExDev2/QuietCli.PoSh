# WorkspaceLayout.psm1

<!-- script-source:begin -->
Source file: [`lib/WorkspaceLayout.psm1`](../../../scripts/lib/WorkspaceLayout.psm1)
<!-- script-source:end -->

## Purpose and usage

Resolves module identities independently of grouped physical paths and provides explicit migration helpers.

```powershell
Import-Module ./scripts/lib/WorkspaceLayout.psm1 -DisableNameChecking
```

## Dependencies and side effects

The conventional grouped path is resolved before a bounded catalogue scan; isolated flat fixtures remain supported. A grouped module path can resolve to an existing flat module in such a fixture; an existing grouped directory always retains its explicit location. Module identities are globally unique. Migration helpers support ShouldProcess and reject destination collisions and workspace escapes.

## Critical review

- The implementation in scripts/lib/WorkspaceLayout.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
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

Purpose: Resolves a module identity or its child path in a grouped checkout or an isolated legacy fixture.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 2.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
