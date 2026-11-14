# Restore-CoreResources.ps1

## Purpose

Populates Core's pinned managed and native third-party resources — SQLite's `e_sqlite3` for eight
platforms, the three Microsoft.ML.Tokenizers packages plus `Microsoft.Bcl.Memory`, and YamlDotNet — from
their recorded NuGet sources, without checking those binaries into Git. `resources/dependencies.lock.json`
already records each file's expected SHA256 and the NuGet `.nupkg` URL its package came from; this script
is the download side of that manifest, and `ResourceVerifier.cs` (the C# engine) is the runtime side that
re-checks the same hashes before loading. The `quietcli-pty` native binaries are deliberately excluded —
they are source-built by `Build-PtyBridge.ps1` from `native/quietcli-pty.c`, not downloaded packages, and
stay Git-tracked since they are small and cannot be "restored" from a URL.


## Selective, guarded restoration

IncludePackage accepts one or more IDs from the pinned manifest; omitted restores all packages. Unknown IDs fail before creating the cache or starting network access. The GitHub automation check workflow explicitly uses -IncludePackage YamlDotNet before invoking its read-only pipeline, so a clean checkout does not assume an ignored DLL is present. Standard WhatIf/Confirm guards restoration before cache creation, extraction or HTTP requests. File-byte hashes remain verified against resources/dependencies.lock.json.

```powershell
./scripts/Restore-CoreResources.ps1 -IncludePackage YamlDotNet -WhatIf
./scripts/Restore-CoreResources.ps1 -IncludePackage YamlDotNet -Confirm
```
## Usage

```powershell
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Force)
```

- `WorkspaceRoot` (string, optional) — QuietCli2 workspace (the module's parent directory); defaults to
  the script's parent directory.
- `Force` (switch, optional) — redownloads and re-extracts every package even when the local file already
  matches its pinned hash. Without it, a file whose on-disk SHA256 already matches the lock is left alone
  and no network call is made for its package at all.

Example:

```powershell
./scripts/Restore-CoreResources.ps1
./scripts/Restore-CoreResources.ps1 -Force
```

Called automatically by `Initialize-Workspace.ps1 -Restore` (line 27), so the documented clone sequence
(`git clone` → `Initialize-Workspace.ps1 -Restore` → `Build-Workspace.ps1`) and both CI jobs in `ci.yml`
already invoke it; it does not need to be run separately in those paths.

## Dependencies

- Reads `FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json` directly (no dot-sourced
  helper) — `SchemaVersion`/`Packages`/`Files` are consumed with the same shape `ResourceVerifier.cs`
  expects, but this script does not call into `Update-QuietDependencies.ps1` or share code with it; the
  two scripts independently agree on the lock's shape.
- `System.Net.Http.HttpClient` for the download (5-minute client timeout and a matching
  `CancellationTokenSource`), mirroring the async-download pattern in `Initialize-PowerShellHost.ps1`
  (`GetAsync` with `ResponseHeadersRead`, `CopyToAsync(...).WaitAsync(...)`).
- `System.IO.Compression.ZipFile.OpenRead` to read each `.nupkg` as a zip archive without extracting it to
  disk first.
- Caches each downloaded `.nupkg` under `$WorkspaceRoot/.cache/nuget-resources/<id>.<version>.nupkg`
  (gitignored) so a repeated run — or a second package group that happens to need the same file again —
  never re-downloads an already-cached package.

## Side effects

- Network: one `GetAsync` per package group that has at least one file missing or hash-mismatched,
  against the exact `Source` URL recorded in `dependencies.lock.json` (official `api.nuget.org` flat
  container URLs for every package in today's lock).
- Filesystem: writes the cached `.nupkg` under `.cache/nuget-resources/`, and writes each restored file to
  its exact `Path` under `FrenchExDev2.QuietCli.Core.PoSh/`, creating parent directories as needed.
  Existing files whose hash already matches are left untouched (not even re-read after the initial hash
  check) unless `-Force` is passed.
- No Git operation of any kind — it does not stage, commit or otherwise touch the working tree's VCS
  state, consistent with the "no implicit commit/push" rule.
- Returns a `[pscustomobject]` summary (`Restored`, `Reused`, `Total`) — counts individual files, not
  packages, so a single package group with e.g. one stale file out of eight reports `Restored=1`.

## Findings

- DESIGN: matching a restored file inside its `.nupkg` is done purely by content — for every entry in the
  archive whose `Length` equals the expected `Bytes`, its SHA256 is computed and compared to the lock's
  `SHA256`, with no dependency on the package's internal folder layout (`runtimes/<rid>/native/...` for
  SQLite, `lib/<tfm>/...` for the managed assemblies). This is deliberate — the sqlite package's eight
  RID-specific files all share the same `libe_sqlite3.so`/`.dylib`/`e_sqlite3.dll` leaf name, so a
  path-based mapping would need the exact internal layout kept in sync by hand; content-matching instead
  degrades safely (throws `ResourceNotFoundInPackage`) if a future package version renames or restructures
  its internal paths, rather than silently restoring the wrong platform's binary.
- CORRECTNESS (verified by direct test): since multiple ZIP entries inside `sqlitepclraw.lib.e_sqlite3`'s
  `.nupkg` share the same length/name family across RIDs, the `break` on first hash match only works
  because collisions are vanishingly unlikely for distinct native builds; this was exercised directly by
  deleting `resources/runtime/runtimes/win-x64/native/e_sqlite3.dll` and confirming the script restored
  the byte-identical file (hash match) rather than a different platform's build.
- No progress/verbose reporting during a multi-minute first-time restore of several packages — a caller
  watching CI output sees nothing between the job starting and the final summary object, no visible sign
  that is itself a long-running network operation (unlike this repository's usual rule that a test run
  gets a visible monitoring window; a one-shot restore step was judged not to need one, but a developer
  running this interactively with a slow connection has no feedback it is stuck versus still downloading).
- No Pester test exists for this script yet; it was validated manually in this session (delete + restore
  + hash comparison for one tokenizer DLL and one platform-specific SQLite native, both round-tripped
  correctly) rather than through an automated companion test.
- Idempotency is per-file, not per-package: a package group downloads its `.nupkg` once per invocation if
  *any* of its files need restoring, then every pending file in that group is resolved from the one
  in-memory archive — so a partially-stale package group never downloads more than once per run.

## Verdict

Does what `Update-QuietDependencies.ps1`'s hardcoded `Downloaded=$false` return value implied was still
missing: an actual network-restoring counterpart to the lock file, verified end-to-end against the real
`dependencies.lock.json` for both a plain managed DLL and a platform-specific native library. The content-
based ZIP matching is a deliberate, more robust choice than hardcoding each package's internal layout. The
main gap is the lack of a companion Pester test and of any interactive progress feedback during a
first-time, multi-package restore.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Restores Core's pinned managed and native third-party resources (SQLite, tokenizers, YamlDotNet) from their recorded NuGet package sources in resources/dependencies.lock.json, verifying every restored file's SHA256 ag...

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
