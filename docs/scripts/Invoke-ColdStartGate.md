# Invoke-ColdStartGate.ps1

<!-- script-source:begin -->
Source file: [`Invoke-ColdStartGate.ps1`](../../scripts/Invoke-ColdStartGate.ps1)
<!-- script-source:end -->

## Purpose and usage

Runs a paired cold-start comparison. Pass `-SkipAaControl` for direct A/B. The default validates a cached or
new A/A control first. The entry point forwards the parameters and preview options to
[Invoke-ColdStartGate.psm1](lib/Invoke-ColdStartGate.md).

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptInvokeColdStartGate`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs a cold-start A/B comparison with an optional A/A control.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Invoke-ColdStartGate.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
