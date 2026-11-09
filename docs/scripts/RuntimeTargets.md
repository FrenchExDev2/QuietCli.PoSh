# RuntimeTargets.ps1

## Purpose

Provides the shared, read-only catalogue of every runtime identifier (RID) the QuietCli2 engine ships for, plus a set of low-level binary-header inspection and assertion functions used to verify that a built/packaged artifact's native architecture actually matches what the catalogue claims — without ever executing the binaries being inspected. It solves the supply-chain problem of "does the thing we are about to package/publish for `linux-musl-arm64` actually contain a `linux-musl-arm64` binary, or did a build step silently produce the wrong architecture." It is dot-sourced by `Common.ps1` (line 5) and therefore available to nearly every other script in this batch; it is used directly by `New-WorkspacePackage.ps1` (lines 16-22, via `Assert-QuietPtyPublications`/`Get-QuietRuntimeTargets`/`Test-QuietBuildManifest`), by `Probe-ContainerRuntime.ps1`'s header check logic indirectly through `Invoke-ContainerRuntimeDiagnosis.ps1` (which dot-sources this file at line 86/90), and by `Gallery.ps1`'s package-set validation (`Get-QuietRuntimeTargets`, line 155 of that file).

## Usage

This file defines four functions; it is always dot-sourced, never invoked directly as a script (no top-level `param()`).

| Function | Parameters | Purpose |
|---|---|---|
| `Get-QuietRuntimeTargets` | `WorkspaceRoot` (string) | Reads and returns `.Targets` from `FrenchExDev2.QuietCli.Core.PoSh/runtime-targets.json`. |
| `Get-QuietElfHeader` | `Path` (string) | Reads a bounded 64-byte ELF64-LE header and program-header table; returns `Machine` and `HasInterpreter`. |
| `Assert-QuietRuntimePublication` | `Directory` (string), `Target` (object) | Verifies a RID directory's managed DLL and apphost architectures against the catalogue entry; throws on mismatch. |
| `Assert-QuietPtyPublications` | `WorkspaceRoot` (string) | Verifies every shipped Linux PTY bridge binary is static, has the expected machine type, and matches its source hash receipt. |

```powershell
. (Join-Path $PSScriptRoot 'RuntimeTargets.ps1')
$targets = Get-QuietRuntimeTargets $WorkspaceRoot
foreach ($rid in $targets.Rid) { Assert-QuietRuntimePublication (Join-Path $publishRoot $rid) ($targets | Where-Object Rid -eq $rid) }
```

## Dependencies

- None at the top of the file itself, but it calls `Get-QuietPeMachine` (lines 42, 44) — a function **not defined in this file**, implying it is defined elsewhere in the dependency chain (likely in `Common.ps1`'s other dot-sourced files such as `SourceIdentity.ps1`, not reviewed in this batch) and simply assumed to be in scope by the time this file's functions run.
- Reads `FrenchExDev2.QuietCli.Core.PoSh/runtime-targets.json` (line 10) and, in `Assert-QuietPtyPublications`, reads `native/quietcli-pty.c` (line 56) and per-RID `resources/transport/<rid>/build.json` receipts (line 60) — all pure file reads, no external process is shelled out to.
- `Get-QuietElfHeader` opens the target file directly with `[IO.File]::OpenRead` and a raw `[IO.BinaryReader]` (lines 21-22) — it never loads or executes the binary, consistent with its own `.SYNOPSIS` ("never loaded into PowerShell").

## Side effects

None. Every function in this file is read-only: it reads JSON/C-source/binary files from disk and either returns data or throws on a mismatch. Nothing is written, deleted, or mutated.

## Findings

- `Get-QuietElfHeader` (lines 13-31) is careful, bounded binary parsing: it validates the ELF magic bytes and class/endianness (`127,69,76,70,2,1` at offsets 0-5, line 24), validates the program-header entry size and count are sane (`$size -lt 56`, `$count -gt 1024`, line 26) before trusting them, and bounds-checks that `$offset + $count*$size` does not exceed the stream length (line 26) before seeking into it. This is exactly the kind of defensive parsing a security reviewer wants to see when parsing an externally-produced binary header, and no gap was found in it.
- `Assert-QuietPtyPublications` (lines 47-63) layers four independent checks before trusting a shipped PTY binary: machine-type match, absence of a dynamic interpreter segment (`!$header.HasInterpreter`, confirming the binary is statically linked, line 61), a source-hash match against the current `quietcli-pty.c` (line 56/61), and an executable-hash match against its own recorded build receipt (line 61). This multi-factor verification is a strong, well-reasoned supply-chain check; no weakness was found in its logic.
- DESIGN: `Get-QuietPeMachine`, used twice in `Assert-QuietRuntimePublication` (lines 42, 44), is referenced but not defined anywhere in this file — this file is therefore not self-contained, and a reader auditing only `RuntimeTargets.ps1` cannot fully verify `Assert-QuietRuntimePublication`'s correctness without also locating that function's definition elsewhere in the `scripts/` tree. This is a minor documentation/discoverability gap rather than a bug (the function clearly works, since `New-WorkspacePackage.ps1` relies on this file's sibling functions successfully), but a one-line comment noting where `Get-QuietPeMachine` lives would help.
- CONVENTION: the file continues the same extremely dense, single-line-per-function-body style seen elsewhere in this folder (e.g. line 61's entire multi-condition `if` spanning one very long line) — consistent with the pre-existing style critique in `docs/audits/2026-11-08-ecosystem-usage-review.md` for sibling scripts, equally applicable here. Given this file implements genuinely security-relevant binary verification logic, the readability cost of this style is higher here than in a purely administrative script.
- No input-validation gap of note: `Get-QuietElfHeader`'s `Path` parameter is used only to open a file for reading (no execution, no shell invocation), so there is no injection surface; any malicious or malformed input would at worst cause a thrown parse exception, which is the intended, safe failure mode.
- Testability: no Pester test was found exercising these functions directly (no `*Tests*.ps1` match for `RuntimeTargets` in this repo, per an earlier search). Given this file implements genuinely security-sensitive binary-header parsing and multi-factor publication verification that gates what gets shipped to the public PSGallery package (via `New-WorkspacePackage.ps1` → `Gallery.ps1`), the complete absence of a dedicated unit test — e.g. constructing synthetic valid/truncated/oversized/malicious ELF headers and asserting `Get-QuietElfHeader` accepts or rejects each correctly — is a real, identifiable gap relative to the repo's own mandatory property-testing/fuzzing policy for "parsers... state/stream sequences."

## Verdict

The binary-verification logic itself is well-designed and defensively written, but it needs rework on the testing front: given its role gating what architecture-sensitive binaries ship to the public package, the highest-priority fix is adding a dedicated Pester test suite (ideally with property/fuzz-style synthetic ELF header fixtures — truncated, oversized program-header counts, wrong magic bytes, mismatched machine types) for `Get-QuietElfHeader` and `Assert-QuietPtyPublications`, since none currently exists.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
