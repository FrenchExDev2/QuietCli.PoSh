# New-QuietGalleryPackage.ps1

## Purpose and usage

Prepares one public QuietCli nupkg and its SHA-256 publication plan, without contacting PSGallery.

```powershell
./scripts/New-QuietGalleryPackage.ps1 -OutputDirectory <new-directory> -Version <exact-version> -RequireReadyToRun
```

Parameters: optional WorkspaceRoot, required new OutputDirectory, optional exact Version, staged alphanumeric Prerelease override, and RequireReadyToRun. The latter propagates to New-WorkspacePackage.ps1 and records ReadyToRun=true in package-set.json. It requires all six Release R2R distributions for CLR 10 and CLR 11. Source manifests are unchanged.

## Dependencies and side effects

Uses Common.ps1, Gallery.ps1 and Microsoft.PowerShell.PSResourceGet's Compress-PSResource. Creates internal staging, the public module, one nupkg and package-set.json. Temporarily changes PSModulePath and restores it in finally. Test-QuietGalleryPackageSet verifies the compressed package; for R2R plans it checks all twelve embedded manifests and actual native-header signatures. No API key or publication is used.

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

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates the public Core nupkg without contacting or publishing to a repository.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
