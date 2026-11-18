# New-CorePerformanceReport.ps1

<!-- script-source:begin -->
Source file: [`New-CorePerformanceReport.ps1`](../../scripts/New-CorePerformanceReport.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [New-CorePerformanceReport.psm1](lib/New-CorePerformanceReport.md). See that library for the full operation, dependencies, examples, effects and validation limits.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptNewCorePerformanceReport`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Produces readable per-job or combined performance evidence without requiring a CLR trace viewer.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
