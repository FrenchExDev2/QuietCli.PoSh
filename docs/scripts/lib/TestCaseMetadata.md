# TestCaseMetadata.psm1

## Companion ownership and optional registrations

Each test companion declares its own metadata in its own RootModule `.psm1`, with `PrivateData.QuietCli.TestCatalogue={Runner;Sources}` in its manifest. `Get-QuietCompanionTestInventory` reads that inert declaration and the explicitly scoped case-factory helper sources; no product code is imported. The generic parser's RunnerName/CaseSources parameters replace the earlier Core-only assumption. Source paths cannot escape the owning directory, repeat or resolve through file links. Dynamic composition is limited to the reviewed `$cases[$entry.Key]=$entry.Value` merge shape with declared helper sources; dynamic registrations remain rejected.

`EnabledWhen` supports only a literal `QUIETCLI_...=1` process-environment condition. Static validation independently matches it to the case's actual enclosing registration guard; unknown conditions, wrong flags and metadata-only hiding conditions fail. `Get-QuietActiveCaseMetadata` resolves these declarations without expression evaluation. Runtime validates the exact active catalogue before selection, catching both omissions and unexpected registrations. ProcessEnvironment is an explicit Integration dependency, distinct from a pure Unit body.

## Purpose and usage

Function-only library shared by the read-only classification gate and the Core test runner.

```powershell
Import-Module ./scripts/lib/TestCaseMetadata.psm1
$inventory = Get-QuietTestCaseInventory -Path ./FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1
Assert-QuietTestCaseMetadata -CaseNames $inventory.CaseNames -Metadata $inventory.Metadata
```

`Get-QuietTestCaseInventory` parses the single `Invoke-QuietCoreTests` function, literal `$cases['name']` registrations and the literal `$caseMetadata` hashtable. `Assert-QuietTestCaseMetadata` checks the complete runtime name list against that table. Both fail on omissions; neither assigns a fallback kind.

## Dependencies and side effects

PowerShell AST and .NET UTF-8 file reading only. Import declares and exports the shared validators/readers and active-case selector, with no output or business effects. No compiled QuietCli engine, native process, parser payload or network is required. Assertions return no success-stream output; the inventory returns only names and metadata.

## Critical review

- `scripts/lib/TestCaseMetadata.psm1`: AST `SafeGetValue` accepts only inert literal metadata. Dynamic registration and duplicate case names fail; test source is never dot-sourced or imported by the static checker.
- Kinds are exactly `Unit` and `Integration`. Unit dependencies must be empty; Integration requires a nonempty set of known dependency names. Optional native transport and independently checked EnabledWhen declarations are preserved. Unknown fields and duplicate dependencies fail.
- `FrenchExDev2.QuietCli.Core.Tests.PoSh/TestCaseMetadata.Tests.ps1` verifies generated inputs, malformed classifications and source mutations. Runtime validation occurs before case selection, including TTY exclusion.
- Static shape validation does not establish semantic test quality, purity, thread safety, transitive dependency completeness or execution success. The declarative companion registration reader is deliberately bounded; do not treat it as a general PowerShell evaluator.

## Verdict

Shared fail-closed classification with explicit scope; scheduling decisions still need an isolation review and concurrent execution evidence.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads a supported optional registration guard from the AST without evaluating environment expressions.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
