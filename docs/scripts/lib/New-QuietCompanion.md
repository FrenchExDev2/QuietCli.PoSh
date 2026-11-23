# New-QuietCompanion.psm1

<!-- script-source:begin -->
Source file: [`lib/New-QuietCompanion.psm1`](../../../scripts/lib/New-QuietCompanion.psm1)
<!-- script-source:end -->

`Invoke-QuietScriptNewQuietCompanion` implements [New-QuietCompanion.ps1](../New-QuietCompanion.md). Importing the library loads only workspace helpers.

Get-QuietCompanionScaffoldPlan validates the inputs and lists the branch and exact destination paths without writing.

The generator validates the requested group and credits, delegates branch creation to the workspace branch script and stages the package, test package, catalogue, solutions and credits. It uses the existing project, catalogue, solution and workflow readers to validate the staged result. The checksum-pinned YAML parser must already be prepared by the checkout's resource tooling.

Installation checks each destination and replaces files from temporary siblings. If installation fails, it restores the previous shared file bytes and removes the files and empty directories it created. The result reports the chosen branch, executable, parser variant and affected paths.

<!-- script-contract:begin -->
## Execution contract

Purpose: Resolves a branch override or derives the companion branch from the module group.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
