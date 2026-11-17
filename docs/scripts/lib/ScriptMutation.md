# ScriptMutation.psm1

## Purpose and usage

Pure model of [Invoke-ScriptsMutation.ps1](../Invoke-ScriptsMutation.md). Import is inert. Nothing here starts a process or writes a file.

| Export | Contract |
| --- | --- |
| `Get-QuietScriptMutants` | Mutants of the named functions of one source, in source order, from every mutator of [ScriptMutators.psm1](ScriptMutators.md). Duplicate and no-op candidates are dropped. The id is the first 12 hex digits of the SHA-256 of module, function, mutator, offsets and replacement. Errors: `ScriptMutationSourceInvalid` and `ScriptMutationFunctionMissing: <name>` (absent, or defined more than once; matched case-sensitively). |
| `New-QuietScriptMutantSource` | Applies a mutant and returns `{Text, Compiles}`. `ScriptMutationOffsetMismatch: <id>` when the extent does not hold the original text. |
| `Get-QuietScriptMutantStatus` | `Timeout` (engine deadline or `Timeout` state), `Survived` (`Success` with no failure), otherwise `Killed`. |
| `Get-QuietScriptMutantTimeout` | `max(60, ceiling(3 × baseline + 30))` seconds. `ScriptMutationBaselineDurationInvalid` for a negative or non-finite duration. |
| `Measure-QuietScriptMutationScore` | Counts per status, then Score = (killed + timeout) / valid × 100, where CompileError and Equivalent are not valid, rounded to two decimals. The score is 100 without valid mutants, and `Passed` means Score ≥ Break. `ScriptMutationStatusInvalid` for an unknown status (ordinal). |
| `Read-QuietScriptMutationTargets` | Validates the targets file (see [the entry point](../Invoke-ScriptsMutation.md)). Errors: `ScriptMutationTargetsMissing` and `ScriptMutationTargetsInvalid: <reason>`, where the reason is `syntax`, `shape`, `name`, `duplicate`, `module`, `functions`, `tests`, `break`, `inputs` or `equivalent`. The optional `Inputs` must be a non-empty list of distinct relative globs whose segments use `[A-Za-z0-9._*-]`, without `.`, `..` or a rooted path. It is returned as `[string[]]`, empty when absent. |
| `Select-QuietScriptMutationEquivalents` | Splits one target's mutants into `{Run, Equivalent}` for a platform (`Windows`, `Linux` or `MacOS`). An entry without `Platform` applies everywhere; one with `Platform` only there. An entry covers every mutant of its function with the same mutator, original and replacement text, and each covered mutant carries its `Reason`. A mutant without those fields always runs. An entry of the current platform that covers no mutant throws `ScriptMutationEquivalentStale: <target>: <entries>`. |
| `New-QuietScriptMutationReport` | `{SchemaVersion=1, Seed, Passed, Incomplete, Crash, Targets}`. Each target carries its counts, including `Cached` (outcomes reused from the cache, counted only for a boolean `Cached = true`), score, break, verdict, survivors (id, function, mutator, line, column, before, after) and declared equivalents (the same fields plus the reason). A campaign that stopped passes `-Crash {Target, Error, NotRun}` with only its finished targets (possibly none): the report is then `Incomplete`, never `Passed`, and `Crash` holds the target it stopped in (empty outside any target), the error and the non-empty names of the targets never started. Otherwise `Incomplete` is false and `Crash` null. |
| `ConvertTo-QuietScriptMutationMarkdown` | The verdict (`passed`, `failed` or `incomplete`), then for an incomplete report where it stopped, the error and the targets not run. Then the score table (with a `Cached` column), one survivors table per target that has survivors and one table of its declared equivalent mutants with their reasons. Pipes and backticks are escaped. |
| `Assert-QuietScriptMutationShards` | Accepts shard reports only when, together, they cover every target exactly once, with the same module and function count, an unlowered break, and a passing score with at least one mutant. An `Incomplete` report (any value but `false` or absent) is `ScriptMutationShardIncomplete: <target it stopped in>`; its finished targets still count. Every issue is thrown at once, separated by semicolons (see [the entry point](../Assert-ScriptMutationShards.md)). Numbers are parsed with the invariant culture. Returns the completion receipt. |

## Dependencies and side effects

Imports ScriptMutators. It uses the PowerShell parser, SHA-256 and `Import-PowerShellDataFile` for the targets file.

## Critical review and verdict

The id leaves out the line number but includes offsets. An edit after the function keeps the ids, and an edit before it renumbers them, which is acceptable for a report that is regenerated on every run. Tests: `test/scripts/unit/lib/ScriptMutation.Tests.ps1`. It covers:
- order and uniqueness of mutants;
- id stability;
- every rejection of mutants, sources and targets;
- the full status table;
- a 300-case score property;
- `Inputs` validation (17 rejected values) and 150 fuzzed targets documents, where only typed errors may occur;
- the report and the Markdown, complete and incomplete (stopped in a target or outside any);
- the shard assertion: an 80-case partition property, a rejection table including incomplete shards, and 150 fuzzed reports.

The library is itself a mutation target.

<!-- script-contract:begin -->
## Execution contract

Purpose: Lists the mutants of the named functions of one library source, with stable ids, in source order.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
