# ScriptMutators.psm1

<!-- script-source:begin -->
Source file: [`lib/ScriptMutators.psm1`](../../../scripts/lib/ScriptMutators.psm1)
<!-- script-source:end -->

## Purpose and usage

Mutators of [Invoke-ScriptsMutation.ps1](../Invoke-ScriptsMutation.md). Each mutator `<Name>` is one function `Find-QuietScriptMutant<Name> -Ast <FunctionBody>`, which emits candidates `{Mutator, StartOffset, EndOffset, Line, Column, Original, Replacement}`. `Get-QuietScriptMutatorCatalog` lists the names in application order. Adding a mutator means adding one function and its name in the catalog, and the engine does not change (open/closed).

| Export | Contract |
| --- | --- |
| `Get-QuietScriptMutatorCatalog` | `EqualityOperator`, `LogicalOperator`, `Regex`, `BooleanLiteral`, `ConditionalExpression`, `StringLiteral`, `ArrayDeclaration`, `BlockStatement`, `MethodExpression`. |
| `Test-QuietScriptMutableNode` | False for a node inside an attribute or type constraint. Parameter defaults remain mutable. |
| `New-QuietScriptMutant` | Builds a candidate from an extent and a replacement. |
| `Find-QuietScriptMutant<Name>` | One mutator. The mutations are listed in [Invoke-ScriptsMutation.md](../Invoke-ScriptsMutation.md). Operators use the operator token (`ErrorPosition`), so only the operator text is replaced. |

## Dependencies and side effects

Only the PowerShell AST types. Import is inert and nothing is written.

## Critical review and verdict

Replacements are chosen so that the mutated source still parses. `!$x` becomes `($x)`, and a removed statement leaves an empty line. The unit property test checks this on generated programs, and the engine still classifies any unparsable result as `CompileError`. `ForEach` collections are not loop conditions and are not mutated. `MethodExpression` matches method names case-sensitively, so `.startswith` is left alone.

Tests: `test/scripts/unit/lib/ScriptMutators.Tests.ps1`.

<!-- script-contract:begin -->
## Execution contract

Purpose: Returns the mutator names in application order; mutator <Name> is implemented by Find-QuietScriptMutant<Name>.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
