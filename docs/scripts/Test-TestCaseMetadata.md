# Test-TestCaseMetadata.ps1

## All companion catalogues

The default Suite is All: discover every test project manifest through WorkspaceProjects, then read that companion's own TestCatalogue/RootModule and local `.psm1` metadata. No Core-owned Git/Vagrant case registry is introduced. `-Suite Core|Git|Vagrant` narrows validation; `-Plan` resolves currently active cases and the selected worker budget without running them. Output includes declared/active counts, optional campaigns not requested, kinds, isolation opt-ins and the manifest cap. Every discovered test companion must declare its catalogue; missing or orphan metadata, unsafe sources and mismatched optional registration conditions fail.

```powershell
./scripts/Test-TestCaseMetadata.ps1
./scripts/Test-TestCaseMetadata.ps1 -Suite Vagrant -Plan -MaxConcurrency 2
```

## Purpose and usage

Check every Core case registration against its explicit metadata without importing Core, running test bodies, building or downloading anything.

```powershell
./scripts/Test-TestCaseMetadata.ps1
./scripts/Invoke-WorkspaceChecks.ps1 -Check TestCaseMetadata
./scripts/Test-TestCaseMetadata.ps1 -Plan -MaxConcurrency 4
```

`WorkspaceRoot` selects the working tree or exported staged snapshot. Success reports the total, Unit and Integration counts. The shared registry runs this gate first locally, during commit checks and in `scripts-docs-check.yml`. Core also validates its actual runtime catalogue before filtering or executing cases.

The check also validates `PrivateData.QuietCli.TestExecution` in the Core test manifest. Success includes the eligible case count and manifest cap. `-Plan` returns the full plan instead, without running any case. `MaxConcurrency` combines with that cap; Ordered/Exclusive cases remain barriers and only consecutive explicitly eligible cases share a batch. Missing declarations default to sequential execution; malformed declarations fail.

## Dependencies and side effects

Uses `lib/TestCaseMetadata.psm1`, `lib/TestCaseScheduling.psm1`, PowerShell's AST parser and its inert data-file reader. UTF-8 source reads only; no engine/module-under-test import, test execution, output files, resource preparation, network or repository mutation. This purely read-only entry point has a reviewed hash-bound exception in `build/script-shouldprocess.json`; no pretend WhatIf API is needed.

Checks still execute with inherited `WhatIfPreference`, as in a commit preview. The explicit ReadOnly entry in `ScriptReview.ps1` prevents the contract generator from adding a guard that would skip validation. Runtime regressions verify both successful reads and rejection of malformed catalogues under that preference.

## Critical review

- `scripts/Test-TestCaseMetadata.ps1`: the check reads the selected owning test runner and explicitly declared helper sources, not an installed release. The parser never evaluates case bodies.
- `scripts/lib/TestCaseMetadata.psm1`: missing/orphan entries, duplicate registrations, invalid kinds/dependencies and nonliteral metadata fail closed. Syntax and classification checks cannot prove isolation or complete dependency declarations.
- `FrenchExDev2.QuietCli.Core.Tests.PoSh/TestCaseMetadata.Tests.ps1`: generated valid inputs, malformed entries and source mutants exercise rejection and inert parsing; the check preserves the source hash.
- The scope is Core's top-level case runner. Nested campaigns and other companion runners retain their existing reports; this is not a claim that every assertion in the repository has acquired metadata.

## Verdict

Blocks incomplete Core classification before costly test execution. See [classification and concurrency](../README-test-classification-and-concurrency.md) for taxonomy and scheduling limits.

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks each owning test companion's classifications and execution policy without loading its engine.

Boundary: **ReadOnly**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
