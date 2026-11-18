# PerformanceStatistics.psm1

<!-- script-source:begin -->
Source file: [`lib/PerformanceStatistics.psm1`](../../../scripts/lib/PerformanceStatistics.psm1)
<!-- script-source:end -->

## Purpose and usage

This module holds the descriptive statistics behind every number in [New-CorePerformanceReport.ps1](../New-CorePerformanceReport.md). It exports two pure functions.

| Export | Contract |
| --- | --- |
| `Get-QuietPerformanceRank` | Nearest rank `ceil(q × n)` for `0 < q ≤ 1` and `n ≥ 1`, so the result is always between `1` and `n`. A quantile that is not finite or is out of range throws `PerformanceQuantileInvalid`. |
| `Get-QuietPerformanceStatistics` | Returns `{Count, Min, Q1, Median, Q3, Max, Iqr, P95, P95Rank, P95IsMax}`. An empty or absent sample returns nothing, so a caller renders `-` rather than zero. NaN and ±∞ throw `PerformanceStatisticsNonFinite`. The caller's array is never reordered. |

- **Median:** the middle value, or the mean of the two middle values when N is even.
- **Quartiles and p95:** nearest-rank observations from the sample, never interpolated.
- **`P95IsMax`:** true when the p95 rank equals N. This is always the case below 20 observations, so the seven fresh imports of a matrix job report the maximum: their p95 describes the worst run, not a stable tail. The report prints `(max)` or `(max of N)` in that case.

```powershell
Get-QuietPerformanceStatistics -Values @(7,1,6,2,5,3,4)
# Count 7, Min 1, Q1 2, Median 4, Q3 6, Max 7, Iqr 4, P95 7, P95Rank 7, P95IsMax True
```

## Dependencies and side effects

None. The module reads nothing, writes nothing and imports nothing.

## Critical review and verdict

- **Nearest rank over interpolation.** Interpolated quantiles would invent values that no run produced, and with so few runs the method choice dominates the result. Nearest rank always names a real observation, and `P95IsMax` makes its weakness explicit.
- **No confidence intervals.** The samples are small and come from shared hosted runners, so an interval would suggest precision that the data does not have. The report gives N, Q1–Q3 and Min–Max instead.
- **Unit-agnostic.** The functions do not know about milliseconds; callers keep one unit per sample.

Verdict: small, exact and honest about small samples.

## Tests

- [`unit/lib/PerformanceStatistics.Tests.ps1`](../../../test/scripts/unit/lib/PerformanceStatistics.Tests.ps1) covers:
  - exact ranks;
  - rejection of invalid quantiles and of non-finite values;
  - the seven-import p95, even and odd medians (including skewed samples), a single observation, and an empty sample that emits nothing;
  - properties:
    - order, with quantiles taken from the sample;
    - independence from input order;
    - translation, where location statistics shift and the spread stays the same;
    - p95 equals the maximum exactly below 20 observations;
  - a finite fuzz that also plants a non-finite value.
- Mutation target `PerformanceStatistics`, `Break` 80.

<!-- script-contract:begin -->
## Execution contract

Purpose: Returns the 1-based nearest-rank position of a quantile in a sorted sample of the given size.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
