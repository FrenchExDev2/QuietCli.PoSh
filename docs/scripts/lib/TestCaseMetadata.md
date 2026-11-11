# TestCaseMetadata.psm1

## Purpose and usage

Function-only library shared by the read-only classification gate and the Core test runner.

```powershell
Import-Module ./scripts/lib/TestCaseMetadata.psm1
$inventory = Get-QuietTestCaseInventory -Path ./FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1
Assert-QuietTestCaseMetadata -CaseNames $inventory.CaseNames -Metadata $inventory.Metadata
```

`Get-QuietTestCaseInventory` parses the single `Invoke-QuietCoreTests` function, literal `$cases['name']` registrations and the literal `$caseMetadata` hashtable. `Assert-QuietTestCaseMetadata` checks the complete runtime name list against that table. Both fail on omissions; neither assigns a fallback kind.

## Dependencies and side effects

PowerShell AST and .NET UTF-8 file reading only. Import declares and exports two functions, with no output or business effects. No compiled QuietCli engine, native process, parser payload or network is required. Assertions return no success-stream output; the inventory returns only names and metadata.

## Critical review

- `scripts/lib/TestCaseMetadata.psm1`: AST `SafeGetValue` accepts only inert literal metadata. Dynamic registration and duplicate case names fail; test source is never dot-sourced or imported by the static checker.
- Kinds are exactly `Unit` and `Integration`. Unit dependencies must be empty; Integration requires a nonempty set of known dependency names. Optional native transport declarations are preserved. Unknown fields and duplicate dependencies fail.
- `FrenchExDev2.QuietCli.Core.Tests.PoSh/TestCaseMetadata.Tests.ps1` verifies generated inputs, malformed classifications and source mutations. Runtime validation occurs before case selection, including TTY exclusion.
- Static shape validation does not establish semantic test quality, purity, thread safety, transitive dependency completeness or execution success. The Core-specific registration reader is deliberately bounded; do not treat it as a general PowerShell evaluator.

## Verdict

Shared fail-closed classification with explicit scope; scheduling decisions still need an isolation review and concurrent execution evidence.

<!-- script-contract:begin -->
## Execution contract

Purpose: Rejects incomplete or contradictory test classifications before selection or execution.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
