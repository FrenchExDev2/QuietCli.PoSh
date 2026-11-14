# RunProfiler.psm1

## Purpose

Wraps the checksum-pinned `PSProfiler` (Profiler 4.3.0) module so run-profile tooling can profile an arbitrary PowerShell script block and export a top-50-lines/top-50-functions self-duration report as JSON. It solves the "where did the cold-start/import time go inside PowerShell code" problem: PSProfiler only sees managed PowerShell execution (native child processes show up only as the line that waits on them), so this module is the PowerShell-side half of a profiling story that is paired with a CLR-side `dotnet-trace` collector elsewhere in the repo. It is invoked by `scripts/Measure-ColdStart.ps1` (via `Invoke-RunProfiled`, when `-ProfileImport` is passed) to profile module import, and is covered directly by `FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Profiler.Tests.ps1` and the mutation catalogue in `RunProfiles.Mutation.ps1`.

## Usage

Exported functions:
- `Resolve-RunProfilerModule([string] $Path)` — optional explicit manifest path. Resolution order: `$Path` → `$env:QUIETCLI_PROFILER_MODULE` → newest `Profiler.psd1` under `%TEMP%/QuietCli2/.../profilers/pinned/Profiler/`. Throws `RunProfilerVersionMismatch` if the found manifest's `ModuleVersion` isn't exactly `4.3.0`, or `RunProfilerNotFound` if nothing resolves.
- `Convert-RunTraceRows($Rows)` — projects `Profiler.Trace` rows (`Top50SelfDuration` / `Top50FunctionSelfDuration`) into plain `pscustomobject`s with millisecond durations rounded to 3 decimals, truncating `Text` at 200 chars with an ellipsis.
- `Invoke-RunProfiled` — parameters: `-ScriptBlock` (Mandatory, `[scriptblock]`), `-OutputDirectory` (Mandatory, `[string]`), `-Label` (Mandatory, `[string]`, must match `^[A-Za-z0-9._-]{1,80}\z`), `-ProfilerModulePath` (optional, `[string]`), `-Logger` (optional, duck-typed `Info`/`Increment`). Runs the block under `Trace-Script -DisableWarning`, builds a report (`Label`, `ProfilerVersion`, `PowerShell`, `TotalMs`, `TopLinesBySelfDuration`, `TopFunctionsBySelfDuration`) and writes it to `<OutputDirectory>/<Label>.profile.json`. Returns the written path.

Example:
```powershell
Import-Module ./scripts/lib/RunProfiler.psm1
Invoke-RunProfiled -ScriptBlock { Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -Force } `
    -OutputDirectory ./artifacts/profiles -Label 'import-core'
```

## Dependencies

- Imports `RunEncoding.psm1` (sibling in `scripts/lib/`) for `Write-RunTextFile` (UTF-8 no-BOM, LF).
- Depends on the external `Profiler` PowerShell module (version pinned to 4.3.0, installed out-of-band by `scripts/Initialize-Profilers.ps1`), specifically its `Trace-Script` cmdlet and `Profiler.Trace` type.
- Reads the environment variable `QUIETCLI_PROFILER_MODULE` and probes `[IO.Path]::GetTempPath()/QuietCli2` as a filesystem convention shared with `Initialize-Profilers.ps1`/`RunToolCache.psm1`.
- `Import-PowerShellDataFile` is used to read the candidate manifest (safe, restricted-language parsing).

## Side effects

- Calls `Import-Module $manifest -Force` — mutates the current PowerShell session's loaded-module state (can reload Profiler even if an incompatible version were already loaded under a different path, though the version gate is checked before this).
- Creates `$OutputDirectory` if missing (`[IO.Directory]::CreateDirectory`).
- Writes `<Label>.profile.json` to that directory — overwrites any prior file silently (no uniqueness check, no `Force`/overwrite-guard pattern like `RunProfileStore.psm1`'s `Write-RunProfile` has).
- No network access, no git, no process spawn beyond whatever the caller's `$ScriptBlock` itself does.

## Findings

- DESIGN: `Invoke-RunProfiled` silently overwrites an existing `<Label>.profile.json` with no `-Force` switch or existence check, unlike the sibling `RunProfileStore.psm1::Write-RunProfile` which explicitly guards against overwriting profiles. This is an inconsistency within the same `lib/` folder's conventions for "write a named artifact file."
- CONVENTION: Line 91, `Trace-Script -ScriptBlock $ScriptBlock -DisableWarning 6>$null` silently discards PSProfiler's warning stream unconditionally, even when a `-Logger` is present that could have surfaced it as `Logger.Warn`. A caller debugging a `RunProfilerNoTrace` failure (thrown right after, line 93) loses PSProfiler's own diagnostic warning that might explain why no trace object came back.
- CONVENTION: `Resolve-RunProfilerModule` (lines 28-31) builds the cache-probe path with `Join-Path ([IO.Path]::GetTempPath()) 'QuietCli2'` — this hardcodes the `QuietCli2` cache directory name inline rather than sourcing it from a single shared constant; the same literal string appears independently in `RunToolCache.psm1`'s comments/callers and `Initialize-Profilers.ps1`. A rename of that cache folder requires a grep across files instead of one constant.
- No bug found in the row-projection or JSON-writing logic itself; `Convert-RunTraceRows` correctly guards `$Rows` with `@()` to tolerate `$null`/scalar input, and `[Math]::Round` usage is consistent.
- Testability: covered by `RunProfiles.Profiler.Tests.ps1` (resolution/version-mismatch paths) and by mutation cases in `RunProfiles.Mutation.ps1` targeting `RunToolCache.psm1` (the caching layer `Invoke-RunProfiled` ultimately depends on for the Profiler package itself) — no mutation entries specifically target `RunProfiler.psm1`'s own logic (e.g., the `6>$null` suppression or the `-Last 1` trace selection at line 92), which is a coverage gap for this file specifically versus its neighbors.

## Verdict

Fit for purpose for its narrow job (pinned-version PSProfiler wrapper); the highest-priority fix is making the overwrite-vs-guard behavior of `<Label>.profile.json` consistent with `RunProfileStore.psm1`'s existing pattern (add a `-Force` switch, or document the overwrite as intentional).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: PSProfiler integration: runs a script block under the pinned Profiler module and exports the hottest lines and functions.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Read-only property projections use script blocks so metadata remains available during WhatIf; mutating operations retain their existing operation guards.
