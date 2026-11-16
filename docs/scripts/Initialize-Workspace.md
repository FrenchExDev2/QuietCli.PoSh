# Initialize-Workspace.ps1

## Purpose and usage

Verifies a single monorepo checkout and optionally restores checksum-pinned third-party resources. It never clones child repositories, selects a branch or compiles the product.

```powershell
./scripts/Initialize-Workspace.ps1 -Restore
```

WorkspaceRoot defaults to the script checkout. Every discovered project must have its matching manifest and no nested .git. The root may use normal Git metadata or a linked worktree's .git file.

Restore verifies/restores Core's pinned external resources. Without Restore, this command only validates the monorepo structure and inert project manifests. Neither mode reads or generates an internal source lock. WhatIf returns before validation or restoration.

## Dependencies and side effects

Loads Common and its workspace/resource helpers. Restore-CoreResources can fetch/extract verified missing resources or reuse existing ones; the default path writes nothing. This is source/resource readiness, not NuGet compilation, test execution or hosted qualification. See [resources](../../README-resources.md) and [source identity](../README-source-identity.md).

## Critical review and verdict

`scripts/Initialize-Workspace.ps1:17` requires Git metadata and discovers project manifests without importing product code. The final Restored flag reports whether resource restoration completed; read the resource operation's own Restored/Reused counts to distinguish downloads from reuse. Missing manifests, dependency cycles and nested repositories remain failures. The commit companion verifies initialization/restoration without an internal lock and preserves external dependency files.



<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Verifies the Git monorepo structure and optionally restores Core's pinned third-party resources. Internal projects are discovered from their manifests; no committed source snapshot is required.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Initialize-Workspace.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
