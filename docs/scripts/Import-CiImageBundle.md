# Import-CiImageBundle.ps1

<!-- script-source:begin -->
Source file: [`Import-CiImageBundle.ps1`](../../scripts/Import-CiImageBundle.ps1)
<!-- script-source:end -->

Loads a downloaded `images.tar` into the runner's Docker daemon. It checks `bundle.json` against the current run, revision and native RID, verifies the archive hash, and inspects the imported transfer tag derived from the suite's computed fingerprint. The script verifies image labels and architecture before returning the consumer daemon's own immutable ID. `-WhatIf` previews the load.

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
