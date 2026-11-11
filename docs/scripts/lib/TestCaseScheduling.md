# TestCaseScheduling.psm1

Case workers accept the owning declared SuiteName, defaulting to Core for existing callers. Git and Vagrant consume their own policies and write their own plans. Git currently has no isolated case opt-in because of shared fixtures/history; Vagrant explicitly opts in six pure parser cases. Both manifest caps are two. Ordered/Exclusive barriers apply within the owning suite. The All suite coordinator separately divides its shared budget among concurrent companion suites; an isolated individual case always receives one internal worker.

## Purpose and usage

Resolve a test companion's inert `PrivateData.QuietCli.TestExecution` declaration, prepare an ordered execution plan and run explicitly eligible batches in isolated PowerShell processes.

```powershell
Import-Module ./scripts/lib/TestCaseScheduling.psm1
$names = @('first', 'second')
$policy = Get-QuietTestExecutionPolicy -ManifestPath ./Companion.Tests.psd1 -CaseNames $names
$plan = Get-QuietTestExecutionPlan -CaseNames $names -Policy $policy -MaxConcurrency 4
```

`Get-QuietTestExecutionPolicy` defaults an absent declaration to Ordered with one worker. Malformed declarations, orphan case names, unknown modes/fields, invalid caps/timeouts and missing reasons fail. `Get-QuietTestExecutionPlan` preserves declaration order and groups only adjacent IsolatedProcess cases. Ordered and Exclusive cases remain individual barriers. The effective cap is the smaller of the caller budget and manifest MaxParallelCases.

## Effects and dependencies

Import is silent and function-only. Planning reads a PowerShell data file without importing its module or executing tests. `Invoke-QuietTestCaseWorkers` supports standard WhatIf/Confirm; the guard precedes directory creation, helper loading and process starts. It uses `Ci.Process.ps1` and the exact current PSHOME executable with inherited native streams, with no automatic output capture or spool.

Every child gets an owned report directory, owning companion’s exact case filter, CaseWorker flag and MaxConcurrency one. The shared worker initializes its private configuration/SQLite and prevents recursive fan-out. RID, host/runtime expectations and TTY scope are preserved. A parent validates terminal case name, selection, PID/RID, counters, suite/state/exit consistency and bounded report size. A deliberately partial single-case child is accepted only as one case inside its parent; it never becomes an independent full qualification.

Failure closes admission when requested and drains already running cases. Timeouts kill owned process trees and become failed case receipts. Cancellation and exceptional exits clean up every still-owned process in finally. Results retain declaration order; parent callbacks aggregate counters once. Existing child directories are rejected rather than reused. Native fixture processes inside a case are not separate scheduled test slots; parallel-eligible cases must not launch their own competing test-worker pool.

## Critical review

- `scripts/lib/TestCaseScheduling.psm1`: declarative permission is explicit, default execution remains ordered, and barriers prevent overlap with measurement or source-lock cases. Declarations require code review; a field is not proof of isolation.
- `FrenchExDev2.QuietCli.Core.Tests.PoSh/TestCaseScheduling.Tests.ps1`: generated plans, malformed declarations, real process overlap, exact wildcard escaping, private directories, bounded admission, serial equivalence, failure/timeout/report rejection, cancellation cleanup, WhatIf and actual library mutations exercise the contract.
- Core, Git and Vagrant consume their own manifest/catalogue policies. Suite-level Git/Vagrant fan-out still follows accepted Core; the case-worker protocol carries the owning declared suite.
- Reports establish observed worker behavior, not hosted speedup or control over unrelated workstation/runner processes. Internal native fixtures can still use CPU; measure hosted duration/memory before widening the eligible set or concurrency cap.

## Verdict

Bounded process isolation for reviewed cases with conservative barriers and engine-independent orchestration. No new build, runner, container image or image download is introduced.

<!-- script-contract:begin -->
## Execution contract

Purpose: Validates inert manifest scheduling declarations with ordered execution as the only default.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
