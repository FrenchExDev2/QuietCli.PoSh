# Verify-Distribution.ps1

## Purpose

A thin, process-isolation wrapper around `Test-WorkspacePackage.ps1` that runs the exact same
verification logic but returns its result as a single compact JSON string instead of a live
PowerShell object. The business reason for this separate script, per its own doc comment ("Objectif :
Vérifier une distribution extraite dans un processus distinct des suites qui l'ont construite" —
"Verify an extracted distribution in a process separate from the suites that built it"), is process
isolation: a caller that wants to validate a just-built distribution without sharing any PowerShell
session state, loaded modules, or variables with the build/test process that produced it can launch
this script as a brand-new `pwsh -File` child process and parse its single JSON line of stdout. This
is the shape used by `audit/Probe-Package.ps1`-style callers elsewhere in the repo (that pattern — a
probe script launched via `quiet -FilePath pwsh -ArgumentList @('-File', 'Probe-X.ps1', ...)` whose
JSON stdout is parsed back — recurs throughout `FrenchExDev2.QuietCli.Core.Tests.PoSh/audit`), though
no test or caller was found inside `scripts/` or the `*.Tests.PoSh` projects invoking
`Verify-Distribution.ps1` by its own file name specifically — it appears to be a general-purpose,
externally-invocable CLI entry point for distribution verification (e.g. for a release/gallery
workflow or manual operator use) rather than something wired into the current automated test suite.

## Usage

```
[CmdletBinding()]param([Parameter(Mandatory)][string]$PackageDirectory,[Parameter(Mandatory)][string]$ExtractionDirectory,[switch]$TestImport)
```

- `PackageDirectory` (string, mandatory) — archives and manifests to verify; passed straight through
  to `Test-WorkspacePackage.ps1`.
- `ExtractionDirectory` (string, mandatory) — new extraction destination; passed straight through.
- `TestImport` (switch, optional) — explicitly executes the fully verified modules after the whole
  package set passes checking; passed straight through.

Note: unlike `Test-WorkspacePackage.ps1`, this wrapper does **not** expose `MaxFiles`, `MaxFileBytes`,
or `MaxTotalBytes` — callers of this script are stuck with `Test-WorkspacePackage.ps1`'s defaults
(10,000 files / 128 MiB per file / 512 MiB total) with no way to override them.

Example:

```powershell
pwsh -File ./scripts/Verify-Distribution.ps1 -PackageDirectory ./artifacts/packages/20261109 -ExtractionDirectory ./tmp/verify -TestImport
```

## Dependencies

- Invokes `Test-WorkspacePackage.ps1` as a child script call (`&`, line 15) in the *same* process
  (this is not itself a `Start-Process`/new-process launch — the "separate process" isolation this
  script's name implies only happens if the *caller* launches `Verify-Distribution.ps1` itself as a
  new `pwsh -File` process, which this script does not do on its own).
- No other dependencies: no dot-sourcing, no module import, no direct external process beyond what
  `Test-WorkspacePackage.ps1` itself shells out to.

## Side effects

- Identical side effects to `Test-WorkspacePackage.ps1` (see that script's review): creates
  `ExtractionDirectory`, validates and copies package contents into it, optionally imports modules
  under `-TestImport`.
- Additionally serializes the result object to JSON (`ConvertTo-Json -InputObject $result -Depth 8
  -Compress`, line 16) and writes it to stdout as the script's only pipeline output — this is the
  entire value this wrapper adds over calling `Test-WorkspacePackage.ps1` directly.

## Findings

- DESIGN: the script's own `.SYNOPSIS` ("Imports only extracted packages and returns a small
  verification JSON document") and French objective comment both frame this as process-isolated
  verification, but the script itself does not create that isolation — it is a same-process child
  script call (`&`). The actual process boundary only exists if whoever *calls*
  `Verify-Distribution.ps1` does so via `Start-Process`/`pwsh -File` rather than dot-sourcing or
  `&`-invoking it in their own session. This is not a bug exactly, but the doc comment slightly
  overstates what the script itself guarantees versus what the calling convention must additionally
  provide — a reader could reasonably assume this script enforces isolation on its own.
- DESIGN: hardcoding `-Depth 8` (line 16) for the JSON conversion is a reasonable but silent choice —
  if `Test-WorkspacePackage.ps1`'s returned object nesting ever grows past depth 8 (e.g. the
  `Modules`/`ImportedModules` arrays gain nested objects in a future change), `ConvertTo-Json` would
  silently truncate those nested levels rather than error, producing an incomplete JSON document with
  no warning. A `-WarningAction Stop` or depth-overflow check would make this fail loudly instead of
  quietly dropping data.
- DESIGN: this wrapper drops the `MaxFiles`/`MaxFileBytes`/`MaxTotalBytes` override capability that
  `Test-WorkspacePackage.ps1` exposes (noted in Usage above) without comment — any caller needing
  non-default quotas (e.g. verifying an intentionally larger or smaller distribution for a test) must
  bypass this wrapper and call `Test-WorkspacePackage.ps1` directly, which somewhat defeats having a
  single "the" distribution-verification entry point.
- CONVENTION: no async-I/O violation — the script does no I/O of its own beyond the `&` call and
  `ConvertTo-Json`.
- Testability gap: no Pester test references `Verify-Distribution.ps1` by name (searched both
  `*.Tests.PoSh` projects — no hits). Since its only added logic over `Test-WorkspacePackage.ps1`
  (which *is* well-tested, see that review) is the JSON serialization wrapper, the untested surface
  area here is small, but it is still exactly the kind of "does the JSON actually round-trip the full
  result object, including at the chosen `-Depth`" check that has zero coverage today.
- No new security concerns beyond those already covered in `Test-WorkspacePackage.ps1`'s review — this
  script adds no new attack surface, since all validation logic is delegated.

## Verdict

A reasonable, minimal JSON-emitting wrapper that correctly delegates its security-critical work to a
well-tested script; the main things worth fixing are clarifying (or renaming/re-documenting) that this
script itself does not provide process isolation — the caller must still launch it as a separate
process to get that property — and surfacing the quota parameters it currently drops.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Imports only extracted packages and returns a small verification JSON document.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
