# Merge-PullRequest.psm1

<!-- script-source:begin -->
Source file: [`lib/Merge-PullRequest.psm1`](../../../scripts/lib/Merge-PullRequest.psm1)
<!-- script-source:end -->

`Invoke-QuietMergePullRequest` implements the [standalone merge command](../Merge-PullRequest.md). It accepts open, same-repository work-branch PRs targeting `develop`. It requires a green `QuietCli required CI` and sends `--match-head-commit` with the verified revision. GitHub still enforces its repository settings and branch protections. The result has a `Merged` state only when GitHub reports a completed merge for that head. When deletion is requested, `BranchDeleted` confirms absence on GitHub and locally. A dirty source checkout or an advanced local source ref blocks deletion before the merge. A failure after GitHub merges is reported separately.

`Invoke-QuietCommitPullRequest` is used by [Commit-Workspace.ps1](../Commit-Workspace.md). It finds the unique existing PR for the current branch, pushes the exact new revision through `Push-Workspace.ps1`, and waits up to 120 seconds for GitHub to register its Companions run. The run must match the PR, branch, event and SHA. The PR's check links can establish association when GitHub omits the PR list in the run metadata. The module launches `Watch-GitHubRun.ps1` and calls the merge operation only when requested and the exact run succeeds. The merge operation rechecks the PR head and required check.

Both operations use the existing bounded Git/GitHub adapter and standard preview guards. Unit tests use offline module-bound doubles for the GitHub results, push and watcher. The integration preview exercises the real entry point.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Identifies the GitHub repository shared by the remote's fetch and push URLs.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 2.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
