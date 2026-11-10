# New-WorkspacePackage.ps1

## Purpose and usage

Stages and archives independently versioned internal modules after verifying their compiled payloads.

```powershell
./scripts/New-WorkspacePackage.ps1 -OutputDirectory <new-directory> -RequireReadyToRun
```

`WorkspaceRoot` defaults to the repository root. `OutputDirectory` must be new. `RequireReadyToRun` additionally requires Release R2R publications and current portable slot declarations for both CLR builds and all six RIDs. Without it, ordinary local IL package preparation remains supported.

## Dependencies and side effects

Uses Common.ps1, AgentDocuments.ps1, runtime/build manifests and repositories.lock.json. Copies staged module files, production agent documents, SHA-256 manifests and deterministic ZIPs into the new output directory. Compiled payloads are copied recursively, including RID-specific net10.0 and net11.0 slots. No compilation, network access or registry publication.

## Critical review

- `scripts/New-WorkspacePackage.ps1:25` checks every requested R2R distribution before creating output. Missing slots, false receipts, wrong RIDs/configurations or invalid binaries block packaging.
- Internal module ZIPs are not the public Gallery identity. New-QuietGalleryPackage.ps1 stages the public QuietCli module separately.
- Existing stale generated directories may remain in the checkout; portable manifests control active slot selection. Packaging does not silently rebuild or repair stale outputs.

## Verdict

GitHub release preparation uses RequireReadyToRun; a local ordinary package does not imply full release qualification.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Packages every locked, independently versioned source/test module; never publishes them.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
