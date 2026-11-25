# Sync-DocsCredits.ps1

<!-- script-source:begin -->
Source file: [`Sync-DocsCredits.ps1`](../../scripts/Sync-DocsCredits.ps1)
<!-- script-source:end -->

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [Sync-DocsCredits.psm1](lib/Sync-DocsCredits.md). See that library for the full operation, dependencies, examples, effects and validation limits.

The scan includes docs/**/*.md, root README*.md, and readmes/README-*.md.
The check requires a single current credits block at the end of each document.
`-Apply` moves misplaced blocks to the end while preserving the document body.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptSyncDocsCredits`. The library retains the original operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks or writes the mandatory CREDITS.md paragraph in docs, root READMEs and readmes/ guides.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
