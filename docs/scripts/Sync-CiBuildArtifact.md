# Sync-CiBuildArtifact.ps1

<!-- script-source:begin -->
Source file: [`Sync-CiBuildArtifact.ps1`](../../scripts/Sync-CiBuildArtifact.ps1)
<!-- script-source:end -->

The PR build job exports the discovered module libraries into `build.zip`. The adjacent receipt records the checkout SHA, archive SHA-256 and presence of the IL benchmark variants. Only compiled output directories and the optional IL publications enter the archive.

```powershell
./scripts/Sync-CiBuildArtifact.ps1 -Mode Export -Revision $env:GITHUB_SHA
./scripts/Sync-CiBuildArtifact.ps1 -Mode Verify -Revision $env:GITHUB_SHA
./scripts/Sync-CiBuildArtifact.ps1 -Mode Import -Revision $env:GITHUB_SHA
```

Export requires previously built distributions. Pass `-Baseline` when the build produced the IL variants in `artifacts/ci-build-baseline`. Verify checks the receipt and ZIP checksum. Import first verifies the same receipt, extracts to an owned temporary directory and installs the expected library directories into a fresh checkout. Consumers use their normal build-manifest checks before qualifying binaries. `-WhatIf` skips filesystem effects.

<!-- script-contract:begin -->
## Execution contract

Purpose: Exports or installs the revision-bound compiled distributions shared by GitHub PR jobs.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
