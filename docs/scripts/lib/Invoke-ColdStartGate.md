# Invoke-ColdStartGate.psm1

<!-- script-source:begin -->
Source file: [`lib/Invoke-ColdStartGate.psm1`](../../../scripts/lib/Invoke-ColdStartGate.psm1)
<!-- script-source:end -->

Implements [Invoke-ColdStartGate.ps1](../Invoke-ColdStartGate.md). Exports only "Invoke-QuietScriptInvokeColdStartGate". Imported without name checking; import defines the command without running the operation.

# Invoke-ColdStartGate.ps1

## Purpose

Runs paired cold-start A/B. The default local mode checks a fresh per-machine and per-profile A/A control
before the comparison. `-SkipAaControl` runs the same A/B profile directly and leaves the cached A/A data
untouched. GitHub ReadyToRun jobs use direct A/B by default. The local Windows matrix and Linux container
worker call the script entry point.

## Usage

Parameters

- `-CandidateModule` (string, **mandatory**) — module manifest of the compared build.
- `-CandidateLabel` (string, optional, `[ValidateNotNullOrEmpty()]`, default `'candidate'`) — display name of the compared build.
- `-BaselineModule` (string, optional, default `<repo>/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1`) — reference build, used as both sides of the A/A control and as the A/B baseline.
- `-ProfileName` (string, optional, `[ValidateNotNullOrEmpty()]`, default `'coldstart-100'`) — run profile for both A/A and A/B.
- `-ArtifactsDirectory` (string, optional, default `<repo>/artifacts/coldstart`) — per-machine A/A cache and every A/B result; must stay git-ignored.
- `-MaxAgeDays` (int, optional, `[ValidateRange(1,365)]`, default `14`) — cached A/A staleness threshold.
- `-Force` (switch, optional) — remeasures the A/A control even if fresh and clean.
- `-SkipAaControl` (switch, optional) — runs direct A/B without checking or measuring A/A.
- `-Arguments` (hashtable, optional, default `@{}`) — extra overrides forwarded to both runs; must not set `CandidateModule`/`CandidateLabel`/`OutputPath`.
- `-MeasurePackageSize` (switch, optional) — convenience flag forwarding `MeasurePackageSize=$true` via `-Arguments`, for contexts where a hashtable literal can't be passed (e.g. `pwsh -File` from a container).
- `-LogLevel` (string, optional, `[ValidateSet('Trace','Debug','Info','Warn','Error','Off')]`, default `'Info'`).
- `-LogPath` (string, optional) — optional log file.

The default command runs the A/A control first.

```powershell
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh\FrenchExDev2.QuietCli.Core.PoSh.psd1' -CandidateLabel readytorun
```

## Dependencies

- Uses `RunLog.psm1` for logging and imports `RunEncoding.psm1` and `RunFormat.psm1` for file reading and reporting.
- Delegates both measurement modes to `Invoke-RunProfile.ps1` and then `Measure-ColdStart.ps1`. A/A adds one
  profile execution when enabled and the cache needs a refresh.
- Reads/writes JSON artifacts under `-ArtifactsDirectory`.
- No native tool (git/docker/dotnet) invoked directly in this file; relies entirely on `Invoke-RunProfile.ps1`.

## Side effects

- Creates `-ArtifactsDirectory` when needed and writes a timestamped A/B result `ab-<profile>-<label>-<stamp>.json`.
- When A/A is enabled, caches its report as `aa-<profile>-<machine>.json`. Any phase with a verdict other than
  `inconclusive` stops the gated comparison with `ColdStartNoiseFloorUnstable`.
- Logs via `$logger` to console and optionally `-LogPath`.

## Findings

- `scripts/lib/Invoke-ColdStartGate.psm1:151` selects the control path and always supplies the selected baseline on both sides of A/A. The direct path never reads the control cache.
- The cache is keyed by machine name and profile. Share an artifacts directory only between runs intended to reuse that control.
- Pester fixtures check both paths, propagation of A/B failures and no-write preview. Hosted execution remains separate evidence.

## Verdict

Direct comparison and gated calibration share the same A/B profile and report format.

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs a cold-start A/B comparison with an optional A/A control.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/Invoke-ColdStartGate.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
