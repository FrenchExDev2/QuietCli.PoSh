# Assert-ScriptMutationShards.ps1

<!-- script-source:begin -->
Source file: [`Assert-ScriptMutationShards.ps1`](../../scripts/Assert-ScriptMutationShards.ps1)
<!-- script-source:end -->

## Purpose and usage

Accepts the script mutation campaign only when the downloaded shard reports cover every configured target, each at or above its break. The `script-mutation-complete` job of [tooling-ci.yml](../ci/github/script-tooling-ci.md) runs it after the `script-mutation` matrix. Each shard runs [Invoke-ScriptsMutation](Invoke-ScriptsMutation.md) on one target.

```powershell
./scripts/Assert-ScriptMutationShards.ps1 -ReportRoot ./artifacts/script-mutation-shards -OutputPath ./artifacts/script-mutation-complete/receipt.json
```

| Options | Behavior |
| --- | --- |
| `ReportRoot` | Downloaded shard artifacts. Every `report.json` below it is read, in path order. A missing directory counts as no report. |
| `OutputPath` | New completion receipt. An existing file fails with `ScriptMutationCompletionReceiptExists`. |
| `WorkspaceRoot` | Checkout that supplies the authoritative targets file. Defaults to the parent of `scripts/`. |
| `TargetsPath` | Targets file. Defaults to `<workspace>/test/scripts/mutation.targets.psd1`. |
| `Target` | Selected target names. Only their shards are required, and a shard of any other target is `ScriptMutationShardUnknown`. An empty selection fails with `ScriptMutationTargetSelectionEmpty`, and a name outside the targets file (case-sensitive) with `ScriptMutationTargetUnknown: <name>`. Omitted, every configured target is required. |

Each report is checked against the targets file by `Assert-QuietScriptMutationShards` ([ScriptMutation.psm1](lib/ScriptMutation.md)). All issues are reported together in one error, separated by semicolons:

| Issue | Cause |
| --- | --- |
| `ScriptMutationShardReportsMissing` | No report was downloaded. |
| `ScriptMutationShardReportInvalid` | The report is over 4 MB, is a reparse point, has a schema other than 1, or has no targets. |
| `ScriptMutationShardIncomplete: <name>` | The campaign stopped in that target (empty name: outside any target), so the report is `Incomplete`. The targets it finished still count; the one it stopped in is also reported missing. |
| `ScriptMutationShardUnknown: <name>` | The target is not configured. |
| `ScriptMutationShardDuplicate: <name>` | The target is reported by more than one shard. |
| `ScriptMutationShardMissing: <name>` | No shard reports the target. |
| `ScriptMutationShardStale: <name>` | The report has a different module or function count. |
| `ScriptMutationShardBreakLowered: <name>` | The report has a break below the configured one. A raised break is accepted. |
| `ScriptMutationShardFailed: <name>` | The report has no mutants, a verdict other than a true boolean, or a score below its break. |

The receipt is `{SchemaVersion=1, Passed=true, Targets=[{Name, Module, Mutants, Score, Break}]}`, in targets-file order.

## Dependencies and side effects

Imports only `lib/ScriptMutation.psm1`. Reads the targets file and the bounded UTF-8 reports. Writes the receipt only after every check passes. `-WhatIf` returns before any import, read, directory or write. No process, network access or publication occurs.

## Critical review and verdict

The workflow downloads only artifacts named for the current SHA and attempt. This script then checks that the union of shards is exactly the configured target set, or the selected one: the workflow passes the targets that `script-selection` expanded. A shard that fails, times out or is cancelled therefore cannot be replaced by an older report. A target whose outcomes came, in part or in full, from the incremental cache is accepted like any other: its cache keys cover every input its tests observe (see [ScriptMutationCache.psm1](lib/ScriptMutationCache.md)), so a reused outcome is the outcome a fresh run would give. Shard job success is also required separately, through `ScriptMutationShardJobsRequired` in the workflow.

Tests:
- `test/scripts/unit/lib/ScriptMutation.Tests.ps1`:
  - an 80-case partition property;
  - an 8-case rejection table;
  - an accepted raised break, and accepted cached outcomes;
  - malformed reports;
  - 150 fuzzed reports, where only typed issues may occur.
- `test/scripts/integration/entrypoints/Assert-ScriptMutationShards.Tests.ps1`:
  - a receipt is written on success;
  - each rejection writes no receipt;
  - an existing receipt is refused;
  - `-WhatIf` writes nothing.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Accepts the script mutation campaign only when the downloaded shard reports cover every configured target, each above its break.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
