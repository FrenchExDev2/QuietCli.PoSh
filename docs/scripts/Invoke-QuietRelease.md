# Invoke-QuietRelease.ps1

<!-- script-source:begin -->
Source file: [`Invoke-QuietRelease.ps1`](../../scripts/Invoke-QuietRelease.ps1)
<!-- script-source:end -->

## Purpose and usage

Recommended release entry point. After one confirmation it creates `release/<components>-<version>-<UTC>-<id>` from the fetched remote delivery branch, commits the selected version edits, pushes only that branch, opens its pull request, waits for the required `QuietCli required CI` check and, with `-Merge`, merges with a merge commit pinned to the release head. It then tags the merge commit, pushes only those tags and restores the original branch. The operation is implemented by [Invoke-QuietRelease.psm1](lib/Invoke-QuietRelease.md) over the [ReleaseFlow](lib/ReleaseFlow.md) phases.

```powershell
./scripts/Invoke-QuietRelease.ps1 -Module Core,Git -Version 0.3.0 -NextPreview -Merge -WhatIf
./scripts/Invoke-QuietRelease.ps1 -Module Core,Git -Version 0.3.0 -NextPreview -Merge
./scripts/Invoke-QuietRelease.ps1 -Resume artifacts/releases/<id>/release-flow.json -Merge
```

Without `-Merge` the facade waits for a manual merge until `-TimeoutMinutes` (120 by default), polling every `-PollSeconds` (30 by default). A red required check, a closed pull request or a replaced head stops the run. Ctrl+C, a failure or a timeout leaves a resumable receipt and prints the exact `-Resume` command. `-WhatIf` shows the provisional plan from local metadata only: no fetch, network call, branch, commit, receipt or GitHub request.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptInvokeQuietRelease` with the bound parameters. Requires a clean checkout at the repository root, the local Core/Git modules, the GitHub CLI with existing credentials, and permission to push `release/*` branches and release tags. It never forces a push, uses `--admin`, enables auto-merge or pushes the delivery branch. Branch protection on GitHub stays authoritative for the merge.

<!-- script-contract:begin -->
## Execution contract

Purpose: Releases modules end to end: version commit on a release/* branch, pull request, required CI, merge commit, then tags.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
