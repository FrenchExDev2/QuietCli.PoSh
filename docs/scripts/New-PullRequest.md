# New-PullRequest.ps1

<!-- script-source:begin -->
Source file: [`New-PullRequest.ps1`](../../scripts/New-PullRequest.ps1)
<!-- script-source:end -->

Creates a GitHub pull request from a branch already pushed to the selected remote. It expands the repository's English CI checklist from `build/companions.yaml` and accepts an optional Markdown footer.

On GitHub, the checklist links to the guide at the pushed revision. `-PreviewBody` uses the versioned template's links and works offline.

```powershell
./scripts/New-PullRequest.ps1 -BodyFile ./description.md -FooterFile ./notes.md -CiOption run-profile-mutation-git,profiling-git -PreviewBody
./scripts/New-PullRequest.ps1 -Title 'Explain the change' -BodyFile ./description.md -FooterFile ./notes.md -CiOption run-profile-mutation-git,profiling-git
```

The defaults are the checked-out branch, `origin` and `develop`. Override them with `-Head`, `-Remote` and `-Base`. An existing open PR for the same source and target is returned as-is. Preview creation with `-WhatIf` to see the operation before the script prepares the body or contacts GitHub. Use `-PreviewBody` to return the composed description, including the companion table. Passing an empty `-CiOption @()` clears a selection already present in the description.

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
