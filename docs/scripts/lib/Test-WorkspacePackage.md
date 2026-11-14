# Test-WorkspacePackage.psm1

Implements [Test-WorkspacePackage.ps1](../Test-WorkspacePackage.md). Exports only "Invoke-QuietScriptTestWorkspacePackage". Imported without name checking; import defines the command without running the operation.

# Test-WorkspacePackage.ps1

## Purpose

Verifies, byte-for-byte, a complete set of distributable package archives (one ZIP + one
`.manifest.json` per business/test module) before anything is extracted or imported, protecting the
rest of the distribution pipeline from a tampered, truncated, or malformed package set. This is the
hard security/integrity gate that sits between "a package set exists on disk" and "it is safe to
extract and optionally execute" in the publish/distribution flow — its own `.SYNOPSIS` states it
"Verifies a complete package set without executing it" and `TestImport` must be explicitly requested
to run anything at all. It is called directly by `Verify-Distribution.ps1` (a thin JSON-emitting
wrapper around it) and is the subject under test of the fuzz/mutation-style
`FrenchExDev2.QuietCli.Core.Tests.PoSh\audit\Package.Tests.ps1` (via
`FrenchExDev2.QuietCli.Core.Tests.PoSh\audit\Probe-Package.ps1`, confirmed at line 20:
`& (Join-Path $WorkspaceRoot 'scripts/Test-WorkspacePackage.ps1') -PackageDirectory ... -ExtractionDirectory ...`).

## Usage

```
[CmdletBinding()]param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$ExtractionDirectory,
    [switch]$TestImport,
    [ValidateRange(1,100000)][int]$MaxFiles=10000,
    [ValidateRange(1,1073741824)][long]$MaxFileBytes=134217728,
    [ValidateRange(1,4294967296)][long]$MaxTotalBytes=536870912
)
```

- `PackageDirectory` (string, mandatory) — directory holding the trusted-source archives and
  manifests. The doc comment explicitly warns: "Hashes alone do not authenticate their author."
- `ExtractionDirectory` (string, mandatory) — new destination this run will create and own; the script
  refuses to run if it already exists (line 95).
- `TestImport` (switch, optional) — explicitly executes the verified Core and Git modules (via
  `Import-Module`) after every archive passes verification. Without it, nothing is imported or run.
- `MaxFiles` (int, optional, range 1-100000, default `10000`) — maximum file count across the whole
  distribution.
- `MaxFileBytes` (long, optional, range 1-1 GiB, default `134217728` = 128 MiB) — maximum uncompressed
  size of a single file.
- `MaxTotalBytes` (long, optional, range 1-4 GiB, default `536870912` = 512 MiB) — maximum total
  uncompressed distribution size.

Example:

```powershell
./scripts/Test-WorkspacePackage.ps1 -PackageDirectory ./artifacts/packages/20261109 -ExtractionDirectory ./artifacts/verify-20261109 -TestImport
```

## Dependencies

- Dot-sources `WorkspaceProjects.ps1` (line 96) for `Get-QuietWorkspaceProjects`, used to compute the
  expected module-name catalogue.
- No external process is shelled out to; uses only `System.IO.Compression.ZipFile`,
  `System.IO.FileStream`, and `System.Security.Cryptography.IncrementalHash`.
- `-TestImport` temporarily prepends `ExtractionDirectory` to `$env:PSModulePath` (line 171) and calls
  `Import-Module` on every non-test project's `.psd1`/`.psm1` from the *just-verified, just-extracted*
  copy — i.e. it does execute PowerShell module code from the package when explicitly asked to.
- Filesystem assumption: the number of `*.manifest.json` and `*.zip` files in `PackageDirectory` must
  exactly equal the number of projects `Get-QuietWorkspaceProjects` discovers in the *current, live*
  workspace (line 101) — the verifier's catalogue of "expected modules" comes from the live source
  tree next to the script, not from anything inside the package set itself.

## Side effects

- Phase one (lines 106-144): purely read-only validation and hashing of every ZIP member — no
  extraction yet, as the inline comment at line 105 states.
- Phase two (lines 146-166): creates `ExtractionDirectory` via an atomically-renamed temp directory
  (lines 147-149, with POSIX permission bits set via `UnixFileMode` on non-Windows), then copies only
  the already-validated entries into it, re-hashing each file during the copy to catch a
  "replacement race" (a file changed on disk between phase one and phase two) — this is a genuine
  TOCTOU mitigation, not decorative.
- `-TestImport`: imports modules from the newly extracted directory (real `Import-Module` execution,
  including any module-initialization code) and counts registered `Get-QuietHandler` entries; restores
  `$env:PSModulePath` in a `finally` block afterward.
- Throws a specific, named error (`ArchiveUnsafePath`, `ArchiveHashMismatch`,
  `ArchiveModuleBoundaryViolation`, `ArchiveChangedAfterValidation`, etc.) on the first violation found,
  aborting the whole verification — no partial/best-effort result is ever returned.

## Findings

- No bugs found in the core ZIP-bomb and path-traversal defenses after close reading:
  `Assert-PackageRelativePath` (lines 30-42) rejects backslashes, drive letters, leading `/`, NUL
  bytes, `.`/`..` segments, trailing dot/space (Windows short-name tricks), reserved device names
  (`CON`, `PRN`, `NUL`, `COM1-9`, `LPT1-9`), and control/`<>"|?*` characters — a thorough allowlist-style
  check, not a naive blacklist. `Assert-PackageDirectoryBounds` (lines 43-69) manually parses the ZIP
  End-Of-Central-Directory record to bound entry count/size *before* `ZipArchive` ever materializes
  entries, specifically to avoid `ZipFile.OpenRead` itself being a zip-bomb vector — a genuinely careful
  design.
- No bugs found in `Copy-PackageEntryBounded` (lines 70-94): it hashes actual decompressed bytes while
  enforcing the *declared* size strictly during the read loop (throwing `ArchiveActualSizeLimit` the
  moment actual bytes exceed the declared count), which defeats a manifest that under-declares a file's
  true size to sneak past per-file quotas.
- DESIGN: the "expected module set" is derived from the live workspace next to the script (line 97-98),
  not from any signed/pinned list embedded in the package set itself. This means if someone runs this
  verifier against a package built from a different (older/newer) commit than the checkout it's run
  from, a legitimately-structured older package could be rejected as "PackageSetIncompleteOrUnexpected"
  purely because the module list changed — not a security bug, but a potential false-positive/negative
  source worth being aware of operationally; the verifier's notion of "expected" is coupled to whatever
  checkout happens to be sitting next to it when it runs.
- CONVENTION: uses `.ReadAsync(...).GetAwaiter().GetResult()` and `.WriteAsync(...).GetAwaiter().GetResult()`
  consistently throughout (lines 59, 85, 89, 90) — this script actually follows the async-even-in-sync
  convention well, unlike several of its siblings in this review batch.
- Testability: well covered — `FrenchExDev2.QuietCli.Core.Tests.PoSh\audit\Package.Tests.ps1` /
  `Probe-Package.ps1` drive this exact script through synthetic fixtures covering `foreign` (module
  boundary violation), `case` (duplicate path on case-insensitive collision), `traversal` (unsafe
  path), `file-quota`, and `byte-quota` attacks, plus a `normal`/non-executing positive case — this is
  a genuine fuzz/mutation-style security test suite for the script's primary job (rejecting malformed
  or hostile package sets), which is exactly what AGENTS.md's testing strategy calls for. No test was
  found, however, that exercises `-TestImport` itself (the actual module-execution path) or the
  phase-two "replacement race" re-validation specifically (i.e. mutating a file on disk between phase
  one and phase two of a single run) — that TOCTOU-mitigation code path appears to rely on manual
  review rather than an automated regression test.
- No other security concerns beyond the above: the comment "Hashes alone do not authenticate their
  author" (doc comment, `PackageDirectory`) correctly sets expectations that this script verifies
  integrity, not provenance/signing — consistent with the `Authenticated=$false` field always present
  in its return object (line 178).

## Verdict

This is the strongest-designed script in this review batch — careful, defense-in-depth path and
size validation with genuine fuzz-test coverage for its core security job. The one gap worth closing
is a regression test for the phase-two "replacement race" re-validation path (mutate a file between
phase one and two in a test) and for the `-TestImport` code path, since both currently rely on manual
review rather than automated tests.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Verifies a complete package set without executing it; TestImport explicitly enables an import smoke check afterwards.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
