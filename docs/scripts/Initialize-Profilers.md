# Initialize-Profilers.ps1

## Purpose

Downloads and verifies two checksum-pinned diagnostic tools — a PowerShell line profiler and a CLR
`dotnet-trace` collector — into an isolated cache directory, without installing them globally on the
machine. It exists so the profiling pipeline (`Invoke-CoreProfiling.ps1`, `Invoke-ClrCollector.ps1`) can
rely on exact, reproducible tool versions instead of whatever happens to be on `PATH`. It is invoked by
`Invoke-ContainerWorker.ps1` (line 41, when `-Profiler` is passed and no explicit
`-ProfilerModulePath`/`-ClrProfilerPath` is supplied) to prepare the host-side pinned tool cache before it
is copied into the container.

## Usage

Parameters:
- `-OutputDirectory` (string, **mandatory**) — dedicated cache directory for the two packages and their extraction receipts.
- `-Offline` (switch, optional, default `$false`) — verifies and extracts already-cached pinned archives without any network access; fails on a cache miss instead of downloading.

Example:
```powershell
./scripts/Initialize-Profilers.ps1 -OutputDirectory (Join-Path $WorkspaceRoot 'artifacts/profilers/pinned')
```

## Dependencies

- Imports `lib/RunToolCache.psm1` (`Join-Path $PSScriptRoot 'lib/RunToolCache.psm1'`), which supplies `Initialize-RunToolCache` and `Get-RunProfilerPackages` — all actual download/verification/extraction logic lives there, this script is a thin parameter-forwarding wrapper.
- Implicitly depends on network access (when not `-Offline`) to fetch the pinned packages; the exact source (NuGet/GitHub/etc.) is opaque from this file and lives in `RunToolCache.psm1`.
- Assumes `$PSScriptRoot/lib/RunToolCache.psm1` exists and exports both functions used.

## Side effects

- Creates/writes files under `-OutputDirectory` (pinned tool binaries and extraction receipts).
- May perform outbound network requests unless `-Offline` is set.
- No git state, no process spawning visible in this file (delegated entirely to the imported module).

## Findings

- DESIGN: The script has essentially no logic of its own — it is a 4-line wrapper. This is fine as a thin CLI entry point (SOLID: single responsibility delegated to `RunToolCache.psm1`), but it also means this file cannot be reviewed in isolation for correctness; all the real behavior (checksum pinning, retry, offline cache-miss handling) is invisible here and was not read in this review pass since it's outside the listed scope.
- CONVENTION: No explicit UTF-8 enforcement in this file, but since it does no text I/O itself (delegates to the module) this is likely not a violation in practice — would need to verify `RunToolCache.psm1` separately.
- Missing input validation: `-OutputDirectory` is `[string]` with no `[ValidateNotNullOrEmpty()]` or path-shape validation; an empty string would be forwarded to `Initialize-RunToolCache` and fail deeper in the stack with a less specific error than if validated here.
- No companion Pester test was found anywhere in the repo for this script by name (`Initialize-Profilers`); there is no `*.Tests.ps1` referencing it. Given it only orchestrates a cache module, test coverage would more naturally live against `RunToolCache.psm1` itself, but no such test was found either in the scope searched.
- No findings of outright bugs: the script is short, uses `$ErrorActionPreference='Stop'`, and the parameter contract documented in the comment-based help matches the actual `param()` block.

## Verdict

Fit for purpose as a thin wrapper; its correctness is entirely delegated to and dependent on `lib/RunToolCache.psm1`, which should be reviewed and tested directly. Highest-priority fix: add `[ValidateNotNullOrEmpty()]` to `-OutputDirectory` and confirm/create test coverage for the underlying `RunToolCache.psm1` module rather than this file.


## Selective dependencies

Use -Module profiler, -Module dottrace or -Module profiler,dottrace. The string-array parameter validates those two names before effects, defaults to both and deduplicates case-insensitively. Only requested packages are downloaded, verified and extracted. Unselected return paths are null, even if an earlier invocation populated that tool. Offline fails on a missing requested archive, never on a missing unrequested one. WhatIf prepares nothing. Example: ./scripts/Initialize-Profilers.ps1 -OutputDirectory ./cache -Module profiler -Offline.

Review: Initialize-Profilers.ps1:12 delegates selection to Get-RunProfilerPackages; RunProfiles.Profiler.Tests.ps1 covers single/both selections, duplicates, invalid/empty inputs, preview and real offline archives. The cache receipt describes this invocation, not an inventory of every prior cache entry. No global installation or module import is performed by preparation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [RunToolCache.psm1](lib/RunToolCache.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Explicitly downloads checksum-pinned diagnostic tools to an isolated cache, without global installation.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
