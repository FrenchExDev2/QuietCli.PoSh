# Merge-PullRequest.ps1

<!-- script-source:begin -->
Source file: [`Merge-PullRequest.ps1`](../../scripts/Merge-PullRequest.ps1)
<!-- script-source:end -->

Merge an existing workspace PR by number once `QuietCli required CI` has succeeded and the latest receipt matches its current revision and options. See [PR checklist and merge evidence](../README-pull-request-ci.md).

```powershell
./scripts/Merge-PullRequest.ps1 -PullRequest 123 -WhatIf
./scripts/Merge-PullRequest.ps1 -PullRequest 123
./scripts/Merge-PullRequest.ps1 -PullRequest 123 -NoRebase -NoBranchDelete
```

The default is rebase and merge, followed by deletion of the source branch on GitHub and locally. `-NoRebase` selects a merge commit. `-NoBranchDelete` preserves the branch. GitHub's repository-level automatic deletion must be disabled to preserve a branch. Use `-ExpectedHead` to pin the merge to a previously reviewed 40-character SHA. The default remote is `origin`.

The script uses standard `-WhatIf` and `-Confirm`. Preview makes no Git or GitHub calls. The [library contract](lib/Merge-PullRequest.md) explains the checks, confirmation and results.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Merges a checked workspace pull request and deletes its source branch by default.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
