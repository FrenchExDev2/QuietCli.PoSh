# Commit-Workspace.ps1

## Purpose

Creates exactly one Git commit of the whole monorepo (after refreshing the project lock) with an optional, de-duplicated `Co-Authored-By` trailer, and deliberately never pushes — intended as the one safe "checkpoint" primitive for an agent (Claude/Codex) or a human to use after making changes. Per the repository's own prior audit (`docs/audits/2026-11-08-ecosystem-usage-review.md`, GAP-01, lines 23-27), **no caller was found anywhere in this repository**: not in any `.github/workflows/*.yml`, not dot-sourced or invoked by any other script in `scripts/`, and not referenced by any Pester `*.Tests.ps1` file. A fresh search performed for this review confirms the same: no match for `Commit-Workspace` exists outside this file itself, `AGENTS.md`, the prior audit document, and `docs/scripts/Push-Workspace.md`/`Update-WorkspaceLock.md`. It appears to be intended for direct, ad hoc invocation, not as part of any automated pipeline.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Message` | `string` | Yes | none |
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `Repository` | `string` (`ValidateSet('Workspace')`) | No | `'Workspace'` |
| `CoAuthoredBy` | `string[]` | No | `$null` |

```powershell
./scripts/Commit-Workspace.ps1 -Message "Add Build-Workspace DRY refactor" -CoAuthoredBy Claude
```

## Dependencies

- Dot-sources `Common.ps1` (line 19) for `Invoke-WorkspaceNative`.
- Invokes `scripts/Update-WorkspaceLock.ps1` as a child script before staging (line 29).
- Shells out to `git` twice: `add --all --` (line 30) and `commit -m` (line 31).
- Assumes `git` is on `PATH` and `$WorkspaceRoot` is the root of a Git working tree.

## Side effects

- Runs `Update-WorkspaceLock.ps1`, mutating the workspace lock file (line 29).
- Stages everything in the working tree with no path scoping (`git add --all --`, line 30).
- Creates exactly one commit (line 31). Never pushes, per its own `.SYNOPSIS`.

## Findings

- DESIGN: `Repository` is `[ValidateSet('Workspace')]` with a single legal value (line 18). A parameter that can only ever take one value functions as documentation dressed up as a parameter — it does add a small amount of defensive "reject a request for an independent module commit" value per its own comment (lines 10-11), but it is unusual API surface for a constant.
- DESIGN/BUG-risk: `git add --all --` (line 30) stages absolutely everything in the working tree with no scoping, confirmation, or preview, and the script has no `-WhatIf`/`SupportsShouldProcess` guard. The repository's own prior audit independently flags exactly this (GAP-01, lines 23-27): "Neither takes `-WhatIf`, and both [this script and `Push-Workspace.ps1`] are one real `git commit` / `git push` away from changing a shared history," rated **medium severity** there.
- Testability: confirmed again in this review — zero references to `Commit-Workspace` exist in any `*.Tests.ps1` file, any workflow YAML, or any other script in `scripts/`. This reproduces the prior audit's GAP-01 finding rather than discovering something new, but it's worth restating: the one script in this folder that mutates shared Git history by committing the entire working tree has **no automated test of any kind**, not even the fixture the audit document itself proposes (lines 44-48): "refreshes the lock before staging, commits exactly once, never touches a remote."
- The `$knownCoAuthors` map (line 20) hardcodes two agent identities (`Claude`, `Codex`) inline in the script body, even though the adjacent doc comment (line 16) points to `docs/agents/README.md` as "the documented list" — so the script's actual single source of truth is this inline map, not the document it cites, and the two could silently drift apart.

## Verdict

Needs rework. This review reinforces the repository's own prior finding: the complete absence of any test for "stage everything, refresh lock, commit once, never push" on the one script that mutates the monorepo's shared Git history is the single highest-priority fix, closely followed by adding a `-WhatIf`/confirmation guard around the unscoped `git add --all`.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
