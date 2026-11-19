# Test-ScriptsInventory.psm1

<!-- script-source:begin -->
Source file: [`lib/Test-ScriptsInventory.psm1`](../../../scripts/lib/Test-ScriptsInventory.psm1)
<!-- script-source:end -->

Implements [Test-ScriptsInventory.ps1](../Test-ScriptsInventory.md). It exports `Invoke-QuietScriptTestScriptsInventory`. Importing it defines the command without running anything.

## Purpose and usage

The check performs these steps in order:
1. Asks `Test-QuietScriptsTestsApplicable` ([ScriptsTests.psm1](ScriptsTests.md)) whether the workspace has script tests. A flat fixture returns `{Check='ScriptsInventory', Applicable=$false}` at once.
2. Reads `test/scripts/coverage.inventory.json`.
3. Inventories the exports of `scripts/lib` and their references from `test/scripts`.
4. Compares the inventory with the baseline, then prints one `Untested export: <key>` or `Stale inventory entry: <key>` line per offending key.
5. With `-UpdateBaseline` and stale entries, writes the pruned list through `Write-WorkspaceJson`, which is atomic. It never adds a key.
6. Returns `{Check='ScriptsInventory', Exports, Tested, Baselined, New, Stale, Pruned}`. Otherwise it throws `ScriptsInventoryUntested: <n>; ...`, or `ScriptsInventoryStale: <n>; ...` when stale entries were not pruned.

## Dependencies and side effects

Imports ScriptsInventory, WorkspaceJson and ScriptsTests. Its side effects are those listed for [Test-ScriptsInventory.ps1](../Test-ScriptsInventory.md).

## Critical review and verdict

A run that both prunes and finds new untested exports writes the pruned list and then fails. The legacy list shrinks, and the new exports still need a test. Tests: `test/scripts/unit/lib/Test-ScriptsInventory.Tests.ps1` runs the check on fixture workspaces under TestDrive.

<!-- script-contract:begin -->
## Execution contract

Purpose: Fails when an export of scripts/lib is referenced by no script test and is not listed in test/scripts/coverage.inventory.json, or when that list is stale.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
