# Sync-ScriptsReadme.ps1

<!-- script-source:begin -->
Source file: [`Sync-ScriptsReadme.ps1`](../../scripts/Sync-ScriptsReadme.ps1)
<!-- script-source:end -->

## Purpose and usage

Run `./scripts/Sync-ScriptsReadme.ps1` to check the mirrored docs, their source links and the index. Run `./scripts/Sync-ScriptsReadme.ps1 -Apply` to synchronize links and the index. See the library for the full operation. [Sync-ScriptsReadme.psm1](lib/Sync-ScriptsReadme.md)

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and forwards explicitly bound parameters, including `-WhatIf` and `-Confirm`.

<!-- script-contract:begin -->
## Execution contract

Purpose: Documentation gate: checks or writes docs/scripts/README.md, the table of contents that links every script under scripts/ to its documentation file.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
