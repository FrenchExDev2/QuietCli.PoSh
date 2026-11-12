# PullRequestUpdates.ps1

## Purpose and usage

An explicit `-Description <markdown>` replaces the existing PR body through `gh pr edit --body-file` after verifying the exact pushed checkpoint. Unicode and LF are preserved in an owned temporary Markdown file removed in finally. Description editing remains explicit even when a checkpoint comment already exists. Without Description, no PR metadata is changed. The scoped offline regression covers preview, duplicate comments, Unicode and description replacement.

`Send-QuietPullRequestUpdate -WorkspaceRoot $root -Remote origin -Branch fix/example [-Body $markdown]`
implements RAC-PR-001 for `Push-Workspace.ps1`. It resolves the selected GitHub remote, reads the one
existing open PR, verifies its head matches the local branch, and adds a checkpoint-marked comment
with GitHub CLI `pr comment --body-file`. Non-GitHub remotes, other branch families, missing PRs and
already-commented checkpoints are explicit skips. Ambiguous PRs and changed heads are errors.

The default body lists the PR's current commits without claiming test success. Callers can supply
a reviewed body explaining concrete changes and actual validation. It never creates a PR or edits
another comment. `-WhatIf` returns before native calls, writes or network access; `-Confirm` guards
the operation. The temporary UTF-8/LF Markdown file is removed in `finally`.

## Dependencies and effects

`Invoke-QuietPullRequestTool` uses the existing `Invoke-CiProcess` administrative boundary, captures
at most 256 KiB of stdout metadata and enforces a 60-second timeout. Failed/truncated metadata
blocks commenting. Git/GitHub CLI and preconfigured credentials are required. No credentials are
read from `.env`, installed or changed. Comment writes use the explicitly selected remote repository.

## Review and validation limits

The Core companion uses a scoped native adapter to check seeded feature/fix branches, exact repository
routing, Unicode summaries, previews, absent/ambiguous PRs, checkpoint races, duplicate suppression,
hostile remote URLs and native failures. These are offline contract tests; they do not qualify GitHub
authentication or network availability. A network failure after GitHub accepts a comment may report
failure despite the posted comment; the checkpoint marker prevents duplication on a later attempt.

Verdict: bounded, explicitly guarded PR reporting; it leaves push success/failure ownership to its caller.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads bounded administrative Git/GitHub metadata through the CI process helper.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
