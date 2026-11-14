# coldstart-1000.profile.psd1

## Purpose

A data-only run profile that binds `Measure-ColdStart.ps1` to a fixed argument set for a long, ~80-minute cold-start A/B measurement (1000 measured pairs), intended, per its own `Description` field (line 5), for "statistical noise elimination" — i.e. a confirmatory, high-confidence run rather than the quick iterative check that `coldstart-100.profile.psd1` provides. It is created by `New-RunProfile.ps1` and consumed by `Invoke-RunProfile.ps1`, and is the "slow, authoritative" counterpart referenced alongside `coldstart-100` in `docs/README-readytorun_profiling.md`'s A/B testing documentation.

## Usage

This file is not a script with parameters; it is a PowerShell data file (`@{ ... }`) parsed in restricted language mode (per its own header comment, line 1: "Data only: parsed in restricted language mode, never executed"). Its schema:

| Key | Type | Value |
|---|---|---|
| `SchemaVersion` | `int` | `1` |
| `Name` | `string` | `'coldstart-1000'` |
| `Description` | `string` | `'Cold-start A/B, 1000 measured pairs (about 80 minutes): statistical noise elimination.'` |
| `Script` | `string` | `'Measure-ColdStart.ps1'` |
| `Parameters` | `hashtable` | `BootstrapResamples=5000; Confidence=0.99; MaxFailedPairs=20; Runs=1000; Seed=20261107; Warmup=10` |

```powershell
./scripts/Invoke-RunProfile.ps1 -Name coldstart-1000
```

## Dependencies

- None directly — pure, inert data, structurally identical in shape to `coldstart-100.profile.psd1`. Its consumer, `Invoke-RunProfile.ps1`, resolves and invokes `Measure-ColdStart.ps1` with these parameters splatted in.
- Transitively depends on `Measure-ColdStart.ps1`'s parameter set staying compatible with `BootstrapResamples`, `Confidence`, `MaxFailedPairs`, `Runs`, `Seed`, `Warmup` — the same coupling noted for `coldstart-100.profile.psd1`.
- `FrenchExDev2.QuietCli.Core.Tests.PoSh\RunProfiles.Tests.ps1`/`RunProfiles.Mutation.ps1` provide indirect coverage of the profile format this file instantiates.

## Side effects

None. Static data file; no side effects from loading it.

## Findings

- No defects found in the file itself; it is internally consistent with `coldstart-100.profile.psd1`'s schema and the two files' parameter scaling is sensible and proportionate: `Runs` 100→1000 (10x), `BootstrapResamples` 2000→5000 (2.5x), `Confidence` 0.95→0.99 (tighter), `MaxFailedPairs` 5→20 (4x, scaling roughly with the 10x run count to keep the same tolerated *failure rate*), `Warmup` 5→10 (2x). This is coherent, deliberate parameter design, not arbitrary numbers.
- DESIGN: as noted in the `coldstart-100.profile.psd1` review, both profiles share the identical literal `Seed = 20261107` (line 12 here and in the sibling file). This duplication across two otherwise-independent data files is a minor DRY concern — if the seed were ever meant to change (e.g. to rotate benchmark randomness periodically), a maintainer must remember to update it in both places; there is no single source of truth for "the current benchmark seed" shared between the two profiles.
- No hardcoded path or secret of concern.
- Testability: same position as `coldstart-100.profile.psd1` — the profile *format* is tested (`RunProfiles.Tests.ps1`/`RunProfiles.Mutation.ps1`), but there is no test asserting that these two specific, shipped profile instances (`coldstart-100`/`coldstart-1000`) remain valid against `Measure-ColdStart.ps1`'s current parameter set. A lightweight regression test that loads each committed `.profile.psd1` file under `scripts/RunProfiles/` and runs it through `Assert-RunProfile`/`Assert-RunTargetParameters` would catch silent drift (e.g. a future rename of `Measure-ColdStart.ps1`'s `-Seed` parameter) before a developer discovers it mid-benchmark.

## Verdict

Fit for purpose as-is; the parameter scaling between the two profiles is coherent and deliberate. The only improvement worth considering — shared with `coldstart-100.profile.psd1` — is adding a small regression test that validates every committed `.profile.psd1` file against its target script's current parameter set, so drift is caught by CI rather than by a failed benchmark run.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Provide coldstart-1000.profile automation.

Boundary: **ProfileDefinition**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
