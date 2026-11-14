# New-QuietGalleryPackage.ps1

## Purpose and usage

Prepares one selected publishable business-module nupkg and its SHA-256 publication plan, without contacting PSGallery. Module defaults to Core; -Module Git selects FrenchExDev2.QuietCli.Git.PoSh. Workspace manifests and the shared reader derive eligibility/name/version, preserving existing filenames, GUID and dependencies. Core keeps its six RID payloads; Git keeps its declared net10.0/net11.0 parser outputs and Core dependency.

```powershell
./scripts/New-QuietGalleryPackage.ps1 -OutputDirectory <new-directory> -Version <exact-version> -RequireReadyToRun
```

Parameters: optional WorkspaceRoot, required new OutputDirectory, optional exact Version, staged alphanumeric Prerelease override, and RequireReadyToRun. The latter propagates to New-WorkspacePackage.ps1 and records ReadyToRun=true in package-set.json. It requires all six Release R2R distributions for CLR 10 and CLR 11. Source manifests are unchanged.

## Dependencies and side effects

Uses Common.ps1, lib/Gallery.psm1, GalleryRelease target discovery and Compress-PSResource. New-WorkspacePackage selects only the requested project. Temporary PSModulePath includes source dependencies during validation and is restored in finally. The plan records the exact Module; validation checks nuspec/manifest identity, dependencies and declared binary hashes. Only Core uses RID/R2R checks. No API key or publication is used.

## Critical review

- `scripts/New-QuietGalleryPackage.ps1:34` forwards the R2R requirement before compression. A prepared package is not proof of a successful hosted platform matrix.
- One nupkg contains all RIDs; there is no per-RID Gallery publication. GitHub packaging rebuilds on Windows x64 after exact-source qualification, then publication downloads/hash-verifies those exact bytes.
- Local preparation can omit RequireReadyToRun. GitHub release/preview preparation explicitly requires it; consumers must inspect the plan rather than infer R2R from a filename.

## Verdict

Preparation is offline and separate from publication. The exact prepared nupkg is the unit delivered to PSGallery.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md), [Gallery.psm1](lib/Gallery.md), [GalleryRelease.psm1](lib/GalleryRelease.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates one selected business-module nupkg without contacting or publishing to a repository.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
