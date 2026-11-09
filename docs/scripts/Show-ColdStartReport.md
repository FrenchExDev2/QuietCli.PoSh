# Show-ColdStartReport.ps1

## Purpose

Renders one existing `Measure-ColdStart.ps1`/`Invoke-ColdStartGate.ps1` JSON cold-start A/B report (summary verdicts per phase, plus on-disk/hosted/package footprint sizes) as console tables, without rerunning any measurement. By default it picks the most recently written `ab-*.json` under `-ArtifactsDirectory`. It solves the problem of inspecting a single, specific cold-start comparison (e.g. "baseline" vs. "readytorun") in human-readable form after a gate has already run. It is invoked by the GitHub Actions workflow `.github/workflows/quietcli2-readytorun.yml` (lines 55 and 132, the latter pointed at a container's copied-back report directory) and documented as a standalone, rerunnable tool in `README-qualification.md` (line 80) and `docs/README-readytorun_profiling.md`.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Path` | `string` | No | none — when omitted, the newest file matching `-Pattern` under `-ArtifactsDirectory` is used |
| `ArtifactsDirectory` | `string` | No | `artifacts/coldstart` (relative to the script's parent directory) |
| `Pattern` | `string` (`ValidateNotNullOrEmpty`) | No | `'ab-*.json'` |

```powershell
./scripts/Show-ColdStartReport.ps1

./scripts/Show-ColdStartReport.ps1 -Path artifacts/coldstart/ab-coldstart-100-readytorun-20261108T095226Z.json
```

## Dependencies

- `using module ./lib/RunLog.psm1` (line 27) — same as its sibling `Show-ColdStartMatrixReport.ps1`, this import appears unused in the script body (no logger is instantiated or called anywhere in this file).
- `Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") -Force` for `RunEncoding` and `RunFormat` (line 35) — supplies `Read-RunTextFile` (line 54), `Format-RunTable` (lines 71, 81), `Format-RunDuration` (line 68), and `Format-RunDataSize` (lines 76-78).
- No external process is invoked.
- Assumes the same on-disk report schema as `Show-ColdStartMatrixReport.ps1`: `Parameters.BaselineLabel`/`CandidateLabel`, `Environment.MachineName`/`PowerShell`/`Clr`/`RuntimeIdentifier`, `Summary.<Phase>.Baseline/Candidate/Difference.{Median,Low,High}.Verdict`, and `Footprint.{Baseline,Candidate}{,Hosted,Package}Bytes` plus the precomputed `Difference...` fields.

## Side effects

- None beyond console output. Purely read-only: locates/reads one JSON file and prints formatted tables; no files are created, modified, or deleted.

## Findings

- `Get-LatestColdStartReport` (lines 37-51) correctly throws a specific, named error (`"ColdStartReportNotFound: no file matching '$Pattern' under $Directory"`, line 49) rather than silently returning nothing when no report exists — good fail-fast behavior for a script meant to be run interactively or in CI logs where a clear error beats a confusing empty table.
- DESIGN: identical to its sibling file, `using module ./lib/RunLog.psm1` (line 27) is imported but never used in this script — the same unused-import smell noted in `Show-ColdStartMatrixReport.ps1`. Likely both files were derived from a shared template.
- The footprint-table caption (line 80) builds a long, conditional, string-concatenated sentence inline (checking `$null -eq $footprint.BaselineHostedBytes` and `$null -eq $footprint.BaselinePackageBytes` to adjust wording) — functionally correct and genuinely useful (it tells the reader *why* a column might read `-`), but the logic is dense enough (a single very long line) that a future schema change to `Footprint` is more likely to be overlooked when editing this caption than if the three conditional clauses were split into named local variables first. A readability improvement, not a defect.
- No input validation issue: `-Path`, when supplied, is passed through `[IO.Path]::GetFullPath` (line 53) but is not checked for existence before `Read-RunTextFile` is called — if the path doesn't exist, the resulting error will come from whatever `Read-RunTextFile` throws (not reviewed as part of this file), rather than from a clear, named error at this call site the way the no-`-Path` branch (`Get-LatestColdStartReport`) provides. Minor inconsistency in error-message quality between the two input modes, not a bug.
- Testability: no Pester test was found exercising this script directly. As with `Show-ColdStartMatrixReport.ps1`, this is a deterministic, pure function of an on-disk JSON file and console output, and is readily testable with a synthetic fixture — currently an unfilled gap. Given both `Show-ColdStart*.ps1` scripts are the primary human-facing reporting surface for the cold-start qualification gate referenced throughout `README-qualification.md`, a regression here (e.g. a column silently showing wrong units after a `Format-RunDuration`/`Format-RunDataSize` change) would be easy to miss without a test asserting the rendered row contents for a fixed fixture.

## Verdict

Fit for purpose; the fail-fast "no report found" error and its clear phase/footprint tables make this a solid interactive/CI tool. The highest-priority improvement, shared with its sibling script, is adding a Pester test against a fixed synthetic `ab-*.json` fixture to lock in the rendered table contents and catch future formatting regressions, since none currently exists.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
