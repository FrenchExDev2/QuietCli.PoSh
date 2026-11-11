# Publish-QuietGallery.ps1

## Purpose and usage

Publish one selected verified business package once, preserving existing Gallery identities, without rebuilding or silently retrying.

```powershell
./scripts/Publish-QuietGallery.ps1 -PackageDirectory <prepared-directory> -Version <exact-version> -ValidateOnly
```

PackageDirectory supplies package-set.json and exactly one selected nupkg. Version must match the plan and embedded identity. ValidateOnly checks local contents without a key/network request. WhatIf validates locally and reports publication intent without credential/remote calls. Confirm uses the standard PowerShell prompt.

## Dependencies and effects

Imports lib/Gallery.psm1 after the shared infrastructure helper. Target discovery permits only explicitly publishable business manifests, currently Core/Git. Validation checks package identity/GUID, dependencies, safe ZIP layout, declared binary hashes and Core-specific RID/R2R payloads.

Real publication requires the environment key, canonical PSGallery repository URI and an absent target version, then passes the exact prepared NupkgPath to Publish-PSResource. Dependency checks remain enabled. A compatible Core dependency must be publicly available for Git; package preparation does not establish availability.

The local publication receipt distinguishes prepared/publishing/published/failed and records confirmed modules, pending identity and unknown effects. No overwrite or automatic retry is performed after a failure.

## Review and validation

GalleryPreview uses non-secret placeholders and mocked repository/remote/publication commands, independently tests rejection before credentials/network and validates real isolated Core/Git installation. Root tag orchestration and CI remain separate from this final publisher. Never use Gallery as a test target.

<!-- script-contract:begin -->
## Execution contract

Purpose: Publishes a prepared release once, with version and destination checks and no automatic retry.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
