# Measure-ColdStart.ps1

<!-- script-source:begin -->
Source file: [`Measure-ColdStart.ps1`](../../scripts/Measure-ColdStart.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point forwards explicitly bound parameters, including standard preview options. The library selects the default native workload for the current platform. [Measure-ColdStart.psm1](lib/Measure-ColdStart.md)

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptMeasureColdStart`. The library retains the original operation guards and output contract. Import alone does not run the operation.

Samples use the executable from the current PowerShell installation, including the pinned runner host in GitHub Actions. Each sample imports its selected QuietCli module in a fresh process.

<!-- script-contract:begin -->
## Execution contract

Purpose: Compares the cold-start cost of two QuietCli Core module builds with interleaved, fresh-process, paired runs.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Measure-ColdStart.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
