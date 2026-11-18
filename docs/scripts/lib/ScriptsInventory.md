# ScriptsInventory.psm1

<!-- script-source:begin -->
Source file: [`lib/ScriptsInventory.psm1`](../../../scripts/lib/ScriptsInventory.psm1)
<!-- script-source:end -->

## Purpose and usage

Pure functions behind [Test-ScriptsInventory.ps1](../Test-ScriptsInventory.md). Importing the module has no side effect. Nothing here starts a process or writes a file.

| Export | Contract |
| --- | --- |
| `Get-QuietScriptsLibraryExports` | Parses each `lib/*.psm1` (top level only, file-name order) and returns `{Key, Library, Name}` per name of its single `Export-ModuleMember -Function` list, in declaration order. Names must be literal `Verb-Noun` strings. Errors: `ScriptsInventoryPathInvalid: scripts-root`, and `ScriptsInventoryExportsInvalid: lib/<File> <reason>`, where the reason is `does not parse`, `has <n> Export-ModuleMember`, `exports no -Function list` or `exports <text>` (a wildcard, variable, array expression or malformed name). |
| `Get-QuietScriptsTestInventory` | Adds `Tests` to each export: the `*.Tests.ps1` paths under the tests root, relative and with `/`, whose text names the export as a whole word (case-insensitive, not preceded or followed by a letter, digit, `_` or `-`). Error: `ScriptsInventoryPathInvalid: tests-root`. |
| `Read-QuietScriptsTestInventoryBaseline` | Reads strict UTF-8 JSON `{SchemaVersion: 1, Untested: [...]}` with exactly these two keys. Errors: `ScriptsInventoryBaselineMissing`, and `ScriptsInventoryBaselineInvalid: <reason>`, where the reason is `syntax`, `shape`, `key` (not `lib/<File>.psm1::<Verb-Noun>`) or `order` (unsorted or duplicated). |
| `Compare-QuietScriptsTestInventory` | Returns `{Passed, Exports, Tested, Baselined, New, Stale, Pruned}`. `New` lists the untested exports that are missing from the baseline, sorted. `Stale` lists the baseline keys that are now tested or no longer exported, in baseline order. `Pruned` is the baseline restricted to the keys that are still untested, so it never gains a key. Keys compare ordinally. |

## Dependencies and side effects

Only the PowerShell parser, `ConvertFrom-Json` and .NET file reads.

## Critical review and verdict

Requiring a single literal export list keeps the inventory exact. A module that computes its exports would make the ratchet unverifiable, so it is rejected instead of skipped. The reference scan is a textual proxy, and line coverage and mutation complement it (see [the check](../Test-ScriptsInventory.md)).

Tests: `test/scripts/unit/lib/ScriptsInventory.Tests.ps1` checks:
- discovery order over generated modules, with non-module and nested files ignored;
- ten rejection cases and fuzzed module text, where only typed errors are allowed;
- reference matching against a token oracle, plus a table of boundary cases;
- a baseline round-trip and seventeen rejection cases, plus fuzzed documents;
- the comparison property against an oracle: `New`, `Stale`, `Pruned` ⊆ baseline, and counts.

<!-- script-contract:begin -->
## Execution contract

Purpose: Returns {Key, Library, Name} for every function a scripts/lib module exports through its single literal Export-ModuleMember.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
