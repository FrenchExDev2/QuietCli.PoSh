# ScriptsTests.psm1

## Purpose and usage

Pure functions behind [Invoke-ScriptsTests.ps1](../Invoke-ScriptsTests.md). Import is inert. Nothing here starts a process, imports Pester or writes a file.

| Export | Contract |
| --- | --- |
| `Get-QuietScriptsTestPlan` | Discovers `*.Tests.ps1` under `unit/` and/or `integration/` for `-Kind`, skipping links, and sorts them in ordinal order. `-Path` narrows the selection through `Resolve-QuietScriptsTestPath`. Returns `{Kind, TestsRoot, Files, FullNameFilter, Tag, ExcludeTag, Partial}`. `Partial` is true exactly when a selector or a non-blank filter is present. A tests root the platform cannot resolve throws `ScriptsTestPathInvalid: tests-root-unresolvable`; a missing or linked one throws `ScriptsTestPathInvalid: tests-root`. An empty selection throws `ScriptsTestSelectionEmpty`. |
| `Resolve-QuietScriptsTestPath` | Validates one selector. Failures throw `ScriptsTestPathInvalid: <reason>`, where the reason is one of `empty`, `control-character`, `invalid-character`, `parent-segment`, `outside-root`, `missing`, `link` or `not-a-test-file`. The value itself is never echoed. |
| `Get-QuietScriptsCoverageTargets` | Reads `coverage.targets.psd1` (`Threshold` 0–100, `Paths` relative to the scripts root) and resolves the paths against the scripts root under test. Errors: `ScriptsTestCoverageTargetsMissing` and `ScriptsTestCoverageTargetsInvalid: <reason>`. |
| `New-QuietScriptsPesterConfiguration` | Returns a JSON-serializable hashtable for `New-PesterConfiguration -Hashtable`: run paths, non-blank filters, Detailed plaintext output, JUnit output and, optionally, JaCoCo coverage with `CoveragePercentTarget`. |
| `ConvertTo-QuietScriptsTestReport` | Maps a Pester result, or any malformed object, to `{Project='Scripts.Tests', Kind, State, Passed, Failed, Skipped, NotRun, Total, Partial, Incomplete, Seed, Files, Coverage, Cases}` without throwing. See the rules below. |
| `New-QuietScriptsTestStatus` | Returns the `Running` status fields that [Watch-Tests](Watch-Tests.md) and `Wait-WorkspaceWorker` read. |
| `Update-QuietScriptsTestStatus` | Moves `Running` to exactly one terminal state, from a report or from a crash message (`Crash` with `Failed + 1`). Any other transition throws `ScriptsTestStatusTransitionInvalid`. |
| `Get-QuietScriptsTestExitCode` | Returns 0 for `Success` only and 1 for every other state. |
| `Test-QuietScriptsTestsApplicable` | Returns `True` when `<WorkspaceRoot>/test/scripts` is a directory and `False` when it is not and `src/` is absent (a flat commit fixture). With `src/` and no test tree it throws `ScriptsTestsRootMissing: test/scripts`. The ScriptAnalyzer and ScriptsInventory checks call it first. |

Rules applied by `ConvertTo-QuietScriptsTestReport`:
- `Failed` counts failed tests, failed blocks and failed containers.
- `Passed + Failed + Skipped = Total` always holds.
- A null or malformed result, zero executed tests, or missing requested coverage marks the report `Incomplete`.
- `Success` requires a complete report, no failure, and, when coverage was requested, the threshold met.

## Dependencies and side effects

Only .NET path, enumeration and parsing APIs, plus `Import-PowerShellDataFile` for the targets file. Path comparison is case-insensitive on Windows only.

## Critical review and verdict

Tests: `test/scripts/unit/lib/ScriptsTests.Tests.ps1`. It covers:
- plans per kind;
- typed rejections;
- links, where the host can create them;
- 400 fuzzed selector sets, where only typed errors may occur and no file escapes the root;
- a property that `Partial` is true exactly when the run is narrowed;
- a property that Pester 6 accepts every generated configuration;
- 500 fuzzed results that keep the invariant;
- status transitions;
- the exhaustive applicability product (test tree as directory, file or absent, crossed with `src/`).

The library is a mutation target in `test/scripts/mutation.targets.psd1` (break 80 %), run by [Invoke-ScriptsMutation.ps1](../Invoke-ScriptsMutation.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Discovers the *.Tests.ps1 files selected by kind, paths and filters, in ordinal order.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
