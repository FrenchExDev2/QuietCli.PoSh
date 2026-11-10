# RunColdStart.psm1 (lib)

## Purpose and usage

Primitives shared by Measure-ColdStart.ps1: ConvertFrom-RunColdSample validates exactly three finite, nonnegative invariant-culture durations; Get-RunModuleFootprintBytes sums all module files; Get-RunModuleHostedPathBytes measures the active engine slot; Get-RunModulePackageBytes measures an actual Compress-PSResource nupkg.

```powershell
Import-Module ./scripts/lib/RunColdStart.psm1
Get-RunModuleHostedPathBytes -ManifestPath <module-manifest> -RuntimeIdentifier linux-arm64
```

ManifestPath is required for footprint/package helpers. RuntimeIdentifier defaults to the actual host RID. Get-RunModuleHostedPathBytes resolves the module's Protocol.ps1 when available: CLR 10 uses lib/inprocess, CLR 11+ uses lib/engine, with the matching R2R child only when the current portable manifest selects it. Minimal fixtures without Protocol.ps1 use the portable path for the actual CLR. Missing active paths fail explicitly. Inactive RID child directories are excluded from portable footprint, while ordinary dependency subdirectories remain counted.

## Dependencies and side effects

Uses host .NET filesystem APIs and the existing RunEncoding helpers; package measurement additionally requires Microsoft.PowerShell.PSResourceGet. Footprint and sample parsing are read-only. Package measurement stages temporary package output and cleans up its owned directory. No native process, build, remote repository or publication is implied.

## Critical review

- `scripts/lib/RunColdStart.psm1:38` follows actual CLR/RID loading instead of the PowerShell marketing version. Whole-module footprint and active-path footprint are distinct quantities.
- The resolver is read from the measured module, making baseline/candidate selection match the code actually imported. It does not import the business module or load a native assembly just to measure bytes.
- RunProfiles.Benchmark.Tests.ps1 covers generated durations, malformed/nonfinite samples, nested/active-path bytes, ignored RID directories, paired order/failure budgets and a real fresh-process A/A smoke. The R2R policy campaign separately covers all RID/CLR selection combinations.
- Byte counts and header presence do not establish a startup speedup; the paired A/A-gated measurement remains required for performance claims.

## Verdict

Shared measurement primitives retain separate whole-package and loaded-path costs for portable and R2R builds.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Validates the three invariant-culture, finite, nonnegative durations returned by a measurement child.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
