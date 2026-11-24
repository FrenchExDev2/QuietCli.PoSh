# PullRequestCi.psm1

<!-- script-source:begin -->
Source file: [`lib/PullRequestCi.psm1`](../../../scripts/lib/PullRequestCi.psm1)
<!-- script-source:end -->

Reads the current PR identity and options via GitHub CLI. `Test-QuietPullRequestCiSelection` compares the normalized selection and exact revisions with a plan or receipt. `Assert-QuietPullRequestCiEvidence` requires a successful latest associated PR run and its matching receipt, then rereads the PR before scripted merge. These reads require access to GitHub Actions and the PR.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads the CI-relevant state of an open GitHub pull request.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
