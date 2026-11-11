# Show-ColdStartMatrixReport.ps1

## Purpose

Renders every cold-start A/B measurement found on disk — both local Windows runs (`artifacts/coldstart/ab-*.json`) and containerized runs (`artifacts/coldstart-containers/<run>/guest/ab-*.json`) — as one combined console table, without rerunning any measurement. It solves the problem of getting a single, at-a-glance view across every historical and cross-platform cold-start A/B result that has accumulated on disk, rather than having to open each JSON report individually with `Show-ColdStartReport.ps1`. Per its own `.DESCRIPTION` (lines 8-13), it is explicitly designed to be repeatable "any time after `Invoke-ColdStartMatrix.ps1` (or any individual gate)." It is invoked at the end of `Invoke-ColdStartMatrix.ps1` (confirmed at that script's lines 16 and 188, which prints `"Render the combined report with: ./scripts/Show-ColdStartMatrixReport.ps1"`), and documented as a standalone, rerunnable tool in `docs/README-readytorun_profiling.md` (lines 134, 152) and `README-qualification.md` (line 103).

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `ArtifactsDirectory` | `string` | No | `artifacts/coldstart` (relative to the script's parent directory) |
| `ContainersDirectory` | `string` | No | `artifacts/coldstart-containers` (relative to the script's parent directory) |
| `Pattern` | `string` (`ValidateNotNullOrEmpty`) | No | `'ab-*.json'` |

```powershell
./scripts/Show-ColdStartMatrixReport.ps1

./scripts/Show-ColdStartMatrixReport.ps1 -ContainersDirectory $containerReports
```

## Dependencies

- `using module ./lib/RunLog.psm1` (line 27) — declared but its logger type is **not actually used anywhere in the script body** (no `New-RunLogger` call appears in the file); this is likely a leftover from a shared template with `New-RunProfile.ps1`/other scripts in the folder.
- `Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") -Force` for `RunEncoding` and `RunFormat` (line 35) — supplies `Read-RunTextFile` (line 94) and `Format-RunTable`/`Format-RunDuration`/`Format-RunDataSize` (lines 121, 124, 77).
- No external process is invoked; this script only reads JSON files from disk and formats console tables.
- Assumes the on-disk report schema produced by `Invoke-ColdStartGate.ps1`/`Invoke-ContainerColdStart.ps1` — specifically `Parameters.BaselineLabel`/`CandidateLabel`, `Environment.RuntimeIdentifier`, `Summary.Import`/`'First call'`/`'Second call'` (each with `.Verdict`/`.Difference.Median`), and `Footprint.DifferenceBytes`/`HostedDifferenceBytes`/`PackageDifferenceBytes`.

## Side effects

- None beyond console output (`Format-RunTable` writes to the host). No files are written, modified, or deleted; this is a pure read-and-render tool, consistent with its own `.DESCRIPTION` claim that it never reruns a measurement.

## Findings

- A row-level parse failure is deliberately isolated: the `try/catch` around each file's processing (lines 92-118) ensures that one unreadable or malformed report becomes a single `"unreadable: $_"` row (line 117) rather than aborting the whole render for every other valid report — a thoughtful resilience choice explicitly called out in the script's own `.DESCRIPTION` (lines 11-12: "a report that fails to parse or is missing an expected field is reported as a row-level error, not a hard failure of the whole render").
- DESIGN: `using module ./lib/RunLog.psm1` (line 27) appears to be dead/unused — no logger is created or used anywhere in this file, unlike `New-RunProfile.ps1`, which actually uses `New-RunLogger`. This is a minor leftover-import smell (possibly copy-pasted from a shared script skeleton) rather than a functional defect, but it is worth removing to avoid confusing a future reader into thinking structured logging is happening here.
- CONVENTION: this script satisfies the repo's "UTF-8 and Unicode box-drawing tables" requirement only indirectly, by delegating entirely to `Format-RunTable` in `RunFormat.psm1` — this file itself contains no table-rendering logic to audit, so compliance with the box-drawing/alignment/`Duration`-column conventions depends entirely on that shared module (not reviewed as part of this task's file list) rather than on anything in this script.
- Minor robustness gap: `Format-RunMatrixVerdictCell` (lines 67-78) assumes `$Entry.Difference.Median` is present whenever `$Entry` is non-`$null` (line 76 accesses `.Difference.Median` without checking it exists); if a report has a `Summary.<phase>` object with `Verdict` but a missing/renamed `Difference` sub-object (e.g. an older or differently-shaped report schema), this would throw inside the per-file `try` block and be caught as a generic "unreadable" row rather than surfacing a more specific error — acceptable given the existing error-isolation design, but it means schema-drift failures are reported less informatively than a parse failure would be.
- No hardcoded machine-specific paths; `ArtifactsDirectory`/`ContainersDirectory`/`Pattern` are all parameterized with sensible, documented defaults.
- Testability: no Pester test was found exercising this script directly. Given it is a pure, deterministic read-and-format function of on-disk JSON, it is readily unit-testable (e.g. feed it a temp directory with synthetic `ab-*.json` fixtures, including a deliberately malformed one, and assert the row count and the "unreadable" fallback path) — this is a concrete, currently-unfilled test-coverage gap, especially given the repo's mandatory property/fuzz-testing expectations for anything that parses external/semi-trusted input (malformed JSON reports qualify).

## Verdict

Fit for purpose and resilient to malformed individual reports, but has a small cleanliness gap (unused `RunLog` import) and a real test-coverage gap. The highest-priority improvement is adding a focused Pester test that feeds this script a mix of well-formed, schema-drifted, and malformed `ab-*.json` fixtures and asserts the resulting table/row-count behavior, since none currently exists.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Renders every cold-start A/B report found on disk (Windows and every Linux container run) as one table, without rerunning any measurement. Repeatable: re-run any time after Invoke-ColdStartMatrix.ps1 (or any individua...

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
