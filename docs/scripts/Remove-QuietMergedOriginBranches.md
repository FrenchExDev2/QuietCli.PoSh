# Remove-QuietMergedOriginBranches.ps1

<!-- script-source:begin -->
Source file: [`Remove-QuietMergedOriginBranches.ps1`](../../scripts/Remove-QuietMergedOriginBranches.ps1)
<!-- script-source:end -->

List the branches still present on GitHub `origin` after a pull request was merged into `develop`. The default mode reads Git and GitHub and returns each branch's name, tip, pull request number, state and reason.

```powershell
./scripts/Remove-QuietMergedOriginBranches.ps1 | Format-Table Branch, PullRequest, State, Reason
./scripts/Remove-QuietMergedOriginBranches.ps1 -Apply -Confirm
./scripts/Remove-QuietMergedOriginBranches.ps1 -Apply -WhatIf
```

Use `-WorkspaceRoot` to select a checkout or `-Limit` to bound the GitHub query. The default limit is 1,000 merged pull requests. `-WhatIf` previews the operation offline. Run the default mode for the live list.

Deletion requires `-Apply` and confirmation. A branch qualifies when its live SHA exactly matches the head of the latest eligible pull request merged into `develop` from the same repository. This also covers squash and rebase merges. The default branch, `develop`, `main` and `master` are kept.

The entry point forwards parameters and common switches to the [implementation library](lib/Remove-QuietMergedOriginBranches.md). For local branch cleanup, use [Remove-QuietMergedBranches.ps1](Remove-QuietMergedBranches.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Lists or removes origin branches whose current tip matches a pull request merged into develop.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
