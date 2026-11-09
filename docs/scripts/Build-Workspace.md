# Build-Workspace.ps1

## Purpose

The canonical build-only entry point for the monorepo: builds the Core engine, test fixtures, and the dependent Git parser assemblies across every required target framework and runtime identifier, without running any tests or publishing. It is invoked directly by `.github/workflows/ci.yml` (line 301), `.github/workflows/publish-psgallery.yml` (line 73), and `.github/workflows/quietcli2-readytorun.yml` (lines 32 and 102) — every workflow in the repository that needs a buildable tree calls this script first.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `Configuration` | `string` (`ValidateSet('Release','Debug')`) | No | `'Release'` |
| `RuntimeIdentifier` (alias `WindowsRuntimeIdentifier`) | `string[]` (`ValidateSet` of 6 RIDs) | No | all 6 RIDs: `win-x64,win-arm64,linux-x64,linux-arm64,linux-musl-x64,linux-musl-arm64` |
| `ReadyToRun` | `switch` | No | off — publishes the engine precompiled (Crossgen2) instead of a plain `dotnet build` |
| `LocalRuntimeIdentifier` | `string` | No | `'win-'+<local architecture>` — only used by `-ReadyToRun` for the `lib/inprocess` publish |

```powershell
./scripts/Build-Workspace.ps1
```

```powershell
# ReadyToRun A/B candidate build, per docs/README-run-profiles.md
./scripts/Build-Workspace.ps1 -ReadyToRun -LocalRuntimeIdentifier win-x64
```

## Dependencies

- Dot-sources `Common.ps1` (line 23), which supplies `Invoke-WorkspaceNative`, `Get-QuietBinaryInputs`, `Write-QuietBuildManifest`, `Get-QuietRuntimeTargets`, and `Assert-QuietRuntimePublication`/`Assert-QuietPtyPublications`.
- Shells out to `dotnet build`/`dotnet publish` for every project (lines 27, 35, 40, 50/52, 65).
- Assumes `global.json`, four hardcoded `.csproj` paths, and the pinned .NET 10/11 SDKs and runtime packs for all 6 target RIDs are present.

## Side effects

- Builds/publishes into 8 separate output directories across the Core, Core.Tests, and Git.Tests/Git.PoSh trees (lines 25-42, 46-56, 57-68).
- Writes a `build-manifest.json` after every single build/publish call — 9+ manifest writes in total.
- Never deletes anything; purely additive output.

## Findings

- DESIGN: the per-project loop body at lines 25-29, and the two near-identical "build both frameworks" blocks at lines 31-42, repeat the exact same three-statement shape (`Get-QuietBinaryInputs` → `Invoke-WorkspaceNative dotnet build ...` → `Write-QuietBuildManifest`) roughly 15 times across the file (4 + 4 + 1 + 6 call sites), with only the project/output path strings varying. This is a clear DRY violation: a shared helper taking `(ProjectPath, OutputPath, Framework)` and performing those three steps would substantially shrink this file and remove the risk of one call site silently drifting from the others (e.g. a missing `--nologo`, or a `-c $Configuration` typo).
- Hardcoded project paths are repeated as literal strings at lines 25 (four entries), 33, 37, 46, and 58 — none are named constants, so renaming any of the four `.csproj` files requires a manual grep-and-replace across this file with no compiler/linter safety net. This mirrors the same smell independently flagged for `New-ReadyToRunCandidate.ps1`'s two hardcoded paths.
- Good: the comment at lines 54-55 explicitly documents a real gotcha — the `lib/inprocess` manifest intentionally keeps the "portable" shape even under `-ReadyToRun`, so a precompiled build is still validated the same way everywhere else. This is helpful self-documentation, not a flaw.
- Testability: no Pester test was found exercising `Build-Workspace.ps1` directly. Given it is the single build entry point every workflow depends on, and a full functional run requires the pinned SDKs/toolchains for 6 RIDs, an end-to-end test is expensive — but there is no test at all, not even a narrow one asserting that `-ReadyToRun` actually appends `-p:PublishReadyToRun=true` to the `lib/inprocess` publish arguments (line 50), which is pure argument-composition logic that could be tested cheaply without invoking `dotnet`.

## Verdict

Correct, and the load-bearing build script for the entire CI/CD pipeline. Its highest-priority fix is the DRY violation across the roughly 15 near-identical build/manifest blocks (lines 25-68) — extracting a shared helper would shrink the file and remove the risk of call sites drifting as RIDs or frameworks are added.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
