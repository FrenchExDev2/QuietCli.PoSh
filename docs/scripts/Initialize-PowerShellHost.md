# Initialize-PowerShellHost.ps1

## Purpose

Downloads and checksum-verifies an official, side-by-side PowerShell release ZIP (stable or preview channel) for CI matrix jobs that need to test against a specific pinned PowerShell host version distinct from whatever `pwsh` the runner ships with, without installing anything or touching any user profile. It is invoked directly by `.github/workflows/ci.yml` (line 110) and `.github/workflows/publish-psgallery.yml` (lines 69 and 135).

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Channel` | `string` (`ValidateSet('stable','preview')`) | Yes | none |
| `RuntimeIdentifier` | `string` (`ValidateSet('win-x64','win-arm64')`) | Yes | none |
| `OutputDirectory` | `string` | Yes | none |
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |

```powershell
$hostInfo = ./scripts/Initialize-PowerShellHost.ps1 -Channel stable -RuntimeIdentifier win-x64 -OutputDirectory (Join-Path $env:RUNNER_TEMP 'quietcli-powershell-host')
```

## Dependencies

- Dot-sources `Common.ps1` (line 22) for `Write-WorkspaceJson`.
- Reads `build/powershell-hosts.lock.json` (line 23) for the pinned version/hash per channel+RID.
- Uses `System.Net.Http.HttpClient` directly (lines 33-43) to download from `github.com/PowerShell/PowerShell/releases/...`, and `[IO.Compression.ZipFile]::ExtractToDirectoryAsync` (line 46) to unpack.
- Assumes the lock file's schema version is exactly 1 and that the requested Channel/RID combination has exactly one matching lock entry.

## Side effects

- Creates a brand-new `OutputDirectory`, rejecting it outright if it already exists (line 29: `throw 'PowerShellHostDirectoryExists'`).
- Downloads `host.zip` into it, extracts to `OutputDirectory/host/`, and writes a `host-receipt.json` manifest (line 50) via `Write-WorkspaceJson`.

## Findings

- Good, security-relevant: the download is checksum-verified against the pinned `SHA256` from the lock file (line 44: `-cne $hostSpec.SHA256`) before extraction, and the lock entry's own `Version`/`SHA256` shapes are validated by regex (line 27) before being trusted — a malformed or tampered lock entry fails closed with `'PowerShellHostIdentityInvalid'` rather than silently downloading an unverified or wrong-looking version. This is solid supply-chain hygiene for a script that fetches and later runs a third-party binary.
- Good: the output stream is opened with `[IO.FileMode]::CreateNew` (line 40), so a half-written prior download at the same path cannot be silently appended to or truncated-and-overwritten — combined with the prior `OutputDirectory`-exists check (line 29), this is reasonable defense against two concurrent runs racing on the same path.
- DESIGN: the script never verifies that the extracted `pwsh.exe` actually reports the expected version (e.g., via `pwsh -Version`) — it only checks the file exists at the expected path (line 48). A lock-file entry that, by human error, pointed at the wrong RID's correctly-signed archive would pass every check in this script and would only fail much later when the CI job tries to use the wrong-architecture binary.
- Two independent timeout mechanisms cover overlapping but not identical spans of the same logical operation: `$client.Timeout` (line 33) bounds only the HTTP request (lines 36, 38-39), while a separately-constructed 5-minute `CancellationTokenSource` (line 34) additionally bounds the `CopyToAsync` call (line 41). Functionally fine as written, but having two separately-configured 5-minute budgets for what is conceptually one bounded operation is a minor duplication that could silently drift if one is changed without the other.
- Testability: no Pester test was found referencing `Initialize-PowerShellHost` directly. A full functional test (real network download) is expensive, but there is no test at all for the cheaper-to-verify parts either — e.g. the regex validation of `hostSpec.Version`/`SHA256` (line 27), or the "reject an existing OutputDirectory" guard (line 29), both of which could be unit-tested without any network access.

## Verdict

Fit for purpose, with genuinely good checksum-based supply-chain hygiene. The highest-priority fix is adding even a minimal offline-testable check (lock-file shape validation, existing-directory rejection) given the current complete absence of any test, cheap or expensive, for this script.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Extracts an official PowerShell ZIP into a new directory without installing or changing profiles.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
