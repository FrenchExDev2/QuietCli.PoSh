# Get-DotNetBaseImages.ps1

## Purpose

Inspect bounded official Debian/Alpine tag metadata without starting a container client
or downloading layers.

## Usage and parameters

```powershell
./scripts/Get-DotNetBaseImages.ps1 -Image debian -Name bookworm -Limit 20
./scripts/Get-DotNetBaseImages.ps1 -Image alpine -Name 3.24 -Limit 20
```

Image accepts debian/alpine. Name is an encoded Docker Hub name filter. Limit bounds the
first page to 1–100 entries. HasMore reports pagination; the output is not an exhaustive
registry inventory. WhatIf performs no request; Confirm approves the metadata operation.

## Dependencies and effects

Imports scripts/lib/DotNetLocks.psm1 and reads the official Docker Hub API over HTTPS.
Returns image/tag/digest/update-time/reported-platform metadata. No files or locks are
written, and no layer is pulled.

## Findings

- scripts/Get-DotNetBaseImages.ps1:16 guards the request. The library's fixed public
  endpoint and URL-encoded name filter avoid shell evaluation and arbitrary endpoint selection.
- Tag metadata is discovery evidence. The lock updater independently fetches the registry
  index, verifies its byte digest and required platforms before pinning it.
- There is no automatic distribution-major choice or build-compatibility claim.

## Verdict

Use to choose a tag for explicit lock planning; use the lock updater to verify/pin its index.

<!-- script-contract:begin -->
## Execution contract

Purpose: Lists bounded official Debian/Alpine tag metadata without downloading image layers.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
