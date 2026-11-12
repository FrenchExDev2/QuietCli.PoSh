# Core test classification and concurrency

## Classification contract

Each companion owns its catalogue: Core.Tests, Git.Tests, Vagrant.Tests and Tooling.Tests declare their own literal metadata inside their own .psm1. Their manifests declare TestCatalogue (runner and explicitly scoped helper sources) and TestExecution independently. Shared readers validate these declarations without importing product modules or moving Git/Vagrant cases into a Core-owned registry. The default gate discovers all test projects; use -Suite to inspect one.

Git declares 78 cases, including nine optional mutation cases, and preserves its shared-repository prerequisites. Vagrant declares 14 cases, with six pure Unit parsers eligible for isolated processes; its environment/handler/native-fixture cases remain ordered. Both companion caps are two. EnabledWhen declarations are statically matched to actual literal optional registration guards; active runtime catalogues must match exactly before filtering. ProcessEnvironment is an explicit dependency. Filtered/stopped Git/Vagrant runs now preserve Partial/Incomplete scope too.

Core progress includes the case kind: `CI case [Running] [Integration] ...`. Reports preserve `TestKind` and `Dependencies` for each executed top-level case. Every registration in `Invoke-QuietCoreTests` has an explicit matching `$caseMetadata` entry; the old partial table and `Unclassified` fallback are removed. Missing, orphan, duplicate, dynamic or malformed entries fail before filtering or execution. A focused run cannot hide an unclassified case elsewhere in the catalogue.

`Unit` means in-memory assertions without filesystem, native process or shared engine dependencies. The byte-count parser and generated status-record digest assertions meet that boundary. `Integration` covers filesystem/source validation, engine state, native fixtures, Git, process boundaries, builds and package installation. A source parser/help check is Integration because it reads repository files and writes a writer fixture; security audit cases are Integration because they launch an audit worker, native fixtures and an isolated SQLite database. Property generation and mutation are test techniques, independent of this dependency classification.

Dependencies use `FileSystem`, `NativeProcess`, `GitProcess`, `DotNetBuild` and `EngineState`. Optional existing `NativeTransport` values distinguish stubbed orchestration and owned native fixtures. These declarations are reviewable descriptions, not a scheduler or proof of complete transitive effects. Nested campaigns keep their own assertion/evidence reports; this gate covers Core's top-level cases.

```powershell
./scripts/Test-TestCaseMetadata.ps1
./scripts/Invoke-WorkspaceChecks.ps1 -Check TestCaseMetadata
./scripts/Invoke-WorkspaceCi.ps1 -Suite Tooling -SkipBuild -SkipTty -Case 'test case classifications*'
```

`TestCaseMetadata` is first in the shared local/commit/CI registry. The GitHub check workflow includes Core test-source changes in its path filters. The runtime guard remains active for direct Core/All execution, including manual CI invocations. Classification cannot turn a failed/skipped case into success or qualify a partial run.

The check also executes under inherited WhatIf in commit previews. Its ReadOnly review and hash-bound exception prevent the contract generator from inserting a guard that would skip validation. `Unclassified` in the separate script preview inventory describes the absence of a preview API; it is unrelated to test kinds and is not globally renamed by this change.

## Manifest policy and prepared plan

All divides its shared worker budget across concurrent Git/Vagrant suite slots. With four slots and two admitted suites, each receives two; individual isolated case workers still receive one. A smaller caller budget wins over every manifest cap. Exclusive/Ordered stages constrain the owning companion; suite-level scheduling remains a separate boundary. Core's measurements and profiling complete outside sibling-suite fan-out.

The Core test companion declares its policy in [its PSD1 manifest](../FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1), which is also exposed as the module's PrivateData. The declaration is inert data:

```powershell
PrivateData = @{ QuietCli = @{ TestExecution = @{
    SchemaVersion = 1
    DefaultMode = 'Ordered'
    DefaultReason = 'Preserve existing engine and fixture dependencies.'
    MaxParallelCases = 2
    Cases = @{
        'PowerShell functions have readable help and sources parse without errors' = @{
            Mode = 'IsolatedProcess'
            Reason = 'Read-only checkout and owned writer fixture.'
            TimeoutSeconds = 180
        }
    }
} } }
```

`Ordered` is the only permitted default. An absent declaration also yields Ordered and a cap of one. Case overrides accept Ordered, Exclusive or IsolatedProcess, with a reviewable reason and optional timeout. Exclusive identifies measurement/packaging barriers; Ordered retains dependencies on earlier cases. Unknown cases/modes/fields, malformed data and invalid caps/timeouts fail before execution. New cases remain ordered until explicitly reviewed.

```powershell
$plan = ./scripts/Test-TestCaseMetadata.ps1 -Plan -MaxConcurrency 4
$plan.Stages | Select-Object Mode, @{n='Cases';e={$_.Cases.Name -join '; '}}
```

The complete plan can be inspected before execution without loading Core. Runtime saves the selected plan to `core-execution-plan.json`. Only consecutive IsolatedProcess cases share a batch; no case moves across an Ordered/Exclusive barrier. Five cases currently opt in: three GitHub receipt/helper/container-input checks, then the help/source check and security audit. Their batches use at most two workers and never exceed the caller's MaxConcurrency. A cap of one runs isolated children sequentially.

Every child uses the same PSHOME, built checkout and image, with one internal worker, private configuration/SQLite/report directory, exact escaped case filter, propagated host/RID expectations and explicit TTY scope. CaseWorker prevents recursive fan-out. The parent validates each receipt, counts each case once and preserves result order. Child partial selections are internal implementation receipts; only the parent can qualify its complete Core catalogue. A developer filter still makes that parent partial.

An observed failure with stop-on-first enabled stops new admissions and drains admitted workers. Timeouts fail the case and terminate its owned tree; cancellation/exception cleanup terminates all still-owned workers. Missing, contradictory, foreign-case or foreign-process receipts fail. No native output is captured by the scheduler. GitHub logs print cumulative case progress only from the parent, avoiding duplicate counters.

## Concurrency assessment

Assessment of [run 42953228867, job 130302253543](https://github.com/FrenchExDev2/QuietCli.PoSh/actions/runs/42953228867/job/130302253543?pr=2), 11 November 2026: the difference between Running and Passed log timestamps was approximately 275 seconds for the commit-workspace case, 64 seconds for the security audit, 57 seconds for paired import measurements, 38 seconds for reusable scripts and 36 seconds for Recall. These are one job's elapsed intervals, including logging overhead; they are neither CPU billing nor a parallel speedup measurement.

| Cases / family | Observed constraints | Scheduling assessment |
| --- | --- | --- |
| Help and source parsing | Reads source files and writes a uniquely named JSON-writer fixture under artifacts | Explicitly enabled with process isolation, after preceding ordered stages and before packaging |
| Security audit | Already launches a child worker with its own configuration and SQLite database; mutates worker-local handlers and engine state, and packages only synthetic files in its owned directory | Explicitly enabled to overlap with source checks; independent process/configuration/database and a bounded batch |
| Byte counts and status-record digests | In-memory inputs and owned accumulators; very short | Runspace candidates, but startup/import cost may exceed any saving |
| Commit-workspace and staged-index contracts | Creates nested synthetic repositories and child processes; its 11 mutants already run through `ForEach-Object -Parallel -ThrottleLimit $MaxConcurrency`, each in an isolated PowerShell process | Retain the existing bounded mutation fan-out. Fixtures now include an inert classified catalogue. Overlapping this whole case with other cases still needs an isolation review and a shared concurrency budget |
| Recall, native callbacks, typed controls and gain queries | Share the active Core engine, handler/configuration state or SQLite history; `generic and named gain filters` requires invocations produced by earlier cases | Keep ordered; a semaphore alone does not remove data dependencies. Extract self-contained setup and private databases before parallelizing |
| Import, overhead, migration and memory measurements | Paired baselines, engine restarts, process-wide allocation counters and timing observations | Keep exclusive with respect to other campaigns to avoid measurement contamination |
| Packaging/install checks | Refresh the workspace source lock and consume shared build/package inputs | Keep behind an exclusive source/packaging barrier; a different process still shares the checkout |

Execution preserves Core stage order while allowing overlap inside declared isolated batches. Git and Vagrant still fan out in separate processes **after complete Core success**, reusing the same built target and image. `MaxConcurrency` bounds the case pool as well as existing parallel-safe campaigns/companion workers.

The largest observed case is already partly parallel. It retains its ordered stage and existing bounded mutation fan-out. Isolated child cases receive internal concurrency one, so an outer batch cannot multiply its test-worker budget. Native fixture processes inside a case still consume CPU and are not additional scheduled case slots. Review repeated fixture preparation as well as scheduling; immutable template content may be reusable, but mutable Git indexes, databases and handlers must remain private.

## SemaphoreSlim and execution evidence

[Microsoft documents SemaphoreSlim](https://learn.microsoft.com/en-us/dotnet/standard/threading/semaphore-and-semaphoreslim) as an in-process primitive, without named semaphore support. It can bound asynchronous C# operations or shared runspaces in one process; it does not isolate environment variables, static state, SQLite histories or source files, and it cannot coordinate independently created child-process instances. [PowerShell's parallel execution guide](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/performance/parallel-execution?view=powershell-7.6) provides runspace-based execution and throttle limits, which already bound worker counts.

Core uses a parent-owned bounded queue of isolated PowerShell processes through `TestCaseScheduling` and `Ci.Process`, with a manifest cap of two. Performance and source-lock mutation cases run outside that pool. No C# rebuild, new runner or image pull is required to schedule these cases.

The scheduling regression verifies generated barrier plans, malformed manifests, actual process overlap and the upper bound, distinct report/configuration/database paths, literal wildcard names, deterministic receipts, serial/parallel outcome equivalence, admission closure, timeout/report failures, cancellation cleanup, no-effect WhatIf and actual concurrency/barrier mutants. Hosted elapsed time and peak memory still need measurement; configuration and local assertions do not establish a quantified CI speedup.

The nine optional Git compiler-mutation cases are explicitly IsolatedProcess and are deferred together after shared-repository scenarios. The shared budget caps their independent catalogue workers at two; each child receives one internal worker. Each catalogue restores package assets once but resets sources and forces compilation for every mutant. Mutation scheduling does not move ordinary Git prerequisites or overlap exclusive measurement barriers. Scheduler properties and pristine-build process doubles accompany the real compiled campaigns.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
