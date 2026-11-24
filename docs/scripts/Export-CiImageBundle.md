# Export-CiImageBundle.ps1

<!-- script-source:begin -->
Source file: [`Export-CiImageBundle.ps1`](../../scripts/Export-CiImageBundle.ps1)
<!-- script-source:end -->

Prepares the selected suite images on the native Docker runner, then saves one `images.tar` and `bundle.json` for the RID. The producer adds a local transfer tag derived from each verified recipe fingerprint and saves the archive by those tags. The receipt binds the archive hash and fingerprints to the run and revision. `-PublishCache` follows the existing upstream develop guard. `-WhatIf` previews preparation and archive creation.

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
