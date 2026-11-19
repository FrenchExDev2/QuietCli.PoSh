# Assert-CoreIntegrationEvidence.ps1

<!-- script-source:begin -->
Source file: [`Assert-CoreIntegrationEvidence.ps1`](../../scripts/Assert-CoreIntegrationEvidence.ps1)
<!-- script-source:end -->

## Purpose

Fails closed a Core (or "All") suite CI result that lacks the full mandated fresh-session-import, import-diagnostics, and controlled-Git-status evidence — a hard qualification gate ensuring the property/fuzz/mutation evidence the repository's test strategy requires was actually produced, not merely declared present. It is invoked by `scripts/Invoke-TestWorker.ps1` (line 145, when `$selected -eq 'Core'`) and exercised directly by `src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Integration.Tests.ps1` (line 29) and `Integration.Gate.Tests.ps1` (line 9, which instead reads this file's own text as a static contract check).

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Summary` | untyped object | Yes | none |

```powershell
$summary = Invoke-QuietCoreIntegrationSuite ...
./scripts/Assert-CoreIntegrationEvidence.ps1 -Summary $summary
```

## Dependencies

- No dot-sourcing of other scripts.
- Pure in-memory assertions over `$Summary.Performance`/`$Summary.Integration` collections and their nested `Samples`/`Scenarios`/`Validation` shapes; no external tool, no file, network, or process I/O.
- Assumes the caller already ran the import/diagnostics/controlled-Git-status probes and assembled `$Summary` with the exact object shape this script expects.

## Side effects

None beyond throwing on failure. This is a pure validation gate.

## Findings

- DESIGN: the file is a dense wall of hardcoded magic numbers with no named constants or provenance comments — e.g. `$imports[0].Samples.Count -ne 14`, `.Iterations -ne 7`, `.MutantsKilled -ne 4` (line 15); `$diagnostics[0].Count -ne 10` and the `Mode -eq Import` count `-ne 3` (line 17); `$evidence.Passed -ne 8`/`Scenarios.Count -ne 8` (line 21); `$evidence.Validation.ValidCases -ne 32`/`DamagedCases -ne 448`/`Mutations.Count -ne 5` (line 34). If the underlying test suite's sampling counts ever legitimately change, this gate either breaks with no clue why, or someone "fixes" the numbers here without understanding what property they encode.
- `Set-StrictMode -Version Latest` is active (line 10), so a `$Summary` shaped slightly differently than expected (e.g. missing `GitModuleLoaded`) would raise a raw `PropertyNotFoundException` rather than one of this file's own descriptive sentinel strings (`'CoreIntegrationEvidenceMissing'`, etc.) — an inconsistent failure mode compared to the rest of the file's deliberate, named throws.
- Good: `[CmdletBinding()]` plus `$ErrorActionPreference='Stop'` and `Set-StrictMode -Version Latest` (lines 7-10) are all explicitly set, and every failure path throws a descriptive, grep-able sentinel string (e.g. `'CoreControlledScenarioMissing: '+$name`, line 24) rather than letting an assertion fail silently.
- Testability: well covered relative to most scripts in this folder — both a direct functional Pester invocation (`Integration.Tests.ps1:29`) and a static textual contract check (`Integration.Gate.Tests.ps1:9`) exist.

## Verdict

Functionally sound and comparatively well tested, but the dense block of unexplained magic numbers (lines 15, 17, 21, 34) is the single highest-priority fix: extract them into named, documented constants so a future maintainer can distinguish "required minimum" from "today's incidental snapshot."

## Mandatory fresh-process timing evidence

The gate additionally requires one FreshProcessStartup record with seven iterations and 28 retained process samples: telemetry on/off crossed with timers on/off. Every sample must have exactly one first call and three warm calls. Applicable elapsed and phase counters must be present, finite and nonnegative. Telemetry-disabled calls must not claim a storage round-trip. The producer uses owned configurations/databases, and the gate validates their creation receipt against the arm.

The common Core/All worker enforces this for selected PR and develop qualification; focused filtered development runs remain partial. Integration.Gate.Tests.ps1 covers absent arms, missing SQLite timers, negative queue duration and fictitious disabled-storage measurements. No machine-dependent timing threshold is used.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Fails closed when a Core/All CI result lacks mandatory import and Core-only controlled Git evidence.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
