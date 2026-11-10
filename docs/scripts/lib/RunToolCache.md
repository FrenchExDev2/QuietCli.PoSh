# RunToolCache.psm1

## Purpose

Provides a verified, offline-capable local cache for the two checksum-pinned diagnostic tool packages the run-profile tooling needs (PSProfiler 4.3.0 and `dotnet-trace` 10.0.750501), so profiling can happen without a global/system install and with cryptographic proof that a cached or freshly-downloaded archive matches an exact expected SHA-256. It is the download/verification layer beneath `RunProfiler.psm1`'s `Resolve-RunProfilerModule` convention (same `%TEMP%/QuietCli2` cache root) and is presumably invoked by `scripts/Initialize-Profilers.ps1`. Directly exercised by `RunProfiles.Profiler.Tests.ps1` and targeted by eight mutation cases in `RunProfiles.Mutation.ps1` (lines 140-147) covering digest bypass, layout-check removal, re-extraction-skip, and the offline/version-drift guards.

## Usage

Exported functions:
- `Get-RunProfilerPackages` — no parameters; returns the two hardcoded package specs (`Name`, `Version`, `Url`, `SHA256`, `Entrypoint`) for Profiler and dotnet-trace.
- `Initialize-RunToolCache` — `[CmdletBinding()]`, parameters: `-OutputDirectory` (Mandatory, `[string]`, isolated cache root), `-Packages` (Mandatory, `[hashtable[]]`), `-Offline` (`[switch]`, rejects a cache miss before any HTTP client is constructed), `-DownloadBytes` (`[scriptblock]`, optional byte provider override for testing/explicit URLs — checksum verification is always applied regardless). Returns a `[pscustomobject]` with `ProfilerModulePath`, `ClrProfilerPath`, `Receipt`, `Directory`.

Example:
```powershell
Import-Module ./scripts/lib/RunToolCache.psm1
$tools = Initialize-RunToolCache -OutputDirectory (Join-Path ([IO.Path]::GetTempPath()) 'QuietCli2/profilers/pinned') -Packages (Get-RunProfilerPackages)
$tools.ProfilerModulePath   # path to Profiler.psd1, hash-verified
```

## Dependencies

- Imports `RunEncoding.psm1` for `Write-RunTextFile`.
- Uses `[Net.Http.HttpClient]` directly (not `Invoke-WebRequest`/`Invoke-RestMethod`) to download package archives when there's a cache miss and no `-DownloadBytes` override and `-Offline` isn't set.
- Uses `[IO.Compression.ZipFile]::ExtractToDirectoryAsync` to unpack `.nupkg` archives (NuGet packages are zip files) and `[Security.Cryptography.SHA256]` for hashing.
- Filesystem convention: writes under `$OutputDirectory/<PackageName>/<PackageName>.<Version>.nupkg` plus a `tool-receipt.json` manifest; shares the `%TEMP%/QuietCli2` cache-root naming convention with `RunProfiler.psm1` and `Initialize-Profilers.ps1`, though that convention is not itself encoded in this file (the directory is always caller-supplied).
- Network dependency: `powershellgallery.com` and `api.nuget.org` (see URLs in `Get-RunProfilerPackages`), only reached when `-Offline` is not set and the local cache is empty.

## Side effects

- Creates `$OutputDirectory` and per-package subdirectories.
- Writes `.nupkg` archive files when downloading (never deletes/overwrites an existing archive without first checking its hash — see Findings).
- Extracts each archive's entrypoint if missing (`ZipFile::ExtractToDirectoryAsync` with `overwrite=$true`, so extraction *would* overwrite existing extracted files, but only runs when the entrypoint file is absent).
- Writes/overwrites `tool-receipt.json` unconditionally at the end of every call (no existence guard, unlike `RunProfileStore.psm1`'s `Write-RunProfile`).
- Opens an `HttpClient` only when needed; always disposed in the `finally` block (line 57).
- No git interaction.

## Findings

- No bug found in the core verify-before-trust flow: every path (fresh download, cache hit) re-hashes the bytes and compares with case-sensitive ordinal (`-cne`) against the expected SHA-256 before use (lines 46 and 50), which is the right defense against a corrupted or tampered cache entry — and this exact behavior is what the `tool-cache-digest-ignored`/`tool-download-digest-ignored` mutation cases in `RunProfiles.Mutation.ps1` are designed to catch if it regresses.
- DESIGN: if a cached archive exists but fails its hash check (line 50, `ProfilerCacheDigestMismatch`), the function throws rather than attempting a fresh re-download to self-heal the cache. This is a reasonable, security-conscious choice (a mismatched cache entry could indicate tampering, not just corruption) but it does mean an operator hitting a corrupted cache must manually delete the file before retrying — worth a comment explaining the choice was deliberate, since the natural reader expectation might be "cache miss → redownload."
- CONVENTION: the download path (lines 41-45) builds `$bytes` via either `& $DownloadBytes $package.Url` or `$client.GetByteArrayAsync($package.Url).GetAwaiter().GetResult()` — the latter correctly follows the repo's "even in sync PowerShell, use `.GetAwaiter().GetResult()`" convention (AGENTS.md), as does `[IO.File]::WriteAllBytesAsync(...).GetAwaiter().GetResult()` (line 47), `[IO.File]::ReadAllBytesAsync(...).GetAwaiter().GetResult()` (line 49), and `ExtractToDirectoryAsync(...).GetAwaiter().GetResult()` (line 52). No violations of that convention found in this file.
- DESIGN: `Get-RunProfilerPackages` (lines 4-13) hardcodes exact package versions and SHA-256 hashes directly in source rather than in a `.json`/`.psd1` data file; bumping a pinned tool version requires a code change here rather than a data-only change, which somewhat undercuts the "profiles are data, never code" philosophy applied elsewhere in this same `lib/` folder (compare `RunProfileStore.psm1`). This is a minor inconsistency, not a defect.
- No unhandled error path found: `-Offline` is checked before any network/`HttpClient` allocation (line 40), and the `finally` (line 57) ensures the client is disposed even if a checksum mismatch throws mid-loop.
- Testability: strongly covered — `RunProfiles.Profiler.Tests.ps1` exercises offline-hit, offline-miss, corrupted-cache, missing-entrypoint, fresh-download, and download-digest-mismatch paths (per the grep results), and the mutation catalogue specifically targets both digest checks, the layout-mismatch guard, the "skip extraction when already present" optimization (mutated to always re-extract), the explicit `GlobalInstallation=$false` claim in the receipt, and the pinned Profiler version string itself.

## Verdict

Well-designed and thoroughly tested; no rework needed — if anything is worth doing, it is moving the two hardcoded package specs in `Get-RunProfilerPackages` into a small data file so a version bump doesn't require touching this module's code, but that is a low-priority cleanup, not a defect.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Returns the two checksum-pinned diagnostic packages and their required entrypoints.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
