# New-CorePerformanceReport.psm1

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

## Dependencies and side effects

Loads Common and reads local JSON/files/hashes. Creates report output and writes all three formats before throwing PerformanceReportEvidenceIncomplete for gaps. It may extend a colocated evidence manifest. No native process, network, Git operation or publication occurs. WhatIf writes nothing.

## Critical review and verdict

`scripts/lib/New-CorePerformanceReport.psm1` limits manifest discovery to bundle roots, and literal-path checks preserve bracketed/hidden evidence. Use a separate output destination for combined rendering; there is no general source/output separation guard matching New-CoreEvidenceBundle. Evidence.Tests exercises ten synthetic environments, dual Process collectors, escaping, output checksums, missing/duplicate-profile failures and previews. Those are rendering/integrity tests, not hosted profiling evidence.





<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Produces readable per-job or combined performance evidence without requiring a CLR trace viewer.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Read-only property projections use script blocks so metadata remains available during WhatIf; mutating operations retain their existing operation guards.
