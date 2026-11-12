# Push-Workspace.ps1

## Purpose

`-PrDescriptionBodyFile <utf8.md>` explicitly replaces the verified existing PR description with `gh pr edit --body-file` after pushing. Both Markdown files are validated before the push. Description editing and commenting use the same selected remote, branch and exact head verification; WhatIf performs neither. Omitting the new option preserves comment-only behavior. Failures are reported separately from the successful push.

After a successful `feature/*` or `fix/*` push, RAC-PR-001 adds an update to the existing open PR
on the selected GitHub remote. `-PrCommentBodyFile <utf8.md>` supplies a reviewed summary of changes
and actual validation; without it, the comment lists the PR's current commits and leaves qualification
to GitHub checks. The shared [PR update helper](PullRequestUpdates.md) verifies the checkpoint and
suppresses duplicate checkpoint comments. No PR is created implicitly. Non-GitHub remotes and other
branch families keep ordinary push behavior. A comment failure prints a warning after the
successful push, so it cannot disguise a push as failed or automatically retry it.

Pushes the monorepo's single root repository's current branch to its configured remote — explicitly, with no `--force` and no automatic retry. It exists to give the release/CI pipeline one narrow, auditable "push" primitive instead of letting every script that needs to push roll its own `git push` invocation. Per `AGENTS.md` (line 43) of this module, it (together with `Commit-Workspace.ps1`) "now operate[s] on the single root repository," reflecting a prior migration away from a multi-repo model. `docs/audits/2026-11-08-ecosystem-usage-review.md` (lines 26, 40, 46, 56, 124) discusses it as part of a broader audit of mutating Git scripts, confirming this script is treated as one of the handful of git-mutating entry points in the ecosystem, alongside `Commit-Workspace.ps1` and `Publish-QuietGallery.ps1`.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `Remote` | `string` (`ValidatePattern('^[A-Za-z0-9._-]+$')`) | No | `origin` |
| `Branch` | `string` (`ValidatePattern('^[A-Za-z0-9._/-]+$')`) | No | `main` |
| `Repository` | `string` (`ValidateSet('Workspace')`) | No | `Workspace` |
| `PrCommentBodyFile` | `string` | No | Automatic commit-title summary |

```powershell
./scripts/Push-Workspace.ps1 -Branch develop
```

## Dependencies

- Dot-sources `Common.ps1` (line 16), which supplies `Invoke-WorkspaceNative` (used line 17).
- Shells out to `git` via `Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'push','--set-upstream',$Remote,$Branch) $WorkspaceRoot` (line 17) — **not** through the `quiet` facade/alias that `New-QuietPreviewTag.ps1` uses for its Git calls; instead it goes through the `Ci.Process.ps1`-backed `Invoke-WorkspaceNative` helper in `Common.ps1`, which is the documented exemption for "CI/build orchestration."
- Assumes `git` is on `PATH`, that `WorkspaceRoot` is a valid Git working tree with `Remote` already configured, and that the caller has push credentials already set up (the script does not touch credentials itself).

## Side effects

No companion tests or qualification campaign is started by this script. A feature/fix branch can be pushed explicitly before local full-suite qualification; the applicable GitHub workflows validate it. Always pass -Branch for the intended work branch: the compatibility default is main.

- Pushes `Branch` to `Remote` with `--set-upstream` (line 17) — a real, non-idempotent network/remote-state mutation. `--set-upstream` will also rewrite the local branch's tracking configuration even on branches that already track a different upstream, which is a side effect beyond "just push."
- PR reporting writes a temporary UTF-8 Markdown body and removes it after the GitHub CLI call.
  Explicit body files are validated before pushing. `-WhatIf` returns before reading these files,
  invoking Git/GitHub CLI or posting comments. No companion test campaign runs as part of push.

## Findings

- BUG-adjacent / DESIGN: `-Repository` is declared with `[ValidateSet('Workspace')]` and a hardcoded default of `'Workspace'` (line 15), but the parameter's value is **never read or used anywhere else in the 18-line body** of the script. This is dead code: a caller can pass `-Repository Workspace` (the only legal value) and it changes nothing, and if someone later adds a second value to the `ValidateSet` expecting it to route to a different behavior, nothing downstream would honor it. This parameter should either be removed (its only possible value should instead be assumed, matching the script's actual single-repository behavior, as the comment at line 1/13 states) or actually wired into the push targeting logic.
- PREVIEW: the earlier missing-ShouldProcess finding is resolved by the entry-point guard. `-WhatIf` previews the entire push operation without invoking Git; `-Confirm` controls starting it. This previews intent, not the remote server's resulting behavior. The dated ecosystem audit retains its original scope.
- CONVENTION: the file packs the entire `param()` block onto a single line (line 15) — the same dense-formatting pattern flagged in `docs/audits/2026-11-08-ecosystem-usage-review.md` line 56 for this exact script ("the entire `param()` block (four parameters, two with [validation])... on one line"). This is a pre-existing, already-documented finding, reconfirmed here.
- No input-sanitization gap: `Remote` and `Branch` are both constrained by restrictive `ValidatePattern`s (lines 15) that reject shell-metacharacter-bearing values, and the call to `git` uses an explicit argument array (`@('-C',$WorkspaceRoot,'push','--set-upstream',$Remote,$Branch)`) rather than a concatenated string, so there is no shell-injection risk through `Invoke-CiProcess`'s underlying `ProcessStartInfo` argument handling.
- Testability: the companion checks PR reporting offline using a scoped native adapter, including
  previews, repository routing, duplicate suppression and checkpoint races. Actual remote
  Git push/authentication remains an integration boundary, not an offline test assertion.

## Verdict

The push now has a standard whole-operation preview/confirmation guard. The separate finding about the compatibility `-Repository` parameter retains its documented scope.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Pushes one monorepo branch and summarizes feature/fix updates on its existing GitHub PR.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
