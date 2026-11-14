# Assert-QualificationGate.ps1

## Purpose and usage

Writes a revision-bound decision and emits `qualified_sha` only when every declared requirement succeeds. This is a scope-specific gate, not an authorization to publish by itself.

```powershell
# Core scope, with GitHub's explicit terminal exclusion.
./scripts/Assert-QualificationGate.ps1 -Suite Core -Revision $env:GITHUB_SHA -WindowsResult success -LinuxResult success -PerformanceResult success -MutationResult skipped -SkipTty -ReceiptPath ./artifacts/qualification-gate/receipt.json -OutputPath $env:GITHUB_OUTPUT
```

| Inputs | Required decision |
| --- | --- |
| WindowsResult, LinuxResult | Both exactly success. LinuxResult represents every selected container/fallback path. |
| PerformanceResult | success for scopes declaring Core evidence; skipped otherwise. |
| MutationResult | success for native Core qualification without SkipTty; skipped when TTY is excluded or outside scope. |
| RequireTooling, ToolingWorkflowResult, ToolingResult, ToolingMutationResult, ToolingCompletionResult | All exactly success when requested; all skipped otherwise. Missing outputs reject qualification. |
| Revision | Exact 40-character SHA. |
| WorkspaceRoot | Selects the validated suite catalogue; default script checkout. |
| ReceiptPath, OutputPath | Decision JSON and GitHub step output file. |

`Suite` defaults to All. Tool-only dependencies do not enable Core performance requirements. SkipTty is recorded as Excluded, never passed. Tooling functional/distribution/independence, mutation execution and catalogue completeness have separate results. Overall reusable-workflow success is required independently, including setup and artifact uploads. The saved receipt retains all four fields even after rejection; a failed functional check cannot mislabel successful mutations.

## Dependencies and side effects

Loads Common and CiCompanions, reads the suite catalogue, obtains the exact HEAD Git tree through the engine-independent repository helper, and writes UTF-8 JSON. The receipt records revision/tree, required/results fields and GitHub run/attempt. A rejected decision is saved before throwing; `qualified_sha` is appended only on acceptance. WhatIf returns before these effects.

Develop reuse separately checks identical-tree successful PR evidence. Publication separately requires All and current-run/current-attempt exact-revision evidence through Assert-QualificationReceipt; neither local receipts nor develop reuse can authorize a release.

## Critical review and verdict

`scripts/Assert-QualificationGate.ps1:43` derives requirements from declarations rather than a Git-specific branch. Property/malformed-result regressions vary platforms, profiling, tooling, mutations and TTY exclusion. Unknown suites fail before receipt emission. This gate trusts supplied authoritative job results; its generated receipt is not an independent authentication of arbitrary caller-provided success values. See [workflow wiring](../ci/github/script-ci.md).



<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [CiCompanions.psm1](lib/CiCompanions.md), [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Emits a revision-bound qualification receipt only after every required job succeeds.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
