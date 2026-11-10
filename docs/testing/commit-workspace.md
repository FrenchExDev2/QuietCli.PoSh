# Commit companion boundaries and PSDrive feasibility

## Local checkpoint versus CI qualification

Local feature/fix-branch commits and pushes do not require companion execution. Commit-Workspace runs the shared source/documentation checks and lock validation; Push-Workspace only performs the explicitly selected push. Neither script launches companion tests. Full local campaigns require an explicit request or prior agreement. Required qualification belongs to the applicable GitHub workflows and publication gates; a local checkpoint does not claim that qualification passed.

## What the current suite actually does

Core is a custom PowerShell case runner, not a Pester Describe/It suite. Core and All contain both pure assertions and integration workloads. The special Integration suite selects Core import/performance evidence, not every test that performs integration effects.

| Case or helper | Boundary | Observable effects |
| --- | --- | --- |
| Test-QuietByteCountParsing | Unit | Parses sizes and rejects malformed values; no file/process operations in the test body |
| New-QuietCommitWorkspaceFixture | Integration setup | Creates a physical temporary directory, runs git init/config/add/commit and generates source/documentation contracts |
| Test-QuietCommitWorkspace | Integration plus properties/mutation | Exercises the real commit script, staged indexes, HEAD, file content, warnings and WhatIf against disposable repositories |
| Test-QuietAutomationCommitChecks | Integration | Checks staged workflow/preview policy and unstaged repair rejection using real Git indexes |
| Test-QuietResourceCommitChecks | Integration | Checks staged resource/script documentation and explicit skips using real Git indexes |
| Report streaming checks | Filesystem integration | Appends fragmented UTF-8, truncates files and checks bounded read-only tails |

The commit campaign creates fresh repositories for independent scenarios and repeats scenarios against eleven targeted script mutants. These are real Git integration checks, not pure unit tests. Generated properties and mutation are testing techniques; they do not remove filesystem/process dependencies. The repositories live under the run's external temporary report directory and are retained with failure evidence.

Known cases now report TestKind and Dependencies, and progress names show the reviewed boundary before execution. Unreviewed cases remain Unclassified rather than being implicitly declared Unit. The pure byte-count assertions have their own selectable case; their existing invocation inside the commit campaign remains useful for the full integration baseline. Runner startup and report writing still use the filesystem even for a pure test body.

## Would a virtual PSDrive remove Git I/O?

No. A FileSystem PSDrive maps a PowerShell name to a real directory. Temporary PSDrive names are session-local; native tools and .NET file APIs require a physical path. Microsoft's [New-PSDrive documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-psdrive?view=powershell-7.6) describes this boundary.

Pester's [TestDrive](https://pester.dev/docs/usage/testdrive) also creates a random temporary directory on the filesystem. Its variable form provides the physical path for .NET/native consumers. It isolates and cleans up file activity; it does not make it memory-only.

A PSDrive could therefore provide a convenient alias around the existing owned temporary root, but would not eliminate git init, index/commit writes or child processes. The current fixtures use System.IO and Git directly, so a custom in-memory PowerShell provider would not substitute for those APIs. Real Git index/HEAD/partial-staging behavior must retain a real filesystem integration test. Automatic TestDrive deletion would also conflict with retaining failed-run diagnostics unless evidence were exported first.

## Feasible separation

~~~mermaid
flowchart TD
    L[Local feature or fix checkpoint] --> C[Source and documentation checks]
    C --> P[Explicit commit and push]
    P --> G[Applicable GitHub workflows]
    G --> U[Pure logic properties and malformed-input cases]
    G --> I[Git and filesystem integration fixtures]
    G --> M[Required mutation and platform campaigns]
    A[Explicit local test request] --> S[Selected development scope]
    S --> U
    S --> I
~~~

Extract pure option mapping, byte-count parsing, warning classification and commit-message construction into cohesive functions with injected boundaries where useful. Keep a small set of real-Git invariants for HEAD/index integrity and publication/remote boundaries. Reuse prepared immutable fixture content where isolation remains independently proved; do not share mutable indexes between cases. A full Unit/Integration filter needs the remaining cases reviewed first: this change labels the reviewed subset and does not advertise Core as unit-only.

This is a source review and classification change. The interrupted All run was explicitly cancelled; it is not a successful qualification. No additional companion campaign was started for the local checkpoint policy change. Existing targeted evidence retains its recorded scope, and the next applicable GitHub workflow must validate the changed runner metadata and remaining contracts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
