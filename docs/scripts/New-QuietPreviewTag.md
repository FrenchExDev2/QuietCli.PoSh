# New-QuietPreviewTag.ps1

## Purpose

Creates a local annotated tag on the exact observed HEAD of a clean checkout. Default mode uses the Core numeric version and a UTC timestamp for an inert preview marker. `-Release` uses the complete owning manifest version in the public module namespace; explicitly pushing that release tag requests Gallery publication. The script never commits, pushes, publishes or replaces an existing tag. `PreviewTag.Tests.ps1` exercises both modes in an owned disposable repository.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` (this script's own checkout) |
| `Timestamp` | `DateTimeOffset` | No | `[DateTimeOffset]::UtcNow` |
| `Release` | `switch` | No | False; selects exact manifest-matched release tags |
| `Module` | `Core`, `Git`, `Vagrant` | No | `Core`; companion publication capability remains unavailable |

Supports `-WhatIf`/`-Confirm` (`SupportsShouldProcess`, `ConfirmImpact = 'Medium'`). `-WhatIf` is explicitly allowed on a dirty checkout (to preview the tag name); actual creation requires a clean tree.

```powershell
# Preview the tag name without creating it
./scripts/New-QuietPreviewTag.ps1 -WhatIf

# Create the tag (requires a clean, committed checkout)
$tag = ./scripts/New-QuietPreviewTag.ps1
```

## Dependencies

Release mode uses `-Release -Module Core` (Core is the default) to create `QuietCli/v<complete-manifest-version>`. It reads the optional prerelease suffix and calls [GalleryRelease](lib/GalleryRelease.md) before creating the local annotated tag. `-Module Git` and `-Module Vagrant` have independent source versions but are rejected while their public publication capability is unavailable. Without `-Release`, the existing timestamped Core preview tag behavior is unchanged. Pushing a namespaced release tag requests publication; this script itself still never pushes.

```powershell
./scripts/New-QuietPreviewTag.ps1 -Release -WhatIf
$release = ./scripts/New-QuietPreviewTag.ps1 -Release
```

The CI optimization case exercises both modes in an owned disposable repository, checking no-write preview, dirty-tree rejection, annotation, exact commit identity, collision rejection and unchanged manifests.

- Dot-sources nothing directly, but `Import-Module`s two workspace modules by exact path: `FrenchExDev2.QuietCli.Core.PoSh` and `FrenchExDev2.QuietCli.Git.PoSh` (lines 25-36), guarding against an already-loaded module from a different checkout.
- `Import-Module (Join-Path $PSScriptRoot 'lib/PreviewTag.psm1') -Force` (line 37) — supplies `New-QuietPreviewTagName`.
- Shells out to `git` exclusively through the local `quiet` facade/alias (`quiet -AsObject -C preview-tag -FilePath git -ArgumentList $Arguments`, line 48), per the repository's QuietCli2 convention — every native invocation goes through `quiet`, not a raw `git` call.
- Reads `FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1` via `Import-PowerShellDataFile` (line 73) to obtain `ModuleVersion`.
- Assumes a working `pwsh` 7.6+ host and that `git` is on `PATH` and reachable through `quiet`.

## Side effects

- With `-WhatIf` or when the checkout is dirty: none (read-only `git rev-parse`, `git status`, `git tag --list`).
- When actually run (`ShouldProcess` confirmed) on a clean tree: creates one local annotated Git tag (`git -c tag.gpgSign=false tag --annotate ...`, line 83). It does not push, does not touch the remote, does not modify any file.

## Findings

- No issues of substance were found after review. The script is tight, single-purpose, and defensive:
  - It independently re-derives the repository root via `git rev-parse --show-toplevel` and asserts it equals the caller-supplied `WorkspaceRoot` (lines 67-71), preventing a mismatched-root class of bug.
  - It validates `revision` against a strict SHA-1/SHA-256 regex (line 76) before using it, and bounds the captured Git stdout line to 4096 chars (line 55) against a runaway/pathological line — appropriate hygiene for data derived from an external process.
  - It explicitly refuses to create the tag when the tree is dirty (line 82), even though `-WhatIf` is allowed to proceed for inspection — this separation is a good design.
- DESIGN: the module-path integrity check (lines 25-36) duplicates logic that likely appears nearly identically in `New-ReadyToRunCandidate.ps1`'s sibling scripts and other entry points that guard against stale module loads; this pattern is copy-pasted per script rather than centralized in `Common.ps1` or a dedicated helper, which is a DRY gap across the `scripts/` folder (not unique to this file).
- CONVENTION: the script's own `.SYNOPSIS`/`.DESCRIPTION`/parameter docs are in English as required, and git calls are mediated through `quiet` as the house convention requires — no violation found here.
- Minor note, not severe: if `$Timestamp` is supplied with sub-tick-level duplicate values across calls in the same process (vanishingly unlikely in practice), tag collision is still guarded by the explicit `tag --list` existence check (line 78-79) which throws rather than silently overwriting.

## Verdict

Fit for purpose as-is; no rework needed. If anything should change, it is purely a cosmetic DRY improvement — hoisting the repeated "verify expected module already loaded from this exact path" block (lines 25-36) into a shared helper so every script in `scripts/` doesn't repeat it.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates a local annotated timestamp preview tag or an exact module release tag.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
