# RunColdStart.psm1 (lib)

## Purpose

Provides the measurement primitives used by the cold-start benchmarking tooling: parsing a child process's three reported durations (import, first call, second call), and three ways of measuring a candidate module's on-disk footprint (whole-directory size, only-the-actually-hosted-engine-path size, and compressed-package size). It solves "how big is this module, by which definition of big, and did the measurement child actually return sane numbers" for the cold-start comparison work (ReadyToRun vs IL candidates, etc.). It is consumed by the cold-start measurement chain — `Measure-ColdStart.ps1`, `Invoke-ColdStartMatrix.ps1`, `Invoke-ColdStartGate.ps1`, `Show-ColdStartReport.ps1`/`Show-ColdStartMatrixReport.ps1` all live alongside it in `scripts/` and are the plausible callers for this measurement module (not individually confirmed by direct grep inside this review, but strongly implied by naming and the module's stated purpose).

## Usage

Exported functions (`Export-ModuleMember`, line 90): `ConvertFrom-RunColdSample`, `Get-RunModuleFootprintBytes`, `Get-RunModuleHostedPathBytes`, `Get-RunModulePackageBytes`.

Key signatures:
- `ConvertFrom-RunColdSample -Fields <object[]>` — expects exactly 3 fields (import/first/second milliseconds); throws `ColdSampleInvalid` if the count is wrong or any value fails `[double]::TryParse` with `InvariantCulture`/`NumberStyles.Float`, is non-finite, or is negative.
- `Get-RunModuleFootprintBytes -ManifestPath <string>` — sums every file size under the manifest's containing directory, recursively.
- `Get-RunModuleHostedPathBytes -ManifestPath <string> [-RuntimeIdentifier <string>]` — sums only `lib/engine/<RID>` (CLR11+) or `lib/inprocess` (CLR10/Auto) under the module root; throws `RunModuleHostedPathMissing` if that directory doesn't exist.
- `Get-RunModulePackageBytes -ManifestPath <string>` — packages the module root with `Compress-PSResource` into a throwaway temp directory and returns the resulting `.nupkg` size, always cleaning up the scratch directory.

Example:
```powershell
Import-Module ./scripts/lib/RunColdStart.psm1
$sample = ConvertFrom-RunColdSample -Fields @('120.5','45.2','12.1')
$bytes = Get-RunModuleFootprintBytes -ManifestPath 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh.psd1'
```

## Dependencies

- No dot-sourcing or `Import-Module` of other repo files.
- Calls `Compress-PSResource` (from the `Microsoft.PowerShell.PSResourceGet` module or similar PSResource tooling) — an external dependency not visible in this file, assumed to already be available in the hosting session.
- Filesystem-only otherwise: `[IO.Directory]::EnumerateFiles`, `[IO.FileInfo]`, `Test-Path`.

## Side effects

- `Get-RunModulePackageBytes` creates a temporary directory under `[IO.Path]::GetTempPath()` (line 79) and always removes it in a `finally` block (line 87, `-ErrorAction SilentlyContinue`) — the only side effect in this module, and it is self-contained/non-persistent by design.
- The other three functions are read-only.

## Findings

- No bug found: `ConvertFrom-RunColdSample`'s validation (lines 10–17) is a clean, strict parse with no culture or NaN/Infinity leakage, matching the module's own doc comment that "a measurement child" returns these fields raw.
- DESIGN: `Get-RunModulePackageBytes`'s cleanup uses `-ErrorAction SilentlyContinue` (line 87) on `Remove-Item`, which silently discards any failure to delete the scratch directory (e.g. a locked file from an antivirus scan). This is a minor, low-risk, but real gap: a build agent that repeatedly leaks scratch directories under the temp path because of a transient lock would never be told about it. A warning on failure (rather than fully silent) would be more consistent with the rest of the codebase's instinct to surface — not hide — cleanup failures (compare `Common.ps1`'s explicit `Cleanup='Unconfirmed: worker terminated before cleanup receipt'` tracking).
- CONVENTION: No explicit UTF-8 handling is needed in this file (no text file I/O happens here directly — only binary file sizes and a package operation), so the UTF-8 convention does not apply; no violation to report.
- CONVENTION: No async/`.GetAwaiter().GetResult()` opportunity exists in this file either — all operations are synchronous filesystem enumeration/size queries or a single synchronous `Compress-PSResource` call with no async overload exposed by that cmdlet; not a violation given there's no async API to prefer.
- Testability: `ConvertFrom-RunColdSample`/footprint functions are plausible candidates to be covered by the broader `RunProfiles.*.Tests.ps1`/`RunProfiles.Mutation.ps1` suites found under `FrenchExDev2.QuietCli.Core.Tests.PoSh/`, given those suites' naming overlaps with the run-profile/cold-start tooling area; no test file is named specifically `RunColdStart.Tests.ps1`, so coverage of this exact module could not be confirmed as dedicated, only as plausibly incidental through the broader run-profile suites.
- Minor robustness note (not severe enough for "BUG"): `Get-RunModulePackageBytes` assumes `Compress-PSResource -PassThru` always returns either an `[IO.FileInfo]` or something string-convertible to a valid path (line 83); if the cmdlet's return shape ever changes across PSResourceGet versions, the fallback `[string]$compressed` cast could silently produce a garbage path that then fails the subsequent `Test-Path` check with a reasonably clear `RunModulePackageMissing` error — so the failure mode is at least explicit, not silent, which is good design even if the assumption itself is implicit.

## Verdict

A small, focused, side-effect-light measurement module with no bugs found; the one worth addressing is the fully silent cleanup-failure suppression in `Get-RunModulePackageBytes` (line 87), which should at least log a warning rather than discard the failure entirely.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
