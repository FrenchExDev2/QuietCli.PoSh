# New-RunProfile.ps1

## Purpose

Creates a named, data-only "run profile" — a `<Name>.profile.ps1` file under `scripts/RunProfiles/` that binds a target script to a fixed set of default arguments (e.g. `coldstart-100` binds `Measure-ColdStart.ps1` to `Runs = 100`, `Warmup = 5`, etc.). This solves the problem of repeatable, named measurement/benchmark configurations without requiring every caller to remember and retype long argument lists. The resulting profile is later read and executed by `Invoke-RunProfile.ps1` (confirmed by `coldstart-100.profile.ps1`'s and `coldstart-1000.profile.ps1`'s own header comment: "Data only: parsed in restricted language mode, never executed", and by `Invoke-RunProfile.ps1` existing alongside it in `scripts/`). It is itself exercised by `FrenchExDev2.QuietCli.Core.Tests.PoSh\RunProfiles.Tests.ps1` and `RunProfiles.Mutation.ps1`.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Name` | `string` (positional 0) | Yes | — |
| `Script` | `string` (positional 1) | Yes | — |
| `Parameters` | `hashtable` | No | `@{}` |
| `Description` | `string` | No | `''` |
| `Directory` | `string` | No | (resolved by `Get-RunProfilePath`, presumably `scripts/RunProfiles`) |
| `ScriptDirectory` | `string` | No | (resolved by `Resolve-RunProfileTarget`, presumably `scripts/`) |
| `Force` | `switch` | No | off |
| `LogLevel` | `string` (`ValidateSet('Trace','Debug','Info','Warn','Error','Off')`) | No | `Info` |
| `LogPath` | `string` | No | none |

Supports `-WhatIf`/`-Confirm` (`SupportsShouldProcess`).

```powershell
./scripts/New-RunProfile.ps1 -Name coldstart-100 -Script Measure-ColdStart.ps1 -Parameters @{ Runs = 100; Warmup = 5 }
```

## Dependencies

- `using module ./lib/RunLog.psm1` (line 36) — structured logger (`New-RunLogger`, with `.Increment`, `.Debug`, `.Time`, `.Error`, `.Snapshot` members used at lines 52-76).
- `Import-Module (Join-Path $PSScriptRoot 'lib/RunProfileStore.psm1'), (Join-Path $PSScriptRoot 'lib/RunFormat.psm1')` (line 50) — supplies `Assert-RunProfile`, `Resolve-RunProfileTarget`, `Assert-RunTargetParameters`, `Get-RunProfilePath`, `Write-RunProfile`, and `Format-RunCounters`.
- No external process is shelled out to; this script only manipulates in-memory data and writes one PowerShell data file to disk.
- Assumes the target `-Script` already exists under `-ScriptDirectory` and exposes a `param()` block whose parameter names are a superset of the keys in `-Parameters` (enforced by `Assert-RunTargetParameters`, line 60).

## Side effects

- Writes one new (or, with `-Force`, replaced) `<Name>.profile.ps1` file under the resolved profile directory (`Write-RunProfile`, line 63), gated by `$PSCmdlet.ShouldProcess` (line 62) — this correctly supports `-WhatIf`.
- No git, network, or process side effects.
- Logs structured counters/messages via `$logger`, optionally to `-LogPath` if supplied.

## Findings

- No correctness issues were found in the control flow: validation (`Assert-RunProfile`), target resolution, and parameter-shape validation (`Assert-RunTargetParameters`) all run and throw *before* the file-write step, and the file write itself is wrapped in `ShouldProcess` — a clean, safe order of operations.
- The `try/catch/finally` (lines 53-76) correctly increments both success and failure counters and always emits a `Format-RunCounters` trailer, which is a good observability pattern consistent with the repo's logging philosophy.
- DESIGN: this script has a fairly deep but reasonable separation of concerns — validation (`RunProfileStore.psm1`), formatting (`RunFormat.psm1`), and logging (`RunLog.psm1`) all live in separate modules rather than being inlined here, which is a good example of the SOLID/modular convention the repo requires; no violation found.
- Minor observation, not a defect: `$Parameters.get_Count()` (line 57) uses the explicit .NET accessor method rather than the more idiomatic PowerShell `$Parameters.Count`; functionally identical, purely a style quirk.
- Testability: good — both an example/acceptance test (`RunProfiles.Tests.ps1`) and a dedicated mutation-testing harness (`RunProfiles.Mutation.ps1`) exist for this area, which satisfies the repo's mandatory mutation-testing expectation for this script's business logic better than most other scripts reviewed in this batch.
- No hardcoded paths/values that should be parameters were found — `Directory`, `ScriptDirectory`, and `LogPath` are all already exposed as optional parameters with sensible defaults delegated to the store module.

## Verdict

Fit for purpose as-is. This is one of the better-engineered scripts in the batch: validated inputs, `ShouldProcess`-gated writes, structured logging, and actual test + mutation coverage. No rework is required.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
