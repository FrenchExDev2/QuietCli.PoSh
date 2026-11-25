# PesterProgress.psm1

<!-- script-source:begin -->
Source file: [`lib/PesterProgress.psm1`](../../../scripts/lib/PesterProgress.psm1)
<!-- script-source:end -->

Loads the checksum-pinned Pester 6.2.0 from the workspace test-tool cache. Use `Import-QuietTestPester` with the workspace root or with the manifest already resolved by a launcher.

The loader reuses a prepared manifest inherited from the worker when it matches the pinned cache path in the current checkout. Offline workers initialize from their cached archive when they need to prepare the manifest.

`Invoke-QuietPesterCaseTable -PesterModulePath` accepts the verified manifest from an owning checkout when an isolated fixture has its own copy of the scripts.

`Invoke-QuietPesterWithProgress` forwards test start and completion from Pester's test hooks. Success and failure counts come from completed tests. Crashes and setup failures remain in the run state and qualification report. The hook uses the plugin registration interface of the pinned Pester version, so verify the progress tests before upgrading Pester.

`Invoke-QuietPesterCompanionPlan` registers one Pester `It` per selected case. It preserves the declared order, explicit isolated-process batches, case filters and stop-on-first-failure. It writes one progress receipt per completed in-process case so the `All` worker can follow several companions at once. `Invoke-QuietPesterCaseTable` also runs focused PowerShell suites directly. When a focused suite supplies assertions to an already running test, its assertions run in that owning `It`.

The test runners keep their existing fixtures, mutation receipts and architecture checks. The C# and native C test binaries still execute in their dedicated harnesses.

<!-- script-contract:begin -->
## Execution contract

Purpose: Loads the workspace's checksum-pinned Pester into the test process.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
