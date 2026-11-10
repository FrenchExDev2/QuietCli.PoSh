# coldstart-100.profile.ps1

## Purpose

A data-only run profile that binds `Measure-ColdStart.ps1` to a fixed argument set for a quick, ~8-minute cold-start A/B measurement (100 measured pairs). It solves the problem of giving a short, repeatable benchmark configuration a stable name (`coldstart-100`) that a developer or CI step can invoke without retyping six parameter values, and that is sensitive enough to "detect differences of a few percent" (per its own `Description` field, line 5). It is created by `New-RunProfile.ps1` and consumed by `Invoke-RunProfile.ps1` (the executor named in `New-RunProfile.ps1`'s own usage example), and is directly referenced in `docs/README-readytorun_profiling.md`'s A/B testing walkthrough as the fast/iterative profile, contrasted with `coldstart-1000` as the slow/confirmatory one.

## Usage

This file is not a script with parameters; it is a PowerShell data file (`@{ ... }`) parsed in restricted language mode (per its own header comment, line 1: "Data only: parsed in restricted language mode, never executed"). Its schema:

| Key | Type | Value |
|---|---|---|
| `SchemaVersion` | `int` | `1` |
| `Name` | `string` | `'coldstart-100'` |
| `Description` | `string` | `'Cold-start A/B, 100 measured pairs (about 8 minutes): detects differences of a few percent.'` |
| `Script` | `string` | `'Measure-ColdStart.ps1'` |
| `Parameters` | `hashtable` | `BootstrapResamples=2000; Confidence=0.95; MaxFailedPairs=5; Runs=100; Seed=20261107; Warmup=5` |

```powershell
./scripts/Invoke-RunProfile.ps1 -Name coldstart-100
```

## Dependencies

- None directly — it is pure, inert data. Its *consumer*, `Invoke-RunProfile.ps1`, is what resolves `Script` against the `scripts/` directory and invokes `Measure-ColdStart.ps1` with the `Parameters` hashtable splatted in; `Invoke-RunProfile.ps1` itself was not in this review's file list.
- Transitively depends on `Measure-ColdStart.ps1` accepting exactly the parameter names listed under `Parameters` (`BootstrapResamples`, `Confidence`, `MaxFailedPairs`, `Runs`, `Seed`, `Warmup`) — if that script's parameter set changes, this profile silently becomes invalid until re-validated by `Assert-RunTargetParameters` (used in `New-RunProfile.ps1`, which is what originally wrote this file).
- `FrenchExDev2.QuietCli.Core.Tests.PoSh\RunProfiles.Tests.ps1` and `RunProfiles.Mutation.ps1` reference this file's conventions/schema (by name pattern, `coldstart-100`/`coldstart-1000`), providing indirect test coverage of the profile format this file instantiates.

## Side effects

None. This is a static data file; loading it has no side effects, and nothing in this file itself writes, deletes, or mutates anything.

## Findings

- No defects found in the file itself — it is simple, well-formed data matching its own declared schema, and its header comment correctly documents the "restricted language mode, never executed" safety property that distinguishes a run profile from an executable script (an important distinction, since a `.ps1`-extensioned data file could otherwise be mistaken for code).
- DESIGN: the fixed `Seed = 20261107` (line 12) hardcodes a specific date-like value as the random seed for both this profile and `coldstart-1000.profile.ps1`. Using the *same* seed across two profiles with different `Runs`/`Warmup`/`BootstrapResamples` values is reasonable for reproducibility within each profile's own runs, but it does mean the two profiles are not independent draws from different random streams — if `Measure-ColdStart.ps1` uses the seed in a way that makes the first N runs of the `coldstart-1000` profile a superset of the `coldstart-100` profile's runs (impossible to verify without reading `Measure-ColdStart.ps1`), that could be either a deliberate reproducibility feature or an unintended correlation; worth a one-line comment in a future edit clarifying intent.
- No hardcoded path or secret of concern — this is intentionally a self-contained, portable configuration record.
- Testability: the profile format itself is covered by `RunProfiles.Tests.ps1`/`RunProfiles.Mutation.ps1`, and `New-RunProfile.ps1`'s own validation pipeline (`Assert-RunProfile`, `Assert-RunTargetParameters`) is what guarantees a profile like this one stays valid against its target script. No gap was found specific to this instance beyond the general caveat that this file's validity depends on `Measure-ColdStart.ps1`'s parameter set remaining stable, which is not something a static data file can self-check at rest (only at the point `New-RunProfile.ps1` creates/replaces it, or when `Invoke-RunProfile.ps1` runs it).

## Verdict

Fit for purpose as-is; this is a correctly-formed, minimal configuration record with no action needed. If anything, a one-line comment explaining the shared `Seed` choice with `coldstart-1000.profile.ps1` would be a nice-to-have, not a requirement.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Provide coldstart-100.profile automation.

Boundary: **ProfileDefinition**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
