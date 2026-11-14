# Resource documentation generator

## Usage

`./scripts/Sync-ResourcesReadme.ps1` checks; `-Apply -WhatIf` previews; `-Apply -Confirm` regenerates.

## Dependencies and effects

Writes only docs/resources/README.md after ShouldProcess. Default drift fails with ResourcesReadmeStale. Uses ResourceDocumentation.ps1; no resource downloads.

## Critical review and verdict

Source: [Sync-ResourcesReadme.ps1:23](../../scripts/Sync-ResourcesReadme.ps1:23). A source-only inventory cannot prove binary readiness. Hashes of dependency readers/writers intentionally make their changes invalidate the document.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [ResourceDocumentation.psm1](lib/ResourceDocumentation.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks or regenerates docs/resources/README.md from resource locks and source references.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
