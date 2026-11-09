# RunStatistics.psm1

## Purpose

Supplies the statistical primitives needed to tell a real cold-start performance difference apart from machine noise: order statistics (quantiles, five-number summary) and a seeded paired-bootstrap confidence interval of the median of candidate-minus-baseline differences, plus a verdict classifier (`faster`/`slower`/`inconclusive`/`too-few-pairs`). It is the statistics engine behind `scripts/Measure-ColdStart.ps1` (the A/B cold-start comparison tool), used there to summarize per-phase (`Import`, `First call`, `Second call`) timing distributions and to decide whether a ReadyToRun build variant is measurably faster/slower than baseline. Covered directly by `RunProfiles.Tests.ps1` and by nine dedicated mutation cases in `RunProfiles.Mutation.ps1` (lines 82-90) targeting quantile interpolation, even-sample median, seed fixation, one- vs two-tailed alpha, verdict boundary conditions, and bootstrap resampling itself.

## Usage

Exported functions:
- `Get-RunQuantile([double[]] $Values, [double] $Probability)` — both Mandatory; `$Probability` validated to `[0,1]`; throws `RunStatisticsEmptySample` on empty input. Sorts a clone and linearly interpolates.
- `Get-RunSummary([double[]] $Values)` — Mandatory; throws on empty; returns `N, Min, Q1, Median, Q3, Max`.
- `Get-PairedBootstrapInterval` — `-Differences` (Mandatory, `[double[]]`, candidate minus baseline), `-Resamples` (`[int]`, default `2000`, range 100-1,000,000), `-Seed` (`[int]`, default `1`), `-Confidence` (`[double]`, default `0.95`, range 0.01-0.9999). Returns `Pairs, Median, Low, High, Confidence, Resamples`.
- `Get-RunVerdict($Interval, [int] $MinPairs = 20)` — Mandatory `$Interval` (object with `Pairs`, `Low`, `High`). Returns `'too-few-pairs'` if `Pairs < MinPairs`, `'slower'` if `Low > 0`, `'faster'` if `High < 0`, else `'inconclusive'`.

Example:
```powershell
Import-Module ./scripts/lib/RunStatistics.psm1
$diffs = [double[]]@(1.2, -0.3, 0.8, 2.1, -1.0, 0.4, 1.5, 0.9, -0.2, 1.1, 0.3, 0.7, -0.5, 1.8, 0.6, 0.2, 1.0, -0.4, 0.5, 1.3)
$interval = Get-PairedBootstrapInterval -Differences $diffs -Seed 42
Get-RunVerdict $interval   # -> 'slower' | 'faster' | 'inconclusive' | 'too-few-pairs'
```

## Dependencies

- No imports and no `#requires` beyond PowerShell 7.6; this is a pure-math module with zero external tool dependencies (no git/dotnet/docker/network).
- Relies only on `[Math]`, `[Array]::Sort`, and `[Random]` (seeded) from the base class library.

## Side effects

- None. Every exported function is pure (no filesystem, process, or global-state mutation). `Get-PairedBootstrapInterval` allocates `$Resamples`-sized working arrays but these are local.

## Findings

- No bug found; the quantile interpolation (`Get-SortedQuantile`, lines 16-21) and even/odd median handling in the bootstrap loop (lines 88-92) are textbook-correct, and the one/two-tailed alpha split (`$alpha = (1 - $Confidence) / 2`, line 94) is correctly two-sided — this exact line is itself one of the mutation targets (`alpha-one-tail` in `RunProfiles.Mutation.ps1` line 85), which is the right kind of assertion-strength check for a statistics module.
- DESIGN: `Get-RunVerdict`'s default `$MinPairs = 20` (line 114) is a hardcoded business threshold baked into the statistics library itself rather than being a concern of the caller (`Measure-ColdStart.ps1`); moving the floor-pairs policy to the call site would keep this module purely mechanical and let different callers (e.g., a cheaper smoke-test profile with fewer runs) choose their own threshold without a parameter override at every call site. As written it is overridable (it is a parameter with a default), so this is a minor smell rather than an actual limitation.
- CONVENTION: no inline documentation issue — every function has a `.SYNOPSIS`/parameter-level comment block, consistent with the repo's "always write documentation for PowerShell functions" rule.
- Testability: this is one of the best-covered files in the set — `Get-RunQuantile`'s empty-sample guard is asserted in `RunProfiles.Tests.ps1` (line 305, `Assert-Throws { Get-RunQuantile ([double[]]@()) 0.5 } 'RunStatistics'`), and the mutation catalogue specifically targets the quantile-floor interpolation, the even-sample median averaging, seed fixation (to verify the seed is actually load-bearing and not dead code), the one-tailed-alpha regression, both verdict boundary directions (`-gt`/`-ge` and `-lt`/`-le`), the `MinPairs` boundary (`-lt`/`-le`), a wrong-quantile regression in `Get-RunSummary` (`Q3` computed as median), and "no resampling happens" in the bootstrap loop. This is a model example of mutation testing applied to a genuinely risky piece of logic (silent wrong-verdict bugs would be very hard to notice from output alone).

## Verdict

Fit for purpose as-is — correct, pure, and unusually well-covered by targeted mutation tests; the only polish item is considering whether `$MinPairs`'s default belongs in the caller instead of this library, which is not urgent.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
