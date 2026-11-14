# Publish-QuietGitHubRelease.ps1

## Purpose and usage

Create one GitHub Release per independently versioned module tag after successful Gallery publication. The workflow calls this entry point with the qualified revision and downloaded package/publication artifacts. No build or Gallery publication is repeated.

```powershell
./scripts/Publish-QuietGitHubRelease.ps1 -TriggerTag FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview1 -Revision ('a'*40) -PackageDirectory ./artifacts/gallery -WhatIf
```

`ReleaseTagsJson` selects the validated annotated batch and per-module subdirectories; empty selects the standalone package directory. `WorkspaceRoot` selects literal owning manifests. Only the leader can proceed. WhatIf resolves source metadata but performs no HTTP request, credential lookup or file write. Execution requires the original repository's exact push/tag/SHA context and an ephemeral `GH_TOKEN` with contents:write.

## Dependencies and effects

Uses GalleryRelease for tag policy, Gallery for exact nupkg integrity/identity verification and GitHubRelease for REST publication. Every package and successful PSGallery receipt is checked before the first release request. Each release includes its unchanged nupkg, package-set.json and publication.json. Preview versions are prereleases. No release changes the repository's global latest pointer.

## Critical findings and verdict

`scripts/Publish-QuietGitHubRelease.ps1` guards effects with ShouldProcess and checks workflow context and successful per-module publication hashes. `scripts/lib/GitHubRelease.psm1` checks the remote tag's peeled commit, uploads verified files to a draft, then publishes only after SHA-256/size verification. Existing drafts/releases are refused without replacement. Failed uploads leave a draft for deliberate recovery; partial batch success has no rollback. A GitHub-only job failure does not undo Gallery publication and may be investigated/retried separately after handling any existing draft/release. Offline tests cover requests and boundaries; real credentials, hosted artifact layout and actual publication remain hosted qualification requirements.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Gallery.psm1](lib/Gallery.md), [GalleryRelease.psm1](lib/GalleryRelease.md), [GitHubRelease.psm1](lib/GitHubRelease.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates per-module GitHub releases from exact packages already published on PowerShell Gallery.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
