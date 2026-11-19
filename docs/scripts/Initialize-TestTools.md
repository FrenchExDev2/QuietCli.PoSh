# Initialize-TestTools.ps1

<!-- script-source:begin -->
Source file: [`Initialize-TestTools.ps1`](../../scripts/Initialize-TestTools.ps1)
<!-- script-source:end -->

## Purpose and usage

Prepares the checksum-pinned script test tools in an isolated cache, without global installation:
- Pester 6.2.0, for [Invoke-ScriptsTests](Invoke-ScriptsTests.md);
- PSScriptAnalyzer 1.25.0, for the [ScriptAnalyzer check](Test-ScriptAnalysis.md).

```powershell
./scripts/Initialize-TestTools.ps1                    # both tools into <workspace>/.cache/test-tools
./scripts/Initialize-TestTools.ps1 -Tool pester -Offline
```

| Options | Behavior |
| --- | --- |
| `WorkspaceRoot` | Repository root; defaults to the parent of `scripts/`. |
| `OutputDirectory` | Explicit cache directory; defaults to `<workspace>/.cache/test-tools`, which Git ignores. |
| `Tool` | `pester`, `scriptanalyzer` or both (default), validated before effects. |
| `Offline` | Verifies and extracts already-cached archives only. A missing requested archive fails with `ProfilerOfflineCacheMiss`. |

## Dependencies and side effects

Delegates to `Initialize-QuietTestTools` in [RunToolCache.psm1](lib/RunToolCache.md). Every archive is downloaded from the PowerShell Gallery URL pinned in `Get-RunTestToolPackages`. Its SHA-256 is verified before it is written, and again before every reuse. A mismatch fails, and a corrupt cache entry is never silently replaced. A transient download failure, such as HTTP 503, 429 or a lost connection, is retried up to five times with a doubling delay ([download retries](lib/RunToolCache.md#download-retries)).

Side effects:
- writes `<cache>/<Name>/<Name>.<Version>.nupkg`, the extracted module and `tool-receipt.json`;
- returns `PesterModulePath`, `ScriptAnalyzerModulePath`, `Receipt` and `Directory`.

`-WhatIf` prepares nothing. No module is installed or imported globally.

## Critical review and verdict

This is a thin entry point. Download, verification and extraction are shared with the profiler cache (`Initialize-RunToolCache`). Tests: `test/scripts/unit/lib/RunToolCache.Tests.ps1` covers the pins, selection, generic `Paths`, an offline miss with no provider call, a digest mismatch, the retry rules, and offline preparation from the real pinned archive.

<!-- script-contract:begin -->
## Execution contract

Purpose: Prepares the checksum-pinned script test tools (Pester 6.2.0, PSScriptAnalyzer 1.25.0) in an isolated cache, without global installation.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
