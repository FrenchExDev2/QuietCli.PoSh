# Import-CiImageBundle.ps1

<!-- script-source:begin -->
Source file: [`Import-CiImageBundle.ps1`](../../scripts/Import-CiImageBundle.ps1)
<!-- script-source:end -->

Loads the image for a suite from the producer's current-run handoff. `-GetCacheKey` reads and validates an optional cache reference for the restore action. On that path, `-ArchiveDirectory` points to the restored cache, while `-Directory` supplies the current run's receipts. A bundle containing `images.tar` loads directly from `-Directory`. Both archive paths verify the current run, revision and native RID, the suite fingerprint and archive SHA-256 before loading. The script also verifies the source label and architecture before returning the daemon's immutable image ID.

A GHCR handoff names the expected digest by suite fingerprint. The consumer uses the existing read-only image resolver and requires the digest observed on pull to match the producer's receipt. `-WhatIf` previews the load. `-GetCacheKey` reads metadata and writes nothing.

See [Linux CI images](../ci/linux-images.md) and [Export-CiImageBundle](Export-CiImageBundle.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Loads the verified image for a test suite from the current run's Linux image bundle.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
