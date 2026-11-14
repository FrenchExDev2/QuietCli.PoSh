# Resource documentation gate

## Usage

`./scripts/Test-Resources.ps1 -WorkspaceRoot <root>`.

## Dependencies and effects

Check-only wrapper around Sync-ResourcesReadme. Registered as Resources in the shared workspace/commit pipeline. No resource preparation or file writes.

## Critical review and verdict

Source: [Test-Resources.ps1:1](../../scripts/Test-Resources.ps1:1). No cosmetic WhatIf parameter: this entry point is read-only. Explicit commit skips are reported as omissions.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs the source-only resource documentation gate.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
