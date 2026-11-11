# Update-DotNetCiLock.ps1

## Purpose

Synchronize exact .NET SDK archive hashes with global.json and optionally resolve current
Debian/Alpine base-image digests. [Complete guide](../../README-dotnet-and-global-dot-json.md#synchronize-ci-sdk-hashes-and-debianalpine-bases).

## Usage and parameters

```powershell
./scripts/Update-DotNetCiLock.ps1 -IncludeDevelopmentLock -RefreshBaseImages -WhatIf
$plans = ./scripts/Update-DotNetCiLock.ps1 -IncludeDevelopmentLock -RefreshBaseImages -PlanOnly
./scripts/Update-DotNetCiLock.ps1 -IncludeDevelopmentLock -RefreshBaseImages -Confirm
```

WorkspaceRoot selects the checkout. IncludeDevelopmentLock adds Windows x64/ARM64 ZIP
hashes. RefreshBaseImages refreshes the existing tags; DebianTag/AlpineTag explicitly
select alternatives. AlpineRuntimeVersion deliberately replaces the separate .NET 10
PowerShell host runtime. Preleases permits preview/RC metadata. PlanOnly queries but writes
nothing; WhatIf makes no HTTP request and creates no file.

## Dependencies and effects

Imports scripts/lib/DotNetLocks.psm1, which reuses official Microsoft release metadata
and official Docker Hub/registry metadata. No native client/daemon or layer download is
needed. All requested archive/platform evidence is validated before any selected lock is
written. Changed files receive original-byte backups and atomic per-file replacements.

## Findings

- scripts/Update-DotNetCiLock.ps1:27 guards orchestration; scripts/lib/DotNetLocks.psm1:156
  independently guards direct use.
- Canonical URLs and unique RID/format SHA-512 entries are required. Registry index bytes
  must match their reported digest and contain Linux amd64/arm64. This verifies metadata,
  not SDK archive bytes or image execution.
- OS-version changes are explicit. Different distributions can require changing native or
  PowerShell packages; registry availability does not establish that compatibility.
- A later write failure can leave an earlier selected file updated: atomicity is per file.
  HTTP/auth/rate-limit or malformed-input failures during planning leave the batch untouched.

## Verdict

A reviewed source-lock updater with offline properties/fuzz/mutation evidence. Run the
required image builds and hosted matrix before claiming release qualification.

<!-- script-contract:begin -->
## Execution contract

Purpose: Synchronizes SDK/archive locks with global.json and optionally refreshes OS base-image digests.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
