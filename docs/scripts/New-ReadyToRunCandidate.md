# New-ReadyToRunCandidate.ps1

<!-- script-source:begin -->
Source file: [`New-ReadyToRunCandidate.ps1`](../../scripts/New-ReadyToRunCandidate.ps1)
<!-- script-source:end -->

## Purpose and usage

Creates a separate Core module with .NET 10 and .NET 11 ReadyToRun engines for the cold-start comparison.

```powershell
$candidate=./scripts/New-ReadyToRunCandidate.ps1 -CandidateRoot <new-owned-directory> -RuntimeIdentifier linux-arm64
```

WorkspaceRoot defaults to the repository root. CandidateRoot defaults to the temporary quietcli-r2r-candidate path and must not already exist. RuntimeIdentifier defaults to the actual host RID, including musl/ARM64. Configuration defaults to Release. The result is the candidate module manifest path.

## Dependencies and side effects

Requires the pinned SDK/runtime packs and an already-built baseline. Copies Core at its relative workspace path together with `global.json`, `Directory.Build.props` and `Directory.Packages.props`. Publishes and verifies ReadyToRun in `lib/inprocess/<rid>` and `lib/engine/<rid>`, and marks the selected RID in both candidate manifests. The Core copy preserves the compiler policy and is built independently of the workspace solution.

## Critical review

- `scripts/New-ReadyToRunCandidate.ps1:45` rejects existing destinations and workspace overlap rather than recursively deleting arbitrary paths. Choose a fresh owned destination for each attempt.
- Each RID-specific receipt records the architecture and verified ReadyToRun format. The hosted footprint measures the selected engine; whole-package footprint includes unused binaries.
- The workflow builds an IL baseline first and supplies a fresh RUNNER_TEMP directory.
- Compilation and architecture checks do not establish a speedup. The A/A noise floor and A/B results remain informational on shared runners.

## Verdict

Dedicated manual experiment input. Production GitHub R2R builds use Build-Workspace.ps1 instead.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds a ReadyToRun copy of FrenchExDev2.QuietCli.Core.PoSh for cold-start A/B profiling.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/New-ReadyToRunCandidate.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
