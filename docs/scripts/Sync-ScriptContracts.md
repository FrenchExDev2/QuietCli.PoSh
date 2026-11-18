# Script boilerplate and preview review generator

<!-- script-source:begin -->
Source file: [`Sync-ScriptContracts.ps1`](../../scripts/Sync-ScriptContracts.ps1)
<!-- script-source:end -->

## Usage

Check with `./scripts/Sync-ScriptContracts.ps1`; apply with `-Apply -WhatIf` or `-Apply -Confirm`.

## Dependencies and effects

Removes objective comment headers and automatic entry-point announcements from ps1 files; replaces remaining explicit objective-tagged progress with neutral progress text. Preserves existing granular guards and PlanOnly planning, adds missing executable orchestration guards, and regenerates mirrored contracts plus docs/scripts/preview-support.md. Purpose comes from comment-based help. Default mode detects drift; Apply supports WhatIf/Confirm and writes UTF-8/LF.

## Critical review and verdict

Source: [Sync-ScriptContracts.ps1:29](../../scripts/Sync-ScriptContracts.ps1:29). Whole-operation preview avoids starting workers/builds but does not simulate native effects. Review the generated diff. Existing detailed supports/guards are not rewritten. Mirrored documentation must exist first.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [ScriptReview.psm1](lib/ScriptReview.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks or removes objective boilerplate and reviews executable entry-point ShouldProcess guards.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Sync-ScriptContracts.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
