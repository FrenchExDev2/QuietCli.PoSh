# Invoke-RunProfile.ps1

## Purpose

Provides a named, reusable "run profile" mechanism so that a repeatable measurement/benchmark scenario (e.g. a cold-start workload against a specific candidate module) can be invoked by a short name instead of re-typing a long parameter set every time. It solves the problem of ad hoc, hand-typed invocations of measurement/diagnostic scripts drifting out of sync between developers and CI: a profile file (`<Name>.profile.ps1`, data only) captures the target script and its default parameters once, and this launcher loads it, lets the caller override specific arguments, validates the merged set against the target script's actual declared parameters, and executes it (optionally under PSProfiler). It is invoked by `Invoke-ColdStartMatrix.ps1`/`Measure-ColdStart.ps1`-style tooling and by developers directly; the `RunProfiles/coldstart-100.profile.ps1` and `coldstart-1000.profile.ps1` files under `scripts/RunProfiles/` are its concrete data targets, and `Invoke-ColdStartGate.ps1` is a known caller in the same scripts folder.

## Usage

Parameters (two parameter sets, `Run` default and `List`):
- `Name` (`string`, mandatory, positional 0, set `Run`) — profile to run.
- `List` (`switch`, mandatory, set `List`) — lists available profiles instead of running one.
- `Arguments` (`hashtable`, optional, default `@{}`, set `Run`) — overrides applied over the profile's own parameters, e.g. `@{ CandidateModule = 'C:\x\Core.psd1' }`.
- `ProfilesDirectory` (`string`, optional, default: `scripts/RunProfiles`) — profile directory.
- `ScriptDirectory` (`string`, optional, default: `scripts/`) — directory holding target scripts.
- `LogLevel` (`string`, optional, `ValidateSet('Trace','Debug','Info','Warn','Error','Off')`, default `'Info'`) — minimum level written to console/log and forwarded to the target if it accepts a `LogLevel` parameter.
- `LogPath` (`string`, optional) — forwarded to the target if it accepts `LogPath`.
- `Profiler` (`switch`, optional, set `Run`) — runs the target under PSProfiler, writing a top-50 JSON report.
- `ProfilerModulePath` (`string`, optional, set `Run`) — pinned Profiler manifest; auto-discovered from the QuietCli2 cache if omitted.
- `ProfilerOutputDirectory` (`string`, optional, set `Run`) — directory for the profiler JSON; defaults to a timestamped temp folder.

Also supports `-WhatIf`/`-Confirm` via `SupportsShouldProcess` (line 45) — running is gated by `$PSCmdlet.ShouldProcess` (line 95).

Example (from its own `.EXAMPLE`, line 42):
```powershell
./scripts/Invoke-RunProfile.ps1 coldstart-100 -Arguments @{ CandidateModule = 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh.psd1' }
```

## Dependencies

- `using module ./lib/RunLog.psm1` (line 44) plus `Import-Module` of `RunFormat`, `RunProfileStore`, `RunProfiler` from `lib/` (line 59).
- Calls into `lib/RunProfileStore.psm1` functions: `Get-RunProfileNames`, `Get-RunProfilePath`, `Read-RunProfile`, `Resolve-RunProfileTarget`, `Merge-RunProfileArguments`, `Assert-RunTargetParameters`, `ConvertTo-RunProfileLiteral` (none of these are defined in this file itself — all externally sourced, not shown here).
- Calls `Invoke-RunProfiled` from `lib/RunProfiler.psm1` when `-Profiler` is used.
- Dynamically invokes the resolved target script via `& $target @parameters` (line 106) — i.e. it shells into another PowerShell script, not a native executable.
- No direct native/external-tool shelling (git/dotnet/docker) in this file; that lives in whatever target profile is selected.

## Side effects

- Writes log lines to stderr (via `ConsoleLogSink` in `RunLog.psm1`) and optionally to a file if `-LogPath` is given.
- When `-Profiler` is used and no `-ProfilerOutputDirectory` is given, creates a directory under the OS temp path (line 99) and writes a JSON profiler report there.
- Whatever side effects the invoked target profile/script itself has (file writes, process launches, etc.) — this script is a pass-through launcher and does not sandbox or limit them.
- `exit`/`throw` on failure (line 110–113) re-throws after logging and counter bookkeeping.

## Findings

- DESIGN: `$profile` (line 81) shadows the PowerShell automatic variable `$profile` (the user's profile script path). While scoped to the `end` block and not fatal, reusing a well-known automatic-variable name as a local variable is a readability hazard and a potential source of confusion if any later code or a future edit assumes `$profile` still refers to the PowerShell profile path.
- DESIGN: Error handling in the `List` branch (line 72) uses `catch { $logger.Warn(...); $logger.Increment('profile.invalid') }` to skip a malformed profile and continue — reasonable for a listing operation, but it means a broken profile file silently drops out of the list rather than being surfaced as an actionable error; a user scanning `-List` output has no way to tell "no profiles of that kind exist" apart from "one profile is broken and hidden."
- CONVENTION: Matches the repository's async/`.GetAwaiter().GetResult()` convention correctly in the modules it depends on (e.g. `RunEncoding.psm1`), but this file itself does no I/O directly so the convention isn't directly exercised here — no violation, just worth noting it inherits compliance rather than demonstrating it.
- Testability: `RunProfiles.Tests.ps1`, `RunProfiles.Mutation.ps1`, and `RunProfiles.Benchmark.Tests.ps1` / `RunProfiles.Profiler.Tests.ps1` exist under `FrenchExDev2.QuietCli.Core.Tests.PoSh/` and reference this tooling area, so this is one of the better-covered scripts in the set — property/mutation testing appears to exist for the run-profile subsystem, in line with AGENTS.md's mandatory strategy.
- No input validation is performed on `-Name` beyond what `Get-RunProfilePath`/`Read-RunProfile` enforce downstream (not shown in this file); this script trusts those lower-level functions entirely, which is reasonable layering (SOLID: parsing/validation delegated to a focused module) rather than a smell.
- Genuine scrutiny found no outright bug in the control flow: the `ShouldProcess` gate, parameter-forwarding logic (lines 87–92), and finally-block counter reporting are all internally consistent.

## Verdict

This is a well-factored orchestrator that correctly delegates parsing/validation/execution concerns to sibling `lib/` modules and already has meaningful test coverage (regular, mutation, and benchmark suites) — fit for purpose as-is. The one worth fixing is the `$profile` variable-name shadowing (line 81), which should be renamed (e.g. `$runProfile`) to avoid confusion with the PowerShell automatic variable.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
