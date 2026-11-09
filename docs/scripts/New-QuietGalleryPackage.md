# New-QuietGalleryPackage.ps1

## Purpose

Produces the actual public-facing `QuietCli` nupkg (the renamed, publishable version of the internal `FrenchExDev2.QuietCli.Core.PoSh` module, bundled with its six verified embedded engine distributions for different RIDs) entirely locally, without contacting or publishing to any package repository. This is the packaging step that both the real release pipeline (`publish-psgallery.yml`, line 89) and the preview-build pipeline (via `New-QuietPreviewPackage.ps1`, line 45) depend on to get a verified, version-matched `.nupkg` before anything is actually pushed to PowerShell Gallery.

## Usage

Parameters:
- `-WorkspaceRoot [string]` (default: parent of `$PSScriptRoot`).
- `-OutputDirectory [string]` (Mandatory) — must be a new, not-yet-existing directory (throws `GalleryOutputAlreadyExists` otherwise, line 18).
- `-Version [string]` (optional) — expected package version; must match the resolved release version unless a `-Prerelease` override is used (throws `GalleryReleaseVersionMismatch` otherwise, line 30).
- `-Prerelease [string]` (optional, must match `^[A-Za-z][A-Za-z0-9]*\z`) — alphanumeric label applied only to the *staged* manifest copy; source manifests/GUIDs/files are left untouched.

Example (from `publish-psgallery.yml`):
```powershell
./scripts/New-QuietGalleryPackage.ps1 -OutputDirectory ./artifacts/gallery -Version $env:RELEASE_VERSION
```

## Dependencies

- Dot-sources `Common.ps1` and `Gallery.ps1` (line 16) — most of the real logic (`Get-QuietGalleryModuleVersion`, `Get-QuietGalleryVersion`, `Copy-QuietGalleryCoreModule`, `Set-QuietGalleryStagedPrerelease`, `Test-QuietGalleryPackageSet`, `Get-QuietRuntimeTargets`) lives in `Gallery.ps1`, not reviewed here.
- Calls `scripts/New-WorkspacePackage.ps1` (line 32) to stage every workspace package first.
- Depends on the `Microsoft.PowerShell.PSResourceGet` module's `Compress-PSResource` cmdlet (line 42) to actually build the `.nupkg`.
- Reads `FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1` via `Import-PowerShellDataFile` (line 21) and `repositories.lock.json` (hashed into the plan, line 48).
- Mutates (temporarily) `$env:PSModulePath` (lines 36-47, restored in `finally`) so `Compress-PSResource` can resolve the staged public module by its public name.

## Side effects

- Throws immediately if `-OutputDirectory` already exists — this script never appends to or reuses a prior output directory.
- Runs `New-WorkspacePackage.ps1`, which (per its own responsibility, not reviewed here) stages every workspace package into `workspace-packages/` under `-OutputDirectory`.
- Copies the Core module into `public-modules/QuietCli` (renamed from the internal `FrenchExDev2.QuietCli.Core.PoSh` name) via `Copy-QuietGalleryCoreModule`.
- Temporarily mutates and then restores the process's `$env:PSModulePath` (lines 36-47) — a global, process-wide environment change for the duration of the `Compress-PSResource` call; restored via `finally` even on error.
- If `-Prerelease` is given, rewrites the *staged* manifest's prerelease tag in place (`Set-QuietGalleryStagedPrerelease`, line 41) — never touches the source-controlled manifest.
- Writes the `.nupkg` file(s) directly into `-OutputDirectory` via `Compress-PSResource -DestinationPath $OutputDirectory` (line 42).
- Writes `package-set.json` (the publication plan, with `Published=$false`, line 48-49) and calls `Test-QuietGalleryPackageSet` to verify the just-built set before returning.

## Findings

- No bug found in the version/prerelease reconciliation logic (lines 22-30): the script correctly separates "the version that must match the source manifest" (`$sourceVersion`) from "the version actually used to build/verify the package" (`$release`, overridden only when `-Prerelease` is explicitly bound via `$PSBoundParameters.ContainsKey('Prerelease')` rather than a truthy check, which correctly allows an empty-but-intentional prerelease label to be distinguished from "not supplied").
- DESIGN: the `$env:PSModulePath` mutation (lines 36-47) is a process-wide global state change performed by a script that may run as part of a larger composed pipeline (it's invoked from `New-QuietPreviewPackage.ps1`, itself invoked from a workflow). While it is correctly wrapped in `try/finally` to restore the original value, a process-wide environment mutation inside a reusable script is inherently a bit fragile — if `Compress-PSResource` itself spawns anything that reads `$env:PSModulePath` concurrently (unlikely in this single-threaded context, but worth flagging), or if a future caller parallelizes package builds within the same process, this pattern would need revisiting. As a sequential CI script this is safe today.
- CONVENTION: the script's own top-of-file comment ("Objective: Prepare the public Core nupkg with its six verified embedded engine distributions.", line 1) is correctly in English here — no French-comment violation in this file, unlike several of its siblings.
- DESIGN: `foreach($name in @($publicName))` (line 39) iterates over a single-element array (`$publicName = 'QuietCli'` is a fixed scalar, line 20) — this loop structure suggests the code was written to generalize to multiple public packages but currently only ever handles one; it's harmless as written, but it's dead generality (a "framework not yet used" smell) rather than a defect.
- No unhandled error path found: the `-OutputDirectory` existence pre-check (line 18), the `Prerelease` pattern validation (line 26), and the version-mismatch check (line 30) all fail fast with clear, specific thrown error codes before any expensive packaging work begins.
- Security: GUIDs and source versions are explicitly stated to remain unchanged when prerelease-staging (doc comment, line 13) — this is a correct safeguard against accidentally publishing a prerelease build under a GUID/version combination indistinguishable from a real release.
- Testability: not directly asserted by a dedicated test file found in this review (searches found `GalleryPreview.Tests.ps1` testing `New-QuietPreviewPackage.ps1`, which calls this script internally — so this script's logic is exercised transitively through that test, but no test was found asserting this script's own standalone behavior, e.g. the `GalleryOutputAlreadyExists`/`GalleryReleaseVersionMismatch`/`GalleryPreviewLabelInvalid` error paths in isolation).

## Verdict

Well-structured with sound version/prerelease handling and good fail-fast validation; no severe issues found — the main improvement opportunity is a direct (not just transitive-via-preview) Pester test for this script's own error paths (`GalleryOutputAlreadyExists`, `GalleryReleaseVersionMismatch`, `GalleryPreviewLabelInvalid`).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
