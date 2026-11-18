# Test-SdkReadiness.ps1

<!-- script-source:begin -->
Source file: [`Test-SdkReadiness.ps1`](../../scripts/Test-SdkReadiness.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [Test-SdkReadiness.psm1](lib/Test-SdkReadiness.md). See that library for the full operation, dependencies, examples, effects and validation limits.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptTestSdkReadiness`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reports whether the pinned .NET SDK is current and whether ReadyToRun (Crossgen2) is actually publishable for every RID that -ReadyToRun on Build-Workspace.ps1 would target, without building, installing or publishing ...

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
