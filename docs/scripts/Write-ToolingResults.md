# Write-ToolingResults.ps1

## Purpose and usage

`./scripts/Write-ToolingResults.ps1 -NeedsJson $env:TOOLING_NEEDS -OutputPath $env:GITHUB_OUTPUT`
exports independent functional, mutation-shard and catalogue-completeness results.
The tooling workflow runs its result job with `always()` after all four prerequisites.
This step reports decisions; it never converts a failed prerequisite to success.

## Dependencies and effects

Imports [ToolingResults](lib/ToolingResults.md). Appends three closed result values
to the selected UTF-8/LF output file. Standard WhatIf returns before parsing or writing.
It starts no process and reads no credentials. Missing or malformed job fields become
failure; invalid or oversized JSON throws without producing outputs.

## Review and validation

The result job may itself be unavailable after cancellation or runner failure. The
calling gate rejects absent outputs and independently checks overall workflow success.
The existing Tooling release-gate case tests 625 result combinations, malformed input,
no-write preview, three targeted mutants and independent gate rejection/receipts.
Local fixtures do not qualify GitHub's hosted output propagation after cancellation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Writes separate tooling job results to the GitHub output file, including failed or incomplete prerequisites.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
