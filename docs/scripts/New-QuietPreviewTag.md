# New-QuietPreviewTag.ps1

<!-- script-source:begin -->
Source file: [`New-QuietPreviewTag.ps1`](../../scripts/New-QuietPreviewTag.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [New-QuietPreviewTag.psm1](lib/New-QuietPreviewTag.md). See that library for the full operation, dependencies, examples, effects and validation limits.

The Publish parameter set accepts `-DeliveryBranch` (develop by default), and the PushTags set accepts `-PushTag` with `-Remote`/`-DeliveryBranch` to push existing local release tags. No parameter set pushes a branch. `-Module` takes exactly one module: several values or `All` fail with `PreviewTagRequiresOneModule`, and [Invoke-QuietRelease.ps1](Invoke-QuietRelease.md) releases several modules together.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptNewQuietPreviewTag`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates a local annotated timestamp preview tag or an exact module release tag.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/New-QuietPreviewTag.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
