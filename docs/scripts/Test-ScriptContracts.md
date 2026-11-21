# Script boilerplate and full preview review gate

<!-- script-source:begin -->
Source file: [`Test-ScriptContracts.ps1`](../../scripts/Test-ScriptContracts.ps1)
<!-- script-source:end -->

## Usage

`./scripts/Test-ScriptContracts.ps1 -WorkspaceRoot <root>`.

## Dependencies and effects

Check-only wrapper around Sync-ScriptContracts. Shared registry name ScriptContracts; no normalization or generated-document writes.

## Critical review and verdict

Source: [Test-ScriptContracts.ps1:1](../../scripts/Test-ScriptContracts.ps1#L1). Static compliance does not replace runtime no-write tests. Reintroduced objective boilerplate, changed guard classifications and stale mirrored contracts fail. Regeneration is explicit.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks absent objective boilerplate and the preview-support review without applying changes.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
