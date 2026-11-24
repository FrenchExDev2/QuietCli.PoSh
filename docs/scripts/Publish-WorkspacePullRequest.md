# Publish-WorkspacePullRequest.ps1

<!-- script-source:begin -->
Source file: [`Publish-WorkspacePullRequest.ps1`](../../scripts/Publish-WorkspacePullRequest.ps1)
<!-- script-source:end -->

From a work branch with changes ready to commit, publish a pull request targeting `develop` and follow its GitHub Actions jobs.

```powershell
# Run from the repository root.
$body = @'
## Changes

Explain the change and its local validation.
'@
./scripts/Publish-WorkspacePullRequest.ps1 -Message 'Describe the change' -Body $body -RunProfile Git,Vagrant -Mutation -Profiling
```

- `-RunProfile` selects companions from `build/companions.yaml`. Combine `-Mutation` and `-Profiling` to profile each companion's mutation pass. Mutation with `-RunProfile` enables profiling by default. Use `-Profiling:$false` for a mutation-only pass.
- `-RunProfileMutation` accepts a list of companions with a declared mutation campaign.
- `-RunProfile Git,Vagrant -Performance` checks the performance option for each named companion. This runs a timed, unprofiled test pass in a separate job.
- `-ScriptMutation` selects the repository script mutation catalogue.
- `-ScriptMutationNoInputCache` checks the box to rerun selected script mutants and refresh the cache.
- `-Parallel:$false` runs the requested companion checks one at a time and selects one worker per mutation shard. Each mutation matrix also runs one shard at a time in this mode.
- `-ReadyToRun` checks the IL and ReadyToRun cold-start comparison.
- `-Preview` checks the extra PowerShell Preview hosts for Core.

Omitted switches preserve any boxes already present in `-Body`. Use `-Preview:$false` or the corresponding false switch to clear a box. `-Footer` appends Markdown. The first line of `-Message` supplies the default title for a new PR. Override it with `-Title`. The checklist links to the guide at the published commit.

The command validates and commits all changes on the active work branch, verifies the local CI plan for the new SHA and pushes that SHA to `origin`. It updates an existing PR description before push so the new SHA's CI reads the requested options. It creates a missing PR after push. After verifying the published head and description, it switches the clean checkout to local `develop` and follows the associated Companions workflow. A successful run, required check and matching CI receipt allow a fast-forward-only pull from `origin/develop`. The PR stays open for review and merge.

`-WhatIf` returns before Git, GitHub or filesystem effects. If a step fails, the error identifies the step and any known branch, SHA, PR and run. Completed operations remain in place for human follow-up. Once switched, the checkout stays on `develop` and a CI failure stops before the pull.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Commits and publishes a work branch, then monitors its pull request from develop.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
