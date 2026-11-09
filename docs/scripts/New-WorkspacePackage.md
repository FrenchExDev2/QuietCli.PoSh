# New-WorkspacePackage.ps1

## Purpose

Packages every locked, independently-versioned source and test module of the QuietCli2 monorepo into per-module `.zip` archives plus SHA-256 manifests, driven by `repositories.lock.json`. This is the monorepo-wide packaging step that other, more specific packagers build on: `New-QuietGalleryPackage.ps1` calls it (line 32 of that script) to produce the internal Core package that is later restaged as the public `QuietCli` Gallery module, and the test suite (`FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1` lines 665/686-687, and `Recall.Tests.ps1` line 255) invokes it directly to produce packages used in end-to-end package/publish tests. The script explicitly never publishes anything itself (per its `.SYNOPSIS`, line 5) — its sole job is to produce verifiable, hashed archives.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `OutputDirectory` | `string` | Yes | — |

```powershell
./scripts/New-WorkspacePackage.ps1 -OutputDirectory ./artifacts/packages/20261109-local
```

## Dependencies

- Dot-sources `Common.ps1` (line 12), which pulls in `ReportPaths.ps1`, `Ci.Process.ps1`, `SourceIdentity.ps1`, `RuntimeTargets.ps1` — supplies `Write-WorkspaceJson` (used lines 37, used for manifest writes).
- Dot-sources `AgentDocuments.ps1` (line 13) — supplies `Copy-QuietProductionAgentDocuments` (line 35), used only for the Core module.
- Calls `Get-QuietRuntimeTargets` and `Test-QuietBuildManifest` (lines 17-22) from the `RuntimeTargets.ps1` dependency chain to assert that every required RID's engine build is present before packaging anything.
- Calls `Assert-QuietPtyPublications` (line 16), defined in `RuntimeTargets.ps1`, which itself calls `Get-QuietElfHeader` and validates native PTY binaries' SHA-256 against a source hash — meaning this script transitively depends on the Linux PTY native build artifacts being present and correctly built.
- Reads `repositories.lock.json` from `WorkspaceRoot` (line 26) via `Get-Content -Encoding utf8 -Raw | ConvertFrom-Json` to discover which modules/paths to package.
- Shells out to nothing directly — all copying, hashing and zipping use managed .NET APIs (`Copy-Item`, `Get-FileHash`, `IO.Compression.ZipArchive`).
- Assumes every module listed in the lock file already has verified build manifests for `net10.0`/`net11.0` parser binaries, `lib/inprocess`, `lib/engine`, and per-RID `lib/engine/<rid>` outputs — i.e. a prior `dotnet build`/`dotnet publish` step has already run (this script does not build anything itself).

## Side effects

- Throws `PackageOutputAlreadyExists` (line 24) if `-OutputDirectory` already exists — this is the script's only safety rail against overwriting; there is no `-Force`/`-WhatIf`.
- Creates `-OutputDirectory` and one subdirectory per locked module (lines 25, 29).
- Recursively copies every module's source tree into the staging subdirectory, excluding a fixed denylist of directory/file names (`.git`, `.gitignore`, `bin`, `obj`, `artifacts`, `engine`, `fixture`, `engine-tests`, `parser-tests`, `tools`, `recall-tools`, `global.json` — line 31).
- Writes one `<Module>.manifest.json` per module (line 37) containing per-file SHA-256 hashes, sizes, the current Git `HEAD` revision, and the lock file's recorded `SourceSHA256`.
- Writes one `<Module>.zip` per module (lines 38-53) built deterministically: entries sorted by `[StringComparer]::Ordinal` (line 43), fixed `LastWriteTime` of 2000-01-01 UTC (line 47), and fixed `ExternalAttributes` (line 48) — producing byte-reproducible archives across runs, a notably good engineering choice for supply-chain verifiability.
- Returns one `[pscustomobject]` per module describing the archive path and hash, with `Published = $false` hardcoded (line 54) to make unmistakably clear that packaging is not publishing.

## Findings

- The zip-writing loop (lines 38-53) correctly uses `CopyToAsync(...).GetAwaiter().GetResult()` (line 51) for the file-to-entry copy, which follows the repo's stated preference ("prefer async methods... use `.GetAwaiter().GetResult()` even in sync PowerShell") — a positive example, not a violation.
- DESIGN: the file-exclusion denylist (line 31: `'.git','.gitignore','bin','obj','artifacts','engine','fixture','engine-tests','parser-tests','tools','recall-tools','global.json'`) is an inline literal array embedded in the packaging loop rather than a named, documented, reusable constant. If a new build-output directory convention is introduced elsewhere in the monorepo (e.g. a future `coverage/` or `.turbo/` directory), this script will silently include it in the shipped package unless someone remembers to update this exact line. A named `$ExcludedPackageEntries` constant (ideally shared with any other script that needs the same exclusion set) would reduce this risk.
- CONVENTION: the entire file is written in a dense, minimal-whitespace style (e.g. line 11: `[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OutputDirectory)` on one line; line 36-37 pack multi-statement logic onto single lines). This is consistent with several other scripts in this folder (`Push-Workspace.ps1`, `Publish-QuietGallery.ps1`, `Probe-ContainerRuntime.ps1`) and is called out as a pre-existing style issue in `docs/audits/2026-11-08-ecosystem-usage-review.md` (lines 56, 60) for sibling scripts — the same critique applies here: it materially hurts readability and makes future diffs harder to review, even though it has no functional defect.
- No `-WhatIf`/`SupportsShouldProcess` is offered, but this is arguably acceptable since the script only ever creates new, non-pre-existing output (it refuses to overwrite, line 24) rather than mutating anything destructively.
- No input validation on `-OutputDirectory` beyond the existence check — a caller could pass a path that resolves (after `GetFullPath`) outside any expected sandbox; since the script only creates/writes there (never deletes), the blast radius of a mistaken path is limited to accidental writes, not data loss.
- Testability: good indirect coverage — this script is exercised directly by `FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1` (lines 665, 686-687) and `Recall.Tests.ps1` (line 255), and transitively by `GalleryPreview.Tests.ps1` through `New-QuietGalleryPackage.ps1`. No defect found in these call sites that would suggest the packaging contract is broken.

## Verdict

Fit for purpose and well-tested via companion test suites; the deterministic-zip design is a genuine strength. The highest-priority improvement is purely stylistic/maintainability: extract the inline exclusion denylist (line 31) into a named, shared constant so future build-output directories can't silently leak into shipped packages.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
