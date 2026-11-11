# Assert-QualificationReceipt.ps1

## Purpose

Reuses an existing All qualification only within the same GitHub run, attempt and exact SHA. An input SHA alone never bypasses qualification.

## Usage

The publication workflow downloads `quietcli2-qualification-gate` from the current run, then supplies `ReceiptPath`, `Revision`, `RunId`, `RunAttempt` and `OutputPath`. Manual releases without an existing receipt still execute the full qualification workflow.

## Dependencies

PowerShell 7.6+, strict UTF-8 and System.Text.Json. No native process, product engine, credential, network request or Gallery secret is required.

## Side effects

Appends `qualified_sha` to the selected GitHub output file only after successful validation. `-WhatIf` performs no read or write. Inputs are bounded to 16 KiB; links, duplicate fields and non-object JSON are rejected.

## Findings

Requires a boolean successful decision, Suite All, successful Windows/Linux, the explicit GitHub TTY exclusion, and matching run/attempt/revision. Tests damage every required field, fuzz malformed JSON and exercise a revision-check mutation. Receipt transport uses download-artifact's current-run default, without a caller-selected external run ID.

## Verdict

Suitable for deduplicating trusted same-run publication orchestration. The receipt is not a signature or transferable qualification of a different run or revision.

<!-- script-contract:begin -->
## Execution contract

Purpose: Accepts an All qualification receipt only for this exact revision and workflow attempt.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
