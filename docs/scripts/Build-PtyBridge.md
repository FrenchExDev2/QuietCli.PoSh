# Build-PtyBridge.ps1

## Purpose

Cross-compiles the native PTY bridge binary for Linux x64/ARM64 (both glibc and musl RID folders) from its bundled C source, using a checksum-pinned Zig toolchain, so the module can ship working PTY support without requiring a C toolchain on the build host. It is invoked ad hoc by `artifacts/Run-IndependentPtyWorker.ps1` (line 8), an audit/profiling helper; no match was found in any `.github/workflows/*.yml`, suggesting this is a manually-run step (run when the native C source changes) rather than a step every CI run executes, which is consistent with it rewriting committed binaries and a lock file.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `CompilerPath` | `string` | No | none (resolved automatically on Windows if omitted) |
| `DownloadCompiler` | `switch` | No | off |

```powershell
./scripts/Build-PtyBridge.ps1 -DownloadCompiler
```

## Dependencies

- Dot-sources `Common.ps1` (line 14) for `Invoke-CiProcess`/`Invoke-WorkspaceNative`/`Write-WorkspaceJson`.
- Shells out to the Zig compiler's `cc` driver (`Invoke-WorkspaceNative`, line 48) and to the compiler itself for `version` (`Invoke-CiProcess`, line 35).
- Uses `Invoke-WebRequest` (line 26) to download the pinned Zig archive from `ziglang.org`, and `[IO.Compression.ZipFile]::ExtractToDirectoryAsync` (line 28) to unpack it, only when `-DownloadCompiler` is passed.
- Reads `build/zig.lock.json` (line 16) and `FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json` (line 59).
- Calls `Assert-QuietPtyPublications` (line 67), a function not defined in this file — it is presumably pulled in transitively through `Common.ps1`'s own dot-source chain.

## Side effects

- Downloads and SHA-256-verifies a third-party compiler archive into `artifacts/toolchains/...` (lines 24-28), gated behind `-DownloadCompiler` and a strict URL regex check (line 25).
- Copies two license files into `FrenchExDev2.QuietCli.Core.PoSh/third_party/quietcli-pty/` (lines 40-42).
- Compiles two static binaries (x64, arm64) into `artifacts/pty-build/<arch>/quietcli-pty` (line 46), then copies each into **two** resource directories per architecture — `resources/transport/linux-<arch>` and `resources/transport/linux-musl-<arch>` (line 51) — since the binary is statically linked and works under either libc.
- Rewrites `resources/dependencies.lock.json` in place (lines 58-66), replacing every `resources/transport/*` entry with freshly computed ones.
- Writes a `build.json` manifest per RID directory (line 55).

## Findings

- Good: a post-compile self-integrity check (line 49) re-hashes the C source file after the native compile call returns, to detect concurrent modification during a slow build — a deliberate, well-designed defensive pattern.
- DESIGN: the loop at lines 43-57 ships the identical static-musl binary under both the glibc (`linux-<arch>`) and musl (`linux-musl-<arch>`) RID folders (line 51), which is correct given the `-static` compile flag (line 47), but this sharing is not explained anywhere in the file's own `.SYNOPSIS`/`.DESCRIPTION` — only inferable from the compile flags. A maintainer skimming the RID list in the lock file could mistakenly assume two distinct binaries exist.
- CONVENTION: no `SupportsShouldProcess`/`-WhatIf` guard despite mutating two tracked files inside the module source tree (`resources/dependencies.lock.json` at lines 58-66, and `third_party/quietcli-pty/*` at lines 40-42) that are presumably meant to be reviewed and committed by a human.
- DRY violation: the exact compiler argument list (`'cc','-target',$triple,'-std=c11','-O2','-s','-Wall','-Wextra','-Werror','-fstack-protector-strong','-D_FORTIFY_SOURCE=2','-fPIE','-static','-pie','-Wl,-z,relro,-z,now','-pthread','-lutil',...`) is typed out twice — once as the actual arguments passed at line 47, and again, by hand, inside the `Arguments` field recorded into `build.json` at line 55. If line 47's flags are ever changed without also updating line 55, the recorded provenance manifest silently drifts out of sync with what was actually compiled.
- Testability: no Pester test was found referencing `Build-PtyBridge` anywhere. Only the audit-only `artifacts/Run-IndependentPtyWorker.ps1` invokes it, which is an independent-worker harness, not a committed regression test. A full functional test (requiring a real cross-compile) is expensive, but there is no test at all — not even a cheap static check that the `build.json` `Arguments` field (line 55) matches the literal argument array actually passed to `Invoke-WorkspaceNative` (line 47).

## Verdict

Functionally careful (pinned/verified toolchain download, post-compile source-tamper check), but needs rework on two points: deduplicate the compile-argument list (line 47 vs. line 55) so the recorded manifest cannot drift from what was actually run, and add a minimal regression test — the total absence of test coverage for a script that rewrites a committed, security-relevant lock file is the single highest-priority fix.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds static musl bridges for both Linux libc families without installing software on the host.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
