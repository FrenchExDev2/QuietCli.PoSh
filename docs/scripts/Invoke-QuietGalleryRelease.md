# Invoke-QuietGalleryRelease.ps1

## Purpose and usage

Prepare, validate or publish a validated annotated release batch after one shared All qualification. Each module keeps its independent package/version/tag, while one leader owns the matrix and packaging build.

```powershell
./scripts/Invoke-QuietGalleryRelease.ps1 -Operation Prepare -PackageDirectory ./artifacts/gallery -ReleaseTagsJson '["FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview1","FrenchExDev2.QuietCli.Git.PoSh/v0.2.0-preview1"]' -TriggerTag FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview1 -Revision <qualified-sha> -RequireReadyToRun -WhatIf
```

`Operation` accepts Prepare, Validate or Publish. `WorkspaceRoot` selects the source manifests. Preparation creates one subdirectory per discovered module plus `release-set.json`; existing output is refused. Validation checks the exact revision, leader, ordered tag set and every unchanged package before the first publication. Publish invokes the existing single-package publisher in dependency order, preserving repository/key/duplicate/dependency checks and individual publication receipts.

## Dependencies and effects

Uses GalleryRelease/Gallery libraries and existing New-QuietGalleryPackage/Publish-QuietGallery entry points. No engine is required. All effects are under standard ShouldProcess; WhatIf validates inert source metadata but creates no output and contacts no repository. The workflow separately verifies remote tag membership and same-run qualification before calling this script. This entry point alone does not establish remote qualification.

## Review and validation limits

GalleryPreview fixtures prepare and validate actual Core/Git packages, reject a damaged second package before any publication, and observe dependency-ordered mock publishing without credentials/network requests. Tag fixtures reject foreign commits, duplicate/disabled members and elect a unique leader. An indexing delay after Core publication may still reject a newly dependent Git publication; no dependency bypass or automatic retry is used. Partial success retains per-module receipts for deliberate recovery. There is no rollback of an already published package.

<!-- script-contract:begin -->
## Execution contract

Purpose: Prepares, validates or publishes an annotated release batch in dependency order after one shared qualification.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
