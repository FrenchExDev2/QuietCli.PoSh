# Probe-ContainerRuntime.psm1

Implements [Probe-ContainerRuntime.ps1](../Probe-ContainerRuntime.md). Exports only "Invoke-QuietScriptProbeContainerRuntime". Imported without name checking; import defines the command without running the operation.

# Probe-ContainerRuntime.ps1

## Purpose

Runs *inside* an owned, networkless Linux diagnostic container (never on the host) to collect host/runtime identity (libc family, ELF machine type, framework version, `DOTNET_ROOT*` variables) and to explicitly load exactly one checksum-verified `libe_sqlite3.so` asset, without ever initializing the product's database or engine. It solves the problem of diagnosing SQLite/.NET native-interop mismatches (musl vs glibc, wrong architecture) across container base images, independently of the product's own startup path. It is invoked exclusively by `Invoke-ContainerRuntimeDiagnosis.ps1`, which copies this script (along with `Ci.Process.ps1` and `RuntimeTargets.ps1`) into the container and runs it via `podman exec ... pwsh -File /diagnostic/Probe-ContainerRuntime.ps1 ...` (confirmed at `Invoke-ContainerRuntimeDiagnosis.ps1` lines 86 and 110).

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `OutputPath` | `string` | Yes | — |
| `AssetsRoot` | `string` | Yes | — |
| `ExpectedRuntimeIdentifier` | `string` (`ValidatePattern('^linux-(musl-)?(x64|arm64)$')`) | Yes | — |

```powershell
pwsh -File /diagnostic/Probe-ContainerRuntime.ps1 `
    -OutputPath /diagnostic/Default.json `
    -AssetsRoot /diagnostic/assets `
    -ExpectedRuntimeIdentifier linux-x64
```

## Dependencies

- Dot-sources `Ci.Process.ps1` and `RuntimeTargets.ps1` (lines 16-17) — relative to its *own* `$PSScriptRoot`, which is the `/diagnostic` staging directory inside the container (not the original `scripts/` folder), since `Invoke-ContainerRuntimeDiagnosis.ps1` copies these three files together (line 86) before invoking this one.
- Uses `[Runtime.InteropServices.NativeLibrary]::Load`/`GetExport`/`Free` (lines 42-48) to dynamically load the candidate `libe_sqlite3.so` and call its `sqlite3_libversion` export through a `Cdecl` delegate built via `Add-Type` (lines 63-69) — this is the one place in the file that genuinely touches unmanaged/native surface.
- Reads `/proc/self/maps` and `/etc/os-release` (lines 53, 56) — hard Linux-only filesystem assumptions; the script will fail immediately (or behave unpredictably) outside a Linux container, which is intentional given its sole caller only runs it inside Linux containers.
- Reads `assets.json` (line 50) from `-AssetsRoot`, an inventory file written by the caller (`Invoke-ContainerRuntimeDiagnosis.ps1` line 94) describing expected per-RID SHA-256 hashes.
- Assumes `AssetsRoot` is laid out as `<AssetsRoot>/<Rid>/libe_sqlite3.so` beside an `assets.json` sibling.

## Side effects

- Writes `OutputPath` multiple times during execution (`Save-RuntimeProbe`, called at lines 62, 70, 72, 74) — once per phase (`Identity`, `RawNativeLoad`, `ExpectedNativeLoad`, `Complete`) — explicitly so that a crash mid-probe still leaves the last completed phase's JSON on disk for diagnosis (stated intent in the `Save-RuntimeProbe` synopsis, lines 19-21). This is a deliberately good crash-forensics pattern.
- Loads (and later frees) a native shared library into the current process via `NativeLibrary::Load`/`Free` (lines 42, 48) — the only true runtime/process-level side effect, and it is explicitly scoped (loaded, queried, freed) rather than left resident.
- No network access, no git, no writes outside `OutputPath`.

## Findings

- No correctness bugs were found in the phase-sequenced JSON-writing or in the native-load/free lifecycle (the `try/finally` at lines 41-48 correctly frees the handle even on failure).
- `Save-RuntimeProbe` (lines 18-23) uses `[IO.File]::WriteAllTextAsync(...).GetAwaiter().GetResult()` (line 22) — correctly following the repo's async-preference convention even in this otherwise synchronous script. Good compliance, not a defect.
- CONVENTION: the file is written in the same extremely dense, multi-statement-per-line style noted in other scripts in this batch (e.g. line 57's single-line `[ordered]@{...}` spanning many fields, lines 53-54, 56 packing loops/conditions onto one line each). This matches the pre-existing style critique in `docs/audits/2026-11-08-ecosystem-usage-review.md` for sibling scripts in this folder, and applies equally here — it materially reduces readability for a security/diagnostics-sensitive script that others will need to audit carefully.
- DESIGN: `Invoke-RuntimeNativeProbe` (lines 24-49) validates `$Rid` with a regex and an explicit `..` check (line 31) before building a file path from it — this is good input sanitization given `$Rid` ultimately traces back to caller-controlled data (`$report.RuntimeIdentifier` or `$ExpectedRuntimeIdentifier`), and the `ValidatePattern` on `$ExpectedRuntimeIdentifier` (line 14) further constrains the explicit-target path. No path-traversal weakness found.
- Security observation (not a defect, worth documenting): this script dynamically loads and calls into an arbitrary native library via `NativeLibrary::Load` + a hand-built function pointer delegate (lines 42-45) based on a hash comparison against `assets.json` (line 36). The hash check is a meaningful integrity gate, but `assets.json` itself is written by the *caller* script and copied into the container alongside the assets — i.e. the integrity of this diagnostic is only as strong as the caller's staging step, which this script correctly does not try to re-verify beyond the hash comparison it's given. This is appropriate scoping, not a bug, but worth flagging as a trust boundary for any future reviewer: `assets.json` must itself come from a trusted build artifact, never user input.
- Testability: no Pester test was found covering this script directly, and none plausibly can without a real Podman/Linux container (its only consumer, `Invoke-ContainerRuntimeDiagnosis.ps1`, is itself clearly designed for manual/CI container runs, not unit testing). This is an explicit, acknowledged qualification gap rather than an oversight — but per the repo's mandatory property/fuzz/mutation-testing policy, the pure, container-independent helper logic here (RID validation regex, hash comparison, the ELF-machine/libc-family compatibility check at line 39) is exactly the kind of logic that *could* be extracted and unit-tested in isolation (e.g. as a function in a `.psm1` with injectable file-system/hash inputs), and currently is not.

## Verdict

Fit for purpose for its narrow diagnostic role; the phase-sequenced crash-forensics writes and the explicit hash-gated native load are solid design choices. The highest-priority improvement is testability: extract the RID-validation/hash-comparison/compatibility-check logic in `Invoke-RuntimeNativeProbe` (lines 24-49) into a pure, injectable function so it can be exercised by a Pester unit test without a real container, closing the current test-coverage gap.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Collects Linux host identity and explicitly loads verified SQLite assets inside an owned diagnostic container.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
