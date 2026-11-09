# RuntimeDiagnosis.psm1

## Purpose

Turns raw container/host probe observations (architecture, OS, ELF machine code, libc flavor, reported .NET runtime identifier, native-asset hash-verification outcomes) into a bounded, conservative diagnosis of *why* a container image might be failing to select the expected native runtime assets (e.g. `linux-musl-arm64` vs `linux-x64`), without ever claiming more than the evidence supports. It exists because a SQLite/native-asset load succeeding proves only that one diagnostic load worked — never whole-product or release compatibility — and the module is explicit about that (`WholeProductCompatibilityProven=$false`, `Qualification='DiagnosticOnly'`, line 117). It is called by `scripts/Invoke-ContainerRuntimeDiagnosis.ps1` (the orchestrating script that actually launches the probes) and is covered by a dedicated `RuntimeDiagnosis.Tests.ps1`, with its output format documented in `docs/audits/2026-11-09-container-runtime-diagnosis.md` / `.json`.

## Usage

Exported function:
- `Get-QuietRuntimeDiagnosis` — `[CmdletBinding()]`, parameters: `-Image` (positional, curated image identity with `Architecture`/`Os`), `-Observations` (`[object[]]`, `AllowNull`/`AllowEmptyCollection`, default/explicit runtime-root probe results), `-ExpectedRuntimeIdentifier` (Mandatory, `[string]`, must match `^linux-(musl-)?(x64|arm64)$`), `-ExpectedRuntimeMajor` (`[int]`, range 10-99, default `10`).
- Returns a `[pscustomobject]` with `SchemaVersion`, `Decision` (one of `ArchitectureMismatch`, `Inconclusive`, `HostUnavailable`, `BootstrapAndAssetSelection`, `AssetSelection`, `NativeAssetsUnusable`, `BootstrapConfiguration`, `NoMismatchObserved`), `Findings[]`, `NextSteps[]`, plus supporting evidence fields.
- Also exposes `Get-QuietDiagnosisValue($InputObject, [string] $Name)` as a module-scope helper (not exported) for duck-typed reads across hashtables/`PSObject`s without treating a missing/malformed field as established evidence.

Example:
```powershell
Import-Module ./scripts/lib/RuntimeDiagnosis.psm1
$diagnosis = Get-QuietRuntimeDiagnosis -Image $image -Observations $probeResults -ExpectedRuntimeIdentifier 'linux-musl-arm64' -ExpectedRuntimeMajor 11
$diagnosis.Decision      # e.g. 'AssetSelection'
$diagnosis.NextSteps     # actionable, non-prescriptive remediation hints
```

## Dependencies

- No `Import-Module`/dot-source dependencies; pure PowerShell logic over plain objects.
- Depends entirely on the *shape* of its caller's probe observation objects (`Probe.SchemaVersion`, `.Phase`, `.Linux`, `.ProcessArchitecture`, `.OSArchitecture`, `.ElfMachine`, `.FrameworkMajor`, `.Libc`, `.RuntimeIdentifier`, `.RawNative`, `.ExpectedNative`) — this contract is implicit and enforced only by field-presence/type checks inside this function, not by a shared schema/type definition.
- No external tool invocation in this module itself (the actual container probing/launching is presumably done by the caller, `Invoke-ContainerRuntimeDiagnosis.ps1`).

## Side effects

- None — pure function, no filesystem/process/network side effects.

## Findings

- No bug found in the core decision tree after tracing it through: the `elseif` chain (lines 99-107) is ordered so `ArchitectureMismatch` and basic-evidence-sanity checks (`Inconclusive` for non-Linux image or unrecognized arch) take priority over the finer-grained `BootstrapAndAssetSelection`/`AssetSelection`/`NativeAssetsUnusable`/`BootstrapConfiguration` classifications, which matches the stated design goal of never overclaiming.
- DESIGN: the function is a single ~70-line body (lines 18-118) with deep nested boolean accumulation (`$imageMismatch`, `$bootstrapFault`, `$selectionFault`, `$ridMismatch`, `$nativeFailure` all computed across two separate `foreach` loops over `$Observations`/`$usable`). This violates the "cohesive responsibility, separate parsing from policy" guidance in `AGENTS.md`'s SOLID/DRY section: evidence extraction (reading/validating each probe), per-probe usability filtering, and decision-tree policy are all interleaved in one function body rather than split into named helper functions (e.g. `Test-ProbeUsable`, `Get-ArchitectureMismatch`, `Get-Decision`). This makes the file hard to unit-test at a finer grain than "the whole decision for a given observation list."
- CONVENTION: the file has no blank lines/consistent spacing (e.g. lines 39-43, 48-74) — dense, semicolon-joined single-line statements throughout. This is a readability concern, not a correctness one, but it works against the "no catch-all utility classes" and general maintainability expectations the AGENTS.md SOLID section asks for; a reviewer unfamiliar with the file will need significant time to verify the boolean logic by eye (as this review did).
- No input validation gap found for the Mandatory/`ValidatePattern`/`ValidateRange` parameters; however, `-Observations` elements are duck-typed via `Get-QuietDiagnosisValue` with no schema assertion, so a probe object with unexpected field *types* (e.g. `RuntimeIdentifier` as a non-string) is silently treated as "doesn't count" (`continue`, line 67) rather than flagged as malformed input — this is intentional per the module's `.DESCRIPTION` ("Preserves reported RIDs verbatim... Incomplete evidence is inconclusive") but means a bug in the probe-emitting code (wrong field name/type) would silently degrade to `Inconclusive` rather than surfacing as an error.
- Testability: has a dedicated `RuntimeDiagnosis.Tests.ps1` file and is referenced by an actual audit run (`docs/audits/2026-11-09-container-runtime-diagnosis.{md,json}`), which is good evidence of both unit and real-world validation. No mutation-test entries for this file were found in `RunProfiles.Mutation.ps1` (that catalogue is scoped to the run-profile/statistics/tool-cache family), which is a gap given the decision tree's branch count and the stated goal of this module being conservative/non-overclaiming — a wrong boundary here (e.g. `$bootstrapFault -and $selectionFault` vs `-or`) would be exactly the kind of defect mutation testing is meant to catch.

## Verdict

Functionally sound and appropriately conservative in its claims, but the single monolithic function mixing evidence-extraction and decision-policy is a maintainability risk; the highest-priority fix is splitting `Get-QuietRuntimeDiagnosis` into smaller, independently testable helpers (probe validation/usability vs. the final decision mapping) and adding mutation coverage for the decision-tree boundaries.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
