# New-CorePerformanceReport.ps1

## Purpose

Turns one or many `evidence-manifest.json` bundles (produced by `New-CoreEvidenceBundle.ps1`, possibly across a whole GitHub Actions matrix) into a single human-readable Markdown report (`PERFORMANCES_RESULTS.md`) plus a machine-readable JSON twin, without requiring the reader to open a raw CLR trace viewer. It re-verifies every referenced file's SHA-256 against the manifest before trusting it, explicitly marks the evidence status as INCOMPLETE/FAILED whenever any gap is found, and is deliberately conservative about what its numbers mean (documents that CLR frame-name counts are "not CPU percentages," that allocations are "cumulative managed allocations... not retained memory," etc.). It is called three times from `.github/workflows/ci.yml` (lines 171, 333, 366) — per-job and for the final combined matrix report with `-ExpectedReports 10` — and directly tested by `Evidence.Tests.ps1` (line 34).

## Usage

Parameters:
- `-EvidenceRoot [string]` — one published bundle, or the directory containing every downloaded matrix bundle.
- `-OutputDirectory [string]` — report destination; may equal a bundle root, but must never be a raw report input directory (not programmatically enforced in this file the way `New-CoreEvidenceBundle.ps1` enforces its own boundary — see Findings).
- `-Revision [string]` — expected exact workflow revision; any manifest with a different `Revision` is rejected as a gap (line 61).
- `-ExpectedReports [int]` (default `0`, disables the check) — required matrix receipt count.
- `-Suite [string]` (`ValidateSet('Core','All','Git','Integration')`, default `'All'`) — `Core`/`All` requires integration and profiling evidence to be present; `Git` reports those as explicitly out of scope rather than missing.

Example (from `ci.yml`, final combined report):
```powershell
./scripts/New-CorePerformanceReport.ps1 -EvidenceRoot ./artifacts/matrix-evidence -OutputDirectory ./artifacts/performance-results -Revision $env:GITHUB_SHA -ExpectedReports 10 -Suite $env:QUIETCLI_SUITE
```

## Dependencies

- Dot-sources `Common.ps1` (line 18) for `Write-WorkspaceJson`.
- Pure filesystem/JSON/hashing — `Get-ChildItem -Recurse -Filter evidence-manifest.json`, `Get-FileHash -Algorithm SHA256`, `ConvertFrom-Json`/`ConvertTo-Json`. No external process, no git, no network.
- Assumes each bundle's `summary.json` (or `guest/summary.json`) follows the shape produced by the test runner elsewhere in the repo: `.Suites[].Project/.Performance/.Integration`, `.Profiling.TargetIdentity.EngineMode/.Collectors[].ObservedFrameNames`, `.State.Platform/.State/.Passed/.Failed`, `.PowerShellVersion`, `.HostRuntime` — this contract is implicit and version-coupled to whatever test-runner code emits `summary.json` (not part of this review's file list).
- Writes using `[Text.UTF8Encoding]::new($false)` directly (line 162) rather than via `RunEncoding.psm1` — see Findings.

## Side effects

- Creates `-OutputDirectory` if missing.
- Writes `PERFORMANCES_RESULTS.md` (UTF-8 no-BOM, explicit `.Replace("`r`n","`n")` normalization to LF, line 162) and `PERFORMANCES_RESULTS.json` (via `Write-WorkspaceJson`) into `-OutputDirectory`.
- Reads/updates an existing `evidence-manifest.json` in `-OutputDirectory` if present (merging in the two new report files' hash entries, lines 165-168), or writes a fresh one with `SourceManifests` provenance if not (lines 169-175) — i.e. this script can itself produce a *second* evidence-manifest layered over the input manifests, which is a sensible chained-provenance design.
- Throws `PerformanceReportEvidenceIncomplete` at the end (line 177) if any gap was recorded — fails the CI step.
- No git interaction, no network, no process spawn.

## Findings

- No bug found in the markdown-escaping helper (`ConvertTo-ReportCell`, lines 19-29): it correctly escapes `|`, strips/replaces CR/LF, and HTML-escapes `<`/`>` before embedding untrusted metadata (file paths, gap descriptions, scenario names) into a Markdown table cell — this is exactly the right defense against a malicious or malformed value breaking the table layout or injecting raw HTML, and it's applied consistently everywhere a value is interpolated into a `| ... |` row.
- DESIGN: unlike `New-CoreEvidenceBundle.ps1`, which actively enforces that `-OutputDirectory` sits outside `-ReportRoot` (`EvidenceDestinationMustBeOutsideReports`), this script's own doc comment states the same expectation for `-OutputDirectory` vs. a "raw report input directory" (line 7) but has **no corresponding runtime check** — nothing here would stop a misconfigured caller from pointing `-OutputDirectory` at a directory that `Get-ChildItem -Recurse -Filter evidence-manifest.json` (line 55) would then re-scan on a second invocation, potentially picking up its own previously-generated manifest as if it were fresh input evidence. The explicit comment acknowledging the risk without a matching guard is a design gap worth closing, especially since the sibling script in the same folder shows the pattern to follow.
- CONVENTION: line 162's `[void][IO.File]::WriteAllTextAsync($markdown,$text.ToString().Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()` constructs its own UTF-8-no-BOM encoding inline instead of reusing `RunEncoding.psm1::Write-RunTextFile`, which already centralizes exactly this policy (UTF-8 no BOM + LF normalization) and is used elsewhere in the `scripts/lib` tree. This is the same kind of duplicated-encoding-policy smell flagged in `WorkstationResources.psm1`.
- DESIGN: `Get-ReportMedian` (lines 41-53) is a second, independent median implementation living in this script, separate from `RunStatistics.psm1::Get-RunQuantile`/`Get-RunSummary` which already compute medians (via linear-interpolated quantiles) elsewhere in the same `scripts/` tree. The two aren't byte-for-byte equivalent (this one does a plain even/odd average with no interpolation, matching `RunStatistics.psm1`'s *bootstrap* median style rather than its *quantile* style — they happen to agree for a median specifically, since `Get-RunQuantile` at `p=0.5` reduces to the same formula), but having two independently-maintained median functions in the same codebase is a DRY smell: a future bug fix to one (e.g. handling of NaN-padded input) would need to be remembered and ported to the other.
- No input-validation gap found for `-Suite`'s `ValidateSet`, and the per-row gap logic (`if($Suite -ne 'Git' -and (!$import -or !$controlled -or $row.Profiling -ne 'Success'))`, line 111) correctly treats `Git`-suite reports as exempt from the mandatory-integration/profiling requirement, matching the documented scope note it also prints into the report (line 126).
- Testability: has a dedicated test (`Evidence.Tests.ps1`, referencing this script at line 34), good coverage signal for the primary report-generation path; the "no boundary enforcement on `-OutputDirectory` reused as `-EvidenceRoot`" gap noted above was not confirmed to be covered by that test.

## Verdict

A careful, conservative reporting tool with good Markdown-injection hygiene; the two worthwhile fixes are adding the same destination-boundary enforcement `New-CoreEvidenceBundle.ps1` already has (since this script's own doc comment claims the same invariant without code to back it), and switching the direct `WriteAllTextAsync`/`UTF8Encoding` call to the shared `RunEncoding.psm1::Write-RunTextFile` helper.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Produces readable per-job or combined performance evidence without requiring a CLR trace viewer.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
