# ScriptLayout.psm1

## Purpose and exported command

`Test-QuietScriptLayout -WorkspaceRoot <checkout>` implements RAC-PS-004 for the
[read-only entry point](../Test-ScriptLayout.md). It recursively visits `scripts`, rejects
links before following directories, parses UTF-8 PowerShell syntax and aggregates violations.
It exports only `Test-QuietScriptLayout`. Import defines functions without business effects.

## Contract and dependencies

Uses the PowerShell AST, `Get-ChildItem` and `System.IO.Path`; no native executable,
product engine, external package or network dependency. The full source inventory is checked
even when the preview policy has a legacy waiver. Function definitions inside nested script
blocks and filters count as functions. Qualified `Join-Path`/`Import-Module` calls are checked.
Imports require an enabled `-DisableNameChecking` argument. `.profile.psd1` files are data
and are outside the executable naming rule, while remaining documented by the script index.

Returns `{ Check = 'ScriptLayout'; Files; State = 'Success' }`, or throws for a missing scripts
directory, parse failure or any violation. Reads only the supplied tree; does not execute it.
The convention is syntactic and cannot establish the meaning of an arbitrary verb, resolve
dynamic aliases or validate runtime side effects. The Tooling companion owns regression,
generated valid-name, malformed-source and mutation assertions.

<!-- script-contract:begin -->
## Execution contract

Purpose: Enforces RAC-PS-004 using inert PowerShell syntax trees, independently of legacy preview waivers.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
