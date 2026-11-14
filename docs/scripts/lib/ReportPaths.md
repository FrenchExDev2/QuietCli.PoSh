# ReportPaths.psm1

## Library boundary

Located at `scripts/lib/ReportPaths.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/ReportPaths.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Get-QuietReportRoot'
```


## Purpose

Provides one shared function, `Get-QuietReportRoot`, that computes a single canonical directory for a given report category (e.g. `workstation`, `coldstart`, `runtime-diagnosis`), separating local developer-machine temp output from CI artifact-upload paths, while keeping separate workspace checkouts from colliding with each other in the shared system temp directory. This is pure plumbing: it solves the problem of "where do I put this output so it doesn't clash with another checkout's output, and so CI can still find it where its upload step expects." It is imported by `Common.ps1` (line 1) and therefore transitively available to almost every other script in this batch, and directly imported by `Remove-DevelopmentWorkstationRun.ps1` (line 22) and by `Probe-ContainerRuntime.ps1`'s caller, `Invoke-ContainerRuntimeDiagnosis.ps1` (via `Common.ps1`).

## Usage

`Get-QuietReportRoot` parameters:

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | Yes | — |
| `Category` | `string` (`ValidatePattern('^[a-z][a-z0-9-]*$')`) | Yes | — |
| `ContinuousIntegration` | `bool` | No | `($env:CI -ceq 'true' -or $env:GITHUB_ACTIONS -ceq 'true')` |

This file is not an executable script itself (no top-level `param()`/`[CmdletBinding()]`); it only defines a function, so it is always imported, never invoked directly.

```powershell
Import-Module (Join-Path $PSScriptRoot 'ReportPaths.psm1') -DisableNameChecking -ErrorAction Stop
$root = Get-QuietReportRoot -WorkspaceRoot $WorkspaceRoot -Category 'coldstart'
```

## Dependencies

- None — no `Import-Module`, no imported of other files, no external process calls. Pure, self-contained logic using only `[IO.Path]`, `[Security.Cryptography.SHA256]`, and `[Text.Encoding]`.
- Reads two environment variables, `$env:CI` and `$env:GITHUB_ACTIONS` (line 13), to auto-detect a CI context when `-ContinuousIntegration` is not explicitly passed.

## Side effects

- None. This function is purely computational — it only returns a path string; it never creates, deletes, or writes anything to disk itself. Callers are responsible for creating the directory it names.

## Findings

- No defects found; the function does exactly one well-bounded thing and does it carefully.
- A deliberate, good design choice: the non-CI branch (lines 16-18) hashes the case-normalized (`ToUpperInvariant` on Windows, line 16) full workspace path with SHA-256 and takes a 12-character hex prefix (line 17) to build a per-workspace-unique subdirectory under the OS temp root. This correctly avoids two different checkouts of the same monorepo (e.g. two worktrees, or CI vs. local) from writing output into the same temp location and corrupting each other's state, while remaining human-debuggable (the hash is short and the category name stays readable in the path).
- Windows-only case-insensitivity handling (line 16: `if($IsWindows){$workspace.ToUpperInvariant()}else{$workspace}`) correctly reflects that Windows filesystem paths are case-insensitive while Linux paths are case-sensitive, avoiding two differently-cased references to the same Windows workspace path producing two different hash buckets.
- DESIGN: the CI-path (`Join-Path $workspace ('artifacts/'+$Category)`, line 15) hardcodes the `artifacts/` segment inline rather than sourcing it from a shared constant. Since this convention ("CI artifacts live under `artifacts/<category>`") recurs across other scripts and the CI workflow YAMLs in this ecosystem (e.g. `Show-ColdStartMatrixReport.ps1`'s default `-ArtifactsDirectory`), a future rename here would silently diverge from those other hardcoded occurrences instead of failing fast. This is a DRY concern shared with several other scripts, not unique to this file, but `ReportPaths.psm1` is the natural single place to anchor it since everything else is meant to flow through it.
- No input-validation gap: `-Category` is restricted by a strict `ValidatePattern` (line 13) to lowercase-alphanumeric-hyphen strings, explicitly preventing path-traversal or absolute-path injection through that parameter. `-WorkspaceRoot` is not similarly pattern-validated, but it is passed through `[IO.Path]::GetFullPath` (line 14), which normalizes it; a caller-supplied `WorkspaceRoot` pointing somewhere unintended is a caller error, not a vulnerability in this function, since the function only derives a path string and never acts on it.
- Testability: good — `FrenchExDev2.QuietCli.Core.Tests.PoSh\ReportPaths.Tests.ps1` exists and directly targets this file's function.

## Verdict

Fit for purpose as-is; this is a small, correct, well-isolated utility with its own dedicated test file. No functional rework is needed — the only improvement worth considering is centralizing the hardcoded `artifacts/` segment (line 15) so it cannot silently drift from the same literal used elsewhere.

## Dependency and regression contract

Path components are passed separately to System.IO.Path.Combine, including the temporary QuietCli2/workspace/category and CI artifacts/category segments. Returned paths use native separators and remain stable across trailing-separator variants.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Separates local temporary reports by workspace while retaining CI artifact upload paths.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
