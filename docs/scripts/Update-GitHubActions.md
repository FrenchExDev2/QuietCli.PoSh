# Update-GitHubActions.ps1

## Purpose and usage

This entry point preserves its parameters and defaults and forwards explicitly bound parameters, including standard preview options, to [Update-GitHubActions.psm1](lib/Update-GitHubActions.md). See that library for the full operation, decision rules, dependencies, effects and validation limits.

```powershell
./scripts/Update-GitHubActions.ps1                                   # report only
./scripts/Update-GitHubActions.ps1 -Apply -WhatIf                    # preview each file
./scripts/Update-GitHubActions.ps1 -Apply -Confirm                   # ask per file
./scripts/Update-GitHubActions.ps1 -Apply -RefreshWorkflowReceipts -Confirm:$false
./scripts/Update-GitHubActions.ps1 -Include 'actions/*' -Exclude 'actions/cache'
```

Every remote `uses:` reference of `.github/workflows/*.yml` or `.yaml` and `.github/actions/**/action.yml` or `.yaml` moves to the latest release of its action. A commit pin stays a commit pin and its `# vX.Y.Z` comment follows the tag. Set `GH_TOKEN` (for example `$env:GH_TOKEN=(gh auth token)`) to avoid the anonymous API rate limit.

## Dependencies and effects

Imports its local library using `-DisableNameChecking -ErrorAction Stop` and invokes `Invoke-QuietScriptUpdateGitHubActions`. The library retains the operation guards and output contract. Import alone does not run the operation.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reports, and with -Apply writes, the latest release of every action referenced by the GitHub workflows and composite actions.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
