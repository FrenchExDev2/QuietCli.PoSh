# New-QuietPreviewPackage.ps1

## Purpose

Prepares a uniquely-versioned, Core-only *preview* package (a PowerShell-Gallery-prerelease-style build tied to a specific CI build number/attempt) without publishing it or editing any source manifest, and — when a `-QualifiedRevision` is supplied — enforces that the packaged commit is exactly the one that passed qualification and that the working tree is clean. This closes the gap between "qualification passed on commit X" and "the artifact we're about to publish as a preview actually is commit X, unmodified" — a supply-chain integrity check for the preview-release pipeline. It is invoked from `.github/workflows/publish-psgallery.yml` (line 86) before the "real" `New-QuietGalleryPackage.ps1` publish step, and is directly tested by `FrenchExDev2.QuietCli.Core.Tests.PoSh/GalleryPreview.Tests.ps1` (lines 88, 105).

## Usage

Parameters:
- `-WorkspaceRoot [string]` (default: parent of `$PSScriptRoot`).
- `-OutputDirectory [string]` (Mandatory) — new destination for nupkg files, publication plan, and preview provenance.
- `-BuildNumber [string]` (default `$env:GITHUB_RUN_NUMBER`) — monotonic build counter.
- `-Attempt [string]` (default `$env:GITHUB_RUN_ATTEMPT`, or `'1'` outside GitHub Actions).
- `-QualifiedRevision [string]` (optional) — exact revision returned by the qualification gate; when given, requires matching `HEAD` (`GalleryPreviewRevisionMismatch` otherwise) and a clean checkout (`GalleryPreviewQualifiedCheckoutDirty` otherwise).

Example (from `publish-psgallery.yml`):
```powershell
./scripts/New-QuietPreviewPackage.ps1 -OutputDirectory ./artifacts/gallery -BuildNumber $env:GITHUB_RUN_NUMBER -Attempt $env:GITHUB_RUN_ATTEMPT -QualifiedRevision $env:QUALIFIED_REVISION
```

## Dependencies

- Dot-sources `Common.ps1` and `Gallery.ps1` (lines 25-26) — `Get-QuietWorkspaceProjects`, `New-QuietGalleryPreviewVersion`, `Get-QuietGalleryVersion`, `Read-QuietRepositoryValue` all live in those files, not reviewed here.
- Calls `git` indirectly via `Read-QuietRepositoryValue` (lines 39, 42 — `rev-parse --verify HEAD`, `status --porcelain=v1 --untracked-files=normal`) to check revision identity and working-tree cleanliness.
- Internally invokes two other scripts in the same folder: `New-QuietGalleryPackage.ps1` (line 45, the actual packaging) and `Publish-QuietGallery.ps1 -ValidateOnly` (line 46, a dry-run validation pass) — this script is purely an orchestrator/gate on top of those two.
- Reads `FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1`'s `ModuleVersion` via `Import-PowerShellDataFile` (line 36).

## Side effects

- Guards (lines 31-34) against `-OutputDirectory` being located *inside* any workspace project's own root directory (`GalleryPreviewOutputInsideModule`) — the comment on line 29 is explicit that this check exists only to prevent polluting source modules with generated artifacts, not to select which packages get published.
- Fully delegates the actual package-building/writing side effects to `New-QuietGalleryPackage.ps1` (see that file's own Side effects section) and the dry-run validation to `Publish-QuietGallery.ps1 -ValidateOnly` (no network publish, per `-ValidateOnly`).
- Writes `preview.json` into `-OutputDirectory` (lines 47) recording `Version, BaseVersion, BuildNumber, Attempt, SourceRevision, QualifiedRevision, Published=$false`.
- Reads git state (`rev-parse`, `status --porcelain`) but does not mutate the repository.

## Findings

- No bug found in the qualified-revision integrity gate (lines 39-44): it correctly validates the revision format itself (`^[a-fA-F0-9]{40}\z`) *before* comparing it to `HEAD` (line 40), and separately checks for a dirty working tree *only* when `-QualifiedRevision` was actually supplied (line 41's `if($QualifiedRevision)`), which is the right conditional scope — an unqualified/ad-hoc preview build (no `-QualifiedRevision`) is correctly allowed to run against a dirty tree, since that check is specifically about trusting a prior qualification result, not a general cleanliness requirement for all preview builds.
- DESIGN: `-BuildNumber` and `-Attempt` have no `ValidatePattern`/numeric type constraint — they are plain `[string]` parameters defaulting to GitHub Actions environment variables. If `New-QuietGalleryPreviewVersion` (in `Gallery.ps1`) doesn't itself validate that these are well-formed non-negative integers before embedding them into a semantic version string, a malformed or attacker-influenced environment variable (unlikely in this trusted CI context, but worth noting since `$env:GITHUB_RUN_NUMBER` could in principle be anything if the workflow is misconfigured) could produce a malformed or colliding preview version with no error from this script itself.
- CONVENTION: top-of-file comment-based help (lines 1-15) is correctly in English; no violation found in this file.
- No input-validation gap found beyond the `-BuildNumber`/`-Attempt` type-looseness noted above: `-OutputDirectory`'s inside-a-module guard (lines 31-34) is a sound, explicit safety check with a clear comment about its (narrow) scope.
- Security: the integrity chain here — "the thing we package is exactly the commit that was qualified, and that commit's checkout is unmodified" — is a genuinely valuable supply-chain property, and it's implemented with the right primitives (`git rev-parse --verify HEAD` compared case-insensitively... actually case-sensitively, via `-cne`, line 40 — correctly exact-match, not case-folded, which is appropriate for a 40-hex-char SHA where case differences would be unusual but should still be rejected rather than silently normalized).
- Testability: has a dedicated test (`GalleryPreview.Tests.ps1`, lines 88 and 105 directly invoke this script with explicit `-BuildNumber`/`-Attempt` values) — good direct coverage for at least the primary packaging path; it was not confirmed in this review whether the `GalleryPreviewRevisionMismatch`/`GalleryPreviewQualifiedCheckoutDirty` error paths specifically are exercised by that test file (only the happy-path invocation was visible in the grep excerpt reviewed).

## Verdict

A well-targeted, appropriately paranoid integrity gate for preview packaging with no severe issues found; the one worth tightening is adding at least a numeric/pattern validation on `-BuildNumber`/`-Attempt` so a malformed CI environment variable fails fast here with a clear message rather than producing a potentially malformed version string deeper in `Gallery.ps1`.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
