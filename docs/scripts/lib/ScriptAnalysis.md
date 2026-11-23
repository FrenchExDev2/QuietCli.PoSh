# ScriptAnalysis.psm1

<!-- script-source:begin -->
Source file: [`lib/ScriptAnalysis.psm1`](../../../scripts/lib/ScriptAnalysis.psm1)
<!-- script-source:end -->

Analysis inventory paths use `/` on every host. The library normalizes the host directory separator before comparing or caching relative paths.

## Purpose and usage

Pure functions behind [Test-ScriptAnalysis.ps1](../Test-ScriptAnalysis.md). Import is inert. Nothing here loads PSScriptAnalyzer, starts a process or writes a file.

| Export | Contract |
| --- | --- |
| `Compare-QuietScriptAnalysisBaseline` | Returns `{Passed, New, Stale, Baselined, Pruned}`. A key whose findings exceed the baseline count reports the excess as `New`. A baseline entry with fewer occurrences than recorded is `Stale`. `Pruned` lowers every count to what still occurs and never gains an entry. Input order does not matter. |
| `Get-QuietScriptAnalysisFindingKey` | Ordinal key `(Rule, Path, Function, ExtentSHA256)`. |
| `Get-QuietScriptAnalysisSha256` | Uppercase SHA-256 of a text after CRLF and CR become LF. |
| `Get-QuietScriptAnalysisFunctionName` | Innermost function containing an extent, or an empty string at file level. |
| `ConvertTo-QuietScriptAnalysisFinding` | Maps a DiagnosticRecord, or any object with the same properties, to `{Rule, Path, Function, ExtentSHA256, Line, Column, Severity, Message}`. The path uses forward slashes. A missing extent hashes as empty. |
| `ConvertTo-QuietScriptAnalysisBaseline` | Builds `{SchemaVersion=1, Analyzer, Entries}`, one entry per key with its count, sorted in ordinal order. |
| `Read-QuietScriptAnalysisBaseline` | Validates the baseline. Errors: `ScriptAnalysisBaselineMissing` and `ScriptAnalysisBaselineInvalid: <reason>`, where the reason is `syntax`, `schema`, `entry`, `path` (absolute, backslash or `..`), `hash`, `count` (an integer of at least 1) or `duplicate`. |
| `Read-QuietScriptAnalysisSettings` | Validates `ScriptAnalyzerSettings.psd1` and returns `{Settings, TestSettings, Reasons, SHA256}`. Errors: `ScriptAnalysisSettingsMissing` and `ScriptAnalysisSettingsInvalid: <reason>` (`syntax`, `key`, `severity`, `reasons`, `duplicate`, `reason`, `orphan-reason`). The hash is computed from the sorted lists, so reordering the file does not invalidate the cache. |
| `Test-QuietScriptAnalysisTestContainer` | True for `test/scripts/**/*.Tests.ps1` (ordinal, case-sensitive suffix). |
| `Get-QuietScriptAnalysisFiles` | Sorted relative paths of the `.ps1` and `.psm1` files under `scripts/` and `test/scripts/`, skipping links. |
| `Get-QuietScriptAnalysisCacheKey` | SHA-256 of the relative path, the content hash and the configuration hash. The path separator and the hash case are normalized. |

## Dependencies and side effects

Only .NET hashing, enumeration and the PowerShell parser types, plus `Import-PowerShellDataFile` for the settings file.

## Critical review and verdict

The key leaves out line and column, so code that moves keeps its entry, while a changed flagged text gets a new key. Two identical violations in the same function share one key and are counted. Tests: `test/scripts/unit/lib/ScriptAnalysis.Tests.ps1` checks these properties:
- a baseline accepts its own findings in any order;
- additions are exactly the new findings;
- removals are stale, and pruning only shrinks;
- the baseline shape holds;
- the cache key reacts to each of its inputs.

It also fuzzes 300 baseline documents, where only typed errors may occur, and covers every settings rejection.

<!-- script-contract:begin -->
## Execution contract

Purpose: Compares analyzer findings with the checked-in baseline; new violations and stale entries fail the check.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
