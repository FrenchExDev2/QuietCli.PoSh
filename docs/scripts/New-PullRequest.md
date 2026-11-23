# New-PullRequest.ps1

<!-- script-source:begin -->
Source file: [`New-PullRequest.ps1`](../../scripts/New-PullRequest.ps1)
<!-- script-source:end -->

Creates a GitHub pull request from a branch already pushed to the selected remote. It uses the repository's English CI checklist and accepts an optional Markdown footer.

```powershell
./scripts/New-PullRequest.ps1 -BodyFile ./description.md -FooterFile ./notes.md -CiOption mutation,preview -PreviewBody
./scripts/New-PullRequest.ps1 -Title 'Explain the change' -BodyFile ./description.md -FooterFile ./notes.md -CiOption mutation,preview
```

The defaults are the checked-out branch, `origin` and `develop`. Override them with `-Head`, `-Remote` and `-Base`. An existing open PR for the same source and target is returned as-is. The source Markdown files remain unchanged. `-WhatIf` makes no remote call and creates no temporary file. `-PreviewBody` returns the exact composed text. Passing an empty `-CiOption @()` clears a selection already present in the description.

<!-- script-contract:begin -->
## Execution contract

Purpose: Creates a workspace pull request with the standard CI checklist and optional Markdown footer.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
