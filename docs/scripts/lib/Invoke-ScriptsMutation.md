# Invoke-ScriptsMutation.psm1

Implements [Invoke-ScriptsMutation.ps1](../Invoke-ScriptsMutation.md). It exports the launcher `Invoke-QuietScriptInvokeScriptsMutation`, the worker body `Invoke-QuietScriptsMutationWorker` and `Copy-QuietScriptsMutationTree`. Import defines the commands without running anything.

## Purpose and usage

The launcher performs these steps in order:
1. Rejects `-NoCache` with `-PruneCache` (`ScriptMutationCacheOptionsConflict`), then validates the roots, the targets and the `-Target` selection.
2. Generates the mutants once to fail early on a missing function.
3. Checks the monitor platform.
4. Prepares the pinned Pester.
5. Creates the run directory and writes `request.json`, with the cache directory (`<WorkspaceRoot>/.cache/script-mutation` by default, empty with `-NoCache`) and the prune flag.
6. Hands the worker to [ScriptsWorker.psm1](ScriptsWorker.md).
7. Returns `{State, Passed, Incomplete, Seed, RunDirectory, Report, Markdown, Targets, ExitCode}`. `ExitCode` is 0 only for a `Success` state with every target at or above its break. `Incomplete` is true without a report or with an incomplete one, whose stop (`Mutation stopped: target=… not-run=…; <error>`) is printed after the scores of the finished targets.

The worker performs these steps:
1. Copies the scripts root into `ThrottleLimit` slots (`Copy-QuietScriptsMutationTree`, which skips links), and starts one persistent [slot worker](ScriptMutationSlot.md) per copy.
2. For each target, generates the mutants and records the unparsable ones as `CompileError`.
3. With the cache enabled, computes every mutant's key ([ScriptMutationCache.psm1](ScriptMutationCache.md)) and reuses each cached `Killed` or `Survived` outcome. A target whose mutants are all cached runs nothing, not even its baseline.
4. Runs the unmutated baseline twice in slot 0. The first run must pass with at least one test (`ScriptMutationBaselineFailed`). The second must pass the same number of tests in the same worker (`ScriptMutationSlotStateLeak`), which proves the reset between runs works for this target. The per-mutant deadline comes from the slower of the two.
5. Writes each remaining mutant into an idle slot's copy and submits it with bail-on-first-failure. When the outcome arrives, the original bytes are restored.
6. Restarts a slot that crashed or timed out, and recycles every slot after `RecycleAfter` jobs. A `Corrupted` outcome replays the mutant once on a fresh slot, then fails with `ScriptMutationSlotCorrupted`.
7. Writes each new `Killed` or `Survived` outcome to the cache.
8. Writes `report.json`, `mutants.json` and `report.md`. With `-PruneCache`, it then deletes every cache document no key of this campaign uses. This happens only here, after every selected target was keyed, so an aborted campaign never prunes.
9. Writes the terminal `status.json` and `summary.json`, stops the slots and deletes the copies.

When the campaign stops before step 8 (a failed baseline, a slot state leak, a corrupted slot or any other error), the worker still writes `report.json`, `mutants.json` and `report.md` before it reports the crash. The report scores only the targets finished in request order and is `Incomplete`, with `Crash = {Target, Error, NotRun}`. `mutants.json` also holds the outcomes already reached in the target that stopped, which the cache keeps too. The status case reads `Mutation campaign stopped in <target>; <finished> of <total> targets finished`. A failure after the reports were written (a prune) keeps the complete report and only sets the `Crash` state.

`Passed` and `Failed` in the status count detected and surviving mutants. Each target in the report carries `Cached`, the number of outcomes reused.

## Dependencies and side effects

Imports ScriptMutation, ScriptMutationCache, ScriptMutationSlot, RunToolCache, WorkspaceJson, ReportPaths and ScriptsWorker. Its side effects are those listed for [Invoke-ScriptsMutation.ps1](../Invoke-ScriptsMutation.md).

## Critical review and verdict

A slot runs one mutant at a time, and the original bytes are written back before the slot is reused, so two mutants never share a source. The engine fingerprint in every cache key includes Pester, PowerShell, the platform and the hashes of `ScriptMutationSlot.psm1` and `ScriptsTests.psm1`, so a change to how tests run invalidates the whole cache. An exception in the worker becomes a `Crash` status with the message and an incomplete report of the finished targets, and the slots are still stopped and deleted. The integration test drives the real entry point on a fixture library, so this library is covered end to end rather than by line coverage.

<!-- script-contract:begin -->
## Execution contract

Purpose: Validates the targets, prepares the pinned Pester, then launches and supervises one mutation campaign; returns its outcome.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
