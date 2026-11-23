# Invoke-GitHubCiPlan.ps1

<!-- script-source:begin -->
Source file: [`Invoke-GitHubCiPlan.ps1`](../../scripts/Invoke-GitHubCiPlan.ps1)
<!-- script-source:end -->

Adapts the GitHub event to [New-CiImpactPlan.ps1](New-CiImpactPlan.md). It passes the exact PR description through `-PullRequestBody`, uses the push's comparison base for a delivery run and passes `-Suite` for manual dispatch. For an incomplete PR event it verifies the API snapshot against the tested merge revision. The runner receives selected options and revision metadata through the plan outputs.

<!-- script-contract:begin -->
## Execution contract

Purpose: Passes the immutable workflow revision and raw pull request body to the selective CI planner.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
