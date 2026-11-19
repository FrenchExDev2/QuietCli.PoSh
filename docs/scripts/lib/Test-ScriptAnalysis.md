# Test-ScriptAnalysis.psm1

<!-- script-source:begin -->
Source file: [`lib/Test-ScriptAnalysis.psm1`](../../../scripts/lib/Test-ScriptAnalysis.psm1)
<!-- script-source:end -->

Implements [Test-ScriptAnalysis.ps1](../Test-ScriptAnalysis.md). It exports `Invoke-QuietScriptTestScriptAnalysis` (check), `Invoke-QuietScriptAnalysisProcess` (worker launcher) and `Invoke-QuietScriptAnalysisWorker` (worker body). Import defines the commands without running anything.

## Purpose and usage

The check performs these steps in order:
1. Asks `Test-QuietScriptsTestsApplicable` ([ScriptsTests.psm1](ScriptsTests.md)) whether the workspace has script tests. A flat fixture returns `{Check='ScriptAnalyzer', Applicable=$false}` at once.
2. Reads and validates the settings, the baseline and the rules module of the analyzed workspace.
3. Computes the configuration hash from the analyzer version, the settings and the rules file.
4. Lists the sources and looks up each cache key.
5. On a miss, prepares the pinned PSScriptAnalyzer from the trusted tool root and runs the worker for the missed files only.
6. Reads every cached document and compares the findings with the baseline.
7. With `-UpdateBaseline` and stale entries, writes the pruned baseline.
8. Returns `{Check, Analyzer, Files, Analyzed, Cached, Findings, Baselined, New, Stale, Pruned}`, or throws `ScriptAnalysisNewViolations` or `ScriptAnalysisBaselineStale` after listing each offending finding or entry.

The launcher writes `request.json` under `<cache>/runs/<id>` and starts `pwsh -NoProfile -NonInteractive -EncodedCommand`. It throws `ScriptAnalysisTimeout` on expiry (after killing the worker tree) and `ScriptAnalysisWorkerFailed` on a non-zero exit, with the end of the stderr log. It deletes the run directory on success.

The worker imports the pinned analyzer, requires its exact version (`ScriptAnalysisAnalyzerVersionMismatch`), analyzes each file with `Settings` or, for a Pester container, `TestSettings`, plus the custom rules, and writes one cache document per file through `Write-WorkspaceJson`, which is atomic.

## Dependencies and side effects

Imports ScriptAnalysis, RunToolCache, WorkspaceJson and ScriptsTests. Its side effects are those listed for [Test-ScriptAnalysis.ps1](../Test-ScriptAnalysis.md).

## Critical review and verdict

Errors: `ScriptAnalysisRulesMissing`, `ScriptAnalysisCacheMissing: <path>` (a worker that exited 0 without writing a document), and the typed settings and baseline errors of [ScriptAnalysis.psm1](ScriptAnalysis.md). The integration test runs the real entry point in child processes, so this library is covered end to end rather than by line coverage.

<!-- script-contract:begin -->
## Execution contract

Purpose: Analyzes scripts/ and test/scripts/ with the pinned PSScriptAnalyzer and fails on any finding outside the baseline or any stale baseline entry.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
