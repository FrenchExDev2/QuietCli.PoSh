# Test-ScriptShouldProcess.ps1

## Purpose and usage

Read-only RaC gate: ./scripts/Test-ScriptShouldProcess.ps1 [-WorkspaceRoot <root>]. Loads ScriptShouldProcess.ps1 and applies build/script-shouldprocess.json. A new unclassified executable script fails; missing/stale exception metadata fails.

## Dependencies and side effects

Uses the PowerShell AST and checked-in policy. Does not execute inspected scripts or change files. This gate itself has a hash-bound read-only exception rather than cosmetic WhatIf/Confirm switches.

## Critical review

- scripts/Test-ScriptShouldProcess.ps1:12 delegates to one shared policy implementation.
- Reports guarded scripts, function-only libraries, reviewed read-only entry points and unqualified legacy files separately. Those counts are not proof that all side effects are guarded at runtime.
- The shared campaign tests generated contracts, a malformed corpus, no-write execution and targeted mutations. Add runtime WhatIf tests for each newly mutating entry point.

## Verdict

Blocking new-script API check in the common commit/GitHub registry; never a blanket qualification of legacy scripts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Read-only RaC gate for standard WhatIf/Confirm support on new executable PowerShell scripts.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
