# New-CorePerformanceReport.psm1

<!-- script-source:begin -->
Source file: [`lib/New-CorePerformanceReport.psm1`](../../../scripts/lib/New-CorePerformanceReport.psm1)
<!-- script-source:end -->

Implements [New-CorePerformanceReport.ps1](../New-CorePerformanceReport.md). Exports only "Invoke-QuietScriptNewCorePerformanceReport". Imported without name checking; import defines the command without running the operation.

# New-CorePerformanceReport.ps1

## Purpose and usage

Verifies one or more evidence bundles and writes standalone HTML, Markdown and JSON for import measurements, controlled Git scenarios and detailed PowerShell/CLR profiling.

```powershell
./scripts/New-CorePerformanceReport.ps1 -EvidenceRoot ./artifacts/matrix-evidence -OutputDirectory ./artifacts/performance-results -Revision $env:GITHUB_SHA -ExpectedReports 10 -Suite All
```

EvidenceRoot contains a bundle or downloaded bundle directories. Revision must match every manifest. ExpectedReports defaults to zero (count check disabled); combined Core matrix reporting supplies eight for production or ten when Preview is explicitly selected. Suite accepts Core/All/Git/Integration and defaults to All. Core scopes require functional integration/profiling; Git labels those observations outside scope.

## Validation and outputs

Rechecks referenced literal-path files and SHA-256, rejects duplicate environment identities and reports missing/modified evidence. A matching count alone cannot establish distinct complete environments. Failed functional runs can still produce readable partial output; absent Core profiles are shown as Missing (phase not reached), then the step fails qualification.

Outputs are `PERFORMANCES_RESULTS.html`, `.md` and `.json`, plus an updated/new checksum/provenance manifest. HTML uses installed ConvertFrom-Markdown, embedded CSS/UTF-8 and a restrictive content-security policy, without external scripts/styles/network. Download `quietcli-performance-results-<revision>` and open the HTML locally; raw traces stay in per-environment bundles.

Reports include up to 50 source-line hotspots per environment and collector PID, trace/speedscope, size and hash provenance. Frame-name counts are not CPU percentages; overlapping wall durations are not additive CPU categories. Allocations are cumulative managed allocations, not retained memory. Instrumented passes remain separate from ordinary timing samples.

## Workloads, statistics and charts

Unless the suite is Git-only, the report has a `Workloads` section. It splits the evidence into five workloads: `ImportFirstCall`, `GitTransport`, `Framing`, `Metadata` and `Events`. [PerformanceWorkloads.psm1](PerformanceWorkloads.md) defines them, and [PerformanceStatistics.psm1](PerformanceStatistics.md) computes their statistics.

- **Coverage at a glance:** a chart of observations, environments and series per workload, for both the uninstrumented and the profiled lanes. Dashed boxes have no data.
- **Definitions:** the phase, evidence source and limits of every measure.
- **Charts by workload:** one bar chart per measure and variant, with one bar per environment. Each bar is a median with its N and, in HTML, its Q1–Q3 span, and has a caption with every value. [PerformanceCharts.psm1](PerformanceCharts.md) writes Mermaid into the Markdown and the same chart as inline SVG into the HTML.
- **Statistics by environment:** N, median, Q1–Q3, Min–Max and p95 for every row. A p95 that equals the largest observation is marked `(max)`. The matrix import column shows `(max of 7)` for the usual seven imports.

The **runtime note** below the matrix names each PowerShell/CLR group and its RIDs, for example musl on 7.6.10/.NET 10.0.14 against 7.7.0/.NET 11.0.0. It states that rows are neither an operating-system ranking nor a causal comparison. Hotspot lines carry the profiler workload that produced them. The JSON adds `Workloads` (flat statistics), `RuntimeNote` and `Statistics` (the method). A present workload value that is not a finite number is recorded as an evidence gap instead of being plotted.

## Dependencies and side effects

Loads Common, PerformanceStatistics, PerformanceWorkloads and PerformanceCharts, and reads local JSON/files/hashes. Creates report output and writes all three formats before throwing PerformanceReportEvidenceIncomplete for gaps. It may extend a colocated evidence manifest. No native process, network, Git operation or publication occurs. WhatIf writes nothing.

## Critical review and verdict

`scripts/lib/New-CorePerformanceReport.psm1` limits manifest discovery to bundle roots, and literal-path checks preserve bracketed/hidden evidence. Use a separate output destination for combined rendering; there is no general source/output separation guard matching New-CoreEvidenceBundle. Evidence.Tests exercises ten synthetic environments, dual Process collectors, escaping, output checksums, missing/duplicate-profile failures and previews. Those are rendering/integrity tests, not hosted profiling evidence. The charts help scanning but are not a ranking: bars of different runners stand side by side, and the tables remain the reference. Mermaid `xychart-beta` data labels depend on the viewer's Mermaid version; the captions keep the numbers either way.

## Tests

- [`unit/lib/New-CorePerformanceReport.Tests.ps1`](../../../test/scripts/unit/lib/New-CorePerformanceReport.Tests.ps1) renders a synthetic three-environment bundle in-process through `New-CoreEvidenceBundle.ps1` and checks:
  - no gaps;
  - LF-only UTF-8 without BOM;
  - the workload sections, the event variants grid, N, quartiles and `(max of 7)`;
  - the runtime note, and the statement that frame-name counts are not CPU shares;
  - one SVG per Mermaid chart, no active content, and byte-stable output across two renders;
  - a Git-only scope without charts;
  - a non-finite value recorded as a gap, and a missing workload shown as a dashed box;
  - `-WhatIf`.
- `Evidence.Tests.ps1` `Test-QuietMatrixHtmlEvidence` covers the ten-environment matrix and the legacy single-speedscope layout.





## Required startup and storage timings

Core reports require the FreshProcessStartup campaign and seven first-call / 21 warm-call observations for each applicable telemetry-on phase. Missing or malformed phase evidence produces an explicit gap and PerformanceReportEvidenceIncomplete after partial output is saved. The Markdown and self-contained HTML contain separate charts and definitions for result construction, metadata projection, save round-trip, queue wait, same-path gate wait, validation/metadata JSON, writer preparation and SQLite write. Ordinary and diagnostic totals are separate controls. Telemetry-off storage values remain unavailable.

Review: missing timer series are checked independently of the success flag in the supplied summary. Tests supply deterministic complete/missing/nonfinite fixtures and verify Markdown/Mermaid, HTML/SVG, JSON and no-write WhatIf. Verdict: complete supplied timing evidence does not establish a causal performance improvement; that requires a matched before/after campaign.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Produces readable per-job or combined performance evidence without requiring a CLR trace viewer.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Read-only property projections use script blocks so metadata remains available during WhatIf; mutating operations retain their existing operation guards.
