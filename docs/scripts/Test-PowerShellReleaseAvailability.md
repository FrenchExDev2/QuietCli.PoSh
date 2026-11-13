# Test-PowerShellReleaseAvailability.ps1

## Purpose and usage

Reads current Microsoft GA/next-preview metadata and checks native archive, NuGet and Alpine package availability. It changes no lock, installation or image.

```powershell
./scripts/Test-PowerShellReleaseAvailability.ps1
./scripts/Test-PowerShellReleaseAvailability.ps1 -WhatIf
```

AlpineBranch defaults to the existing `v3.24` repository. The report separates published archives with official SHA-256 and successful HEAD probes from absent assets. Preview selection considers only published previews newer than GA; an announced next tag is recorded unavailable until published. Native Alpine indexes are read for both x86_64 and aarch64. HTTP/TLS/rate-limit failures are explicit, never proof of absence.

## Dependencies and side effects

Imports [PowerShellReleases](lib/PowerShellReleases.md). Performs bounded HTTPS metadata/HEAD reads without retries or certificate bypasses. WhatIf returns before import/network. No binaries or container layers are downloaded by the audit.

## Critical review and verdict

`scripts/Test-PowerShellReleaseAvailability.ps1:1` provides a reproducible source inventory, not execution qualification. HEAD availability and published checksums do not verify archive bytes; host preparation verifies downloaded bytes, and native tests establish execution. The current musl ARM64 GA archive and Alpine GA package gaps remain explicit.

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks official PowerShell GA, next-preview archives and native Alpine package availability.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
