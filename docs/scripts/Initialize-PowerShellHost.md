# Initialize-PowerShellHost.ps1

## Purpose and usage

Prepares a checksum-pinned side-by-side host without a machine installation or profile change. Stable currently selects GA 7.7.0 / CLR 11. Supported RIDs are win-x64, win-arm64, linux-x64 and linux-arm64; Linux musl stays under its separate native-image policy.

```powershell
$hostInfo = ./scripts/Initialize-PowerShellHost.ps1 -Channel stable -RuntimeIdentifier win-x64 -OutputDirectory (Join-Path $env:RUNNER_TEMP 'quietcli-powershell-host')
```

Channel, RuntimeIdentifier and a new OutputDirectory are mandatory. WorkspaceRoot defaults to the checkout. ArchiveCacheDirectory defaults to `.cache/powershell-hosts`; files are addressed by locked SHA-256 plus ZIP/tar.gz extension and reverified on every reuse. Linked or corrupted entries fail explicitly. WhatIf performs no read, network request or write.

## GA and optional Preview

The lock records GA separately from the next-version prerelease. Preview execution is optional and disabled by default in CI. Requesting the announced but unpublished 7.8.0-preview.1 fails before creating an extraction directory; production does not require it. Refresh with [Update-PowerShellCiLock](Update-PowerShellCiLock.md) after official archives become available.

The setup-powershell composite action prepares stable for native tooling, image orchestration and smoke jobs. The product Windows matrix selects its explicit channel. Publication independently selects stable. GITHUB_PATH affects subsequent runner steps only; no persistent profile is edited.

## Dependencies and effects

`scripts/Initialize-PowerShellHost.ps1:28` reads build/powershell-hosts.lock.json. Common supplies Write-WorkspaceJson. HTTPS downloads use HttpClient with a five-minute cancellation budget. SHA-256 verification precedes ZIP or .NET tar/gzip extraction. Linux pwsh receives execute permission on Linux. The returned receipt records version, expected CLR major, RID, archive hash, source and executable path; workers separately verify actual runtime identity.

Creates a new destination, optionally populates the checksum-addressed cache and writes host-receipt.json. An existing destination is rejected. Failed downloads/extractions may leave diagnostic files; no automatic cleanup/retry or installation occurs.

## Critical review and verdict

The host lock and digest bind extraction, while execution identity remains the worker's responsibility. Offline ZIP and independently generated tar/gzip fixtures cover cache reuse, corruption and no-effect previews; archive presence is not ARM64 execution evidence. General hostile-archive qualification and hosted transfer speed are outside these checks. The selected release URLs are constructed from validated versions/RIDs rather than caller-provided hosts.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Extracts a checksum-pinned PowerShell ZIP or tar/gzip archive without installing or changing profiles.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
