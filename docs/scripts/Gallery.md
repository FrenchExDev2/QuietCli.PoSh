# Gallery.ps1


## ReadyToRun package verification

When package-set.json declares ReadyToRun, Test-QuietGalleryPackageSet in scripts/Gallery.ps1 checks both CLR slots for all six RIDs: Release manifests, exact RID and real native-header signatures inside the compressed nupkg. Older/local IL plans remain supported. The CI release preparation requires ReadyToRun before compression. ReadyToRun.Tests.ps1 exercises a real all-RID package; ordinary Gallery identity/preview properties and mutation fixtures retain their existing scope.

## Purpose

Validates every artifact of a public PowerShell-Gallery-bound QuietCli package — version format, manifest identity/GUID stability, nupkg zip integrity and safety, nuspec identity, and the full set of required runtime/engine/PTY payloads per RID — before it is ever allowed to reach the actual publish step. The business problem it solves is "never publish a package whose public manifest, version, or payload set doesn't match exactly what was promised," since a PowerShell Gallery publish cannot be unpublished. It is invoked (dot-sourced) by `scripts/New-QuietGalleryPackage.ps1`, `scripts/New-QuietPreviewPackage.ps1`, and `scripts/Publish-QuietGallery.ps1`, and tested by `FrenchExDev2.QuietCli.Core.Tests.PoSh/GalleryIdentity.Tests.ps1` and `GalleryPreview.Tests.ps1`.

## Usage

A function library; no script-level params.

| Function | Key parameters |
|---|---|
| `Copy-QuietGalleryCoreModule` | `SourceDirectory` (Mandatory), `ModuleDirectory` (Mandatory) |
| `Read-QuietGalleryManifest` | `Entry` (`IO.Compression.ZipArchiveEntry`) |
| `Get-QuietGalleryVersion` | `Version` |
| `New-QuietGalleryPreviewVersion` | `BaseVersion`, `BuildNumber`, `Attempt` (default `'1'`) |
| `Set-QuietGalleryStagedPrerelease` | `Path`, `Prerelease` |
| `Get-QuietGalleryModuleVersion` | `Manifest` (`Collections.IDictionary`) |
| `Read-QuietGalleryXml` | `Entry` (`IO.Compression.ZipArchiveEntry`) |
| `Test-QuietGalleryPackageSet` | `PackageDirectory`, `Version` |
| `Get-QuietGalleryRemoteIdentity` | `Module`, `Version` |

```powershell
. ./scripts/Gallery.ps1
$plan = Test-QuietGalleryPackageSet -PackageDirectory ./artifacts/gallery -Version '1.4.0'
```

## Dependencies

- No dot-sourcing of other scripts in this file; `Test-QuietGalleryPackageSet` calls `Get-QuietRuntimeTargets` (line 155), which is defined in `RuntimeTargets.ps1` — an implicit, undeclared load-order dependency (the same pattern as `CiImages.ps1`).
- Reads and validates `.nupkg` zip archives and the embedded `.nuspec`/`.psd1` content.
- Makes one outbound HTTPS call to the live PowerShell Gallery OData API (`Get-QuietGalleryRemoteIdentity`, line 225) to check whether a version already exists before publishing.

## Side effects

- `Copy-QuietGalleryCoreModule` copies an entire directory tree and renames two files in place (lines 18-20), then rewrites the manifest's `RootModule` value via an AST-based text splice (lines 23-30), not a blind string replace.
- `Set-QuietGalleryStagedPrerelease` calls the mutating `Update-ModuleManifest` cmdlet and re-normalizes line endings afterward (lines 99-101).
- Everything else in this file is read-only validation.

## Findings

- Good, security-relevant: `Read-QuietGalleryXml` and the inline XML parsing inside `Test-QuietGalleryPackageSet` (lines 131-138, 178-183) explicitly disable DTD processing (`DtdProcessing.Prohibit`) and set `XmlResolver=$null` before parsing untrusted nuspec XML pulled from a `.nupkg` — correct, deliberate XXE-injection hardening, applied consistently in both places that parse nuspec content.
- Good: `Test-QuietGalleryPackageSet`'s zip-entry loop (lines 169-174) explicitly rejects path-traversal and zip-slip patterns (`'(^/|\\|:|(^|/)\.\.(/|$)|[\x00-\x1f])'`, line 172) and bounds both per-entry size (128MB) and total extracted size (512MB) before trusting anything in the archive — solid zip-bomb/zip-slip defense for a file about to be treated as a trusted public artifact.
- Good: `Copy-QuietGalleryCoreModule`'s manifest rewrite (lines 23-30) walks the PowerShell AST to find the exact `RootModule` key-value pair's source extent and only replaces that text range, deliberately avoiding a blind find/replace that could corrupt, say, a comment mentioning the same literal filename.
- Same implicit-dependency smell as `CiImages.ps1`: `Get-QuietRuntimeTargets` (line 155) is called with no dot-source of `RuntimeTargets.ps1` anywhere in this file — it only works because every current caller loads `Common.ps1` (which loads `RuntimeTargets.ps1`) first.
- `Get-QuietGalleryRemoteIdentity` (lines 211-233) makes a live, unauthenticated network call with a 30-second timeout and no retry; a transient network blip surfaces as the same generic `'GalleryPreflightHttpFailure: ...'` (line 229) as an actual Gallery outage, which matters for a release pipeline deciding whether to proceed.
- Testability: two dedicated test files exist (`GalleryIdentity.Tests.ps1`, `GalleryPreview.Tests.ps1`) — among the better-tested files in this set, consistent with this being public-release-gating code.

## Verdict

Careful, security-conscious validation code (XXE hardening, zip-slip/zip-bomb bounds, AST-based manifest editing) that is well tested. Its only real gap is the same undeclared `RuntimeTargets.ps1` dependency pattern seen in `CiImages.ps1` — making that explicit is the highest-priority fix, since it currently only works by accident of caller load order.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Copies the internal Core project into a public QuietCli staging directory without editing its sources.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
