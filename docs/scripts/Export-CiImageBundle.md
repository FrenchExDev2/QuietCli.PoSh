# Export-CiImageBundle.ps1

<!-- script-source:begin -->
Source file: [`Export-CiImageBundle.ps1`](../../scripts/Export-CiImageBundle.ps1)
<!-- script-source:end -->

Prepares the selected suite images on the native Docker runner, then saves one `images.tar` and `bundle.json` for the RID. The producer adds a local transfer tag derived from each verified recipe fingerprint and saves the archive by those tags. The receipt binds the archive hash and fingerprints to the run and revision. `-PublishCache` follows the existing upstream develop guard. `-WhatIf` previews preparation and archive creation.

`-CacheKey` reads the declared suite plans and returns a hash of their distinct final fingerprints. It needs only `-Suite` and `-RuntimeIdentifier` and accesses neither Docker nor the registry. `-ReuseArchive` checks the restored archive in `-OutputDirectory` against the expected RID, fingerprint set and SHA-256 before writing a receipt for `-Revision` and `-RunId`. Its `-WhatIf` performs no file access or writes.

`-RestoredCacheKey` checks the restored key against the exact recipe fingerprint and writes a small `handoff.json` beside the verified archive receipt. `-TransferRegistryReferences` writes only a digest handoff when every selected chain came from GHCR. A local build uses the archive path. `-PassThru` reports whether every selected image chain was reused from the verified registry cache. `-RenewCache` bypasses GHCR reuse and requires publication to be disabled. The GitHub workflow also bypasses both Actions cache restores for a renewal.

A receipt or archive mismatch fails before transfer. Local tests cover the handoff, archive integrity and workflow conditions. Hosted cache restore and save require a GitHub Actions run.

See [Linux CI images](../ci/linux-images.md) and [Import-CiImageBundle](Import-CiImageBundle.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Prepares and transfers the verified Linux CI images for one native target.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
