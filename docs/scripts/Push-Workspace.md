# Push-Workspace.ps1

## Purpose

Pushes the monorepo's single root repository's current branch to its configured remote — explicitly, with no `--force` and no automatic retry. It exists to give the release/CI pipeline one narrow, auditable "push" primitive instead of letting every script that needs to push roll its own `git push` invocation. Per `AGENTS.md` (line 43) of this module, it (together with `Commit-Workspace.ps1`) "now operate[s] on the single root repository," reflecting a prior migration away from a multi-repo model. `docs/audits/2026-11-08-ecosystem-usage-review.md` (lines 26, 40, 46, 56, 124) discusses it as part of a broader audit of mutating Git scripts, confirming this script is treated as one of the handful of git-mutating entry points in the ecosystem, alongside `Commit-Workspace.ps1` and `Publish-QuietGallery.ps1`.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `Remote` | `string` (`ValidatePattern('^[A-Za-z0-9._-]+$')`) | No | `origin` |
| `Branch` | `string` (`ValidatePattern('^[A-Za-z0-9._/-]+$')`) | No | `main` |
| `Repository` | `string` (`ValidateSet('Workspace')`) | No | `Workspace` |

```powershell
./scripts/Push-Workspace.ps1 -Branch develop
```

## Dependencies

- Dot-sources `Common.ps1` (line 16), which supplies `Invoke-WorkspaceNative` (used line 17).
- Shells out to `git` via `Invoke-WorkspaceNative git @('-C',$WorkspaceRoot,'push','--set-upstream',$Remote,$Branch) $WorkspaceRoot` (line 17) — **not** through the `quiet` facade/alias that `New-QuietPreviewTag.ps1` uses for its Git calls; instead it goes through the `Ci.Process.ps1`-backed `Invoke-WorkspaceNative` helper in `Common.ps1`, which is the documented exemption for "CI/build orchestration."
- Assumes `git` is on `PATH`, that `WorkspaceRoot` is a valid Git working tree with `Remote` already configured, and that the caller has push credentials already set up (the script does not touch credentials itself).

## Side effects

- Pushes `Branch` to `Remote` with `--set-upstream` (line 17) — a real, non-idempotent network/remote-state mutation. `--set-upstream` will also rewrite the local branch's tracking configuration even on branches that already track a different upstream, which is a side effect beyond "just push."
- No local file writes beyond whatever `Invoke-WorkspaceNative`'s optional logging does (no `-LogPath` is passed here, so none).

## Findings

- BUG-adjacent / DESIGN: `-Repository` is declared with `[ValidateSet('Workspace')]` and a hardcoded default of `'Workspace'` (line 15), but the parameter's value is **never read or used anywhere else in the 18-line body** of the script. This is dead code: a caller can pass `-Repository Workspace` (the only legal value) and it changes nothing, and if someone later adds a second value to the `ValidateSet` expecting it to route to a different behavior, nothing downstream would honor it. This parameter should either be removed (its only possible value should instead be assumed, matching the script's actual single-repository behavior, as the comment at line 1/13 states) or actually wired into the push targeting logic.
- DESIGN/CONVENTION: this script offers **no `-WhatIf`/`SupportsShouldProcess`** despite being one of the two scripts the ecosystem audit (`docs/audits/2026-11-08-ecosystem-usage-review.md` line 46) explicitly calls out as needing confirmation-safe behavior: "`Push-Workspace.ps1` never force-pushes." The audit's own framing implies this script is expected to be used carefully by humans/CI, but there's no built-in dry-run capability to preview what would be pushed before doing it — unlike `New-QuietPreviewTag.ps1` (same folder), which does support `-WhatIf`. Given this script performs an irreversible remote mutation, adding `SupportsShouldProcess`/`-WhatIf` (gating the `Invoke-WorkspaceNative` call) would bring it in line with the repo's own safety conventions for mutating operations.
- CONVENTION: the file packs the entire `param()` block onto a single line (line 15) — the same dense-formatting pattern flagged in `docs/audits/2026-11-08-ecosystem-usage-review.md` line 56 for this exact script ("the entire `param()` block (four parameters, two with [validation])... on one line"). This is a pre-existing, already-documented finding, reconfirmed here.
- No input-sanitization gap: `Remote` and `Branch` are both constrained by restrictive `ValidatePattern`s (lines 15) that reject shell-metacharacter-bearing values, and the call to `git` uses an explicit argument array (`@('-C',$WorkspaceRoot,'push','--set-upstream',$Remote,$Branch)`) rather than a concatenated string, so there is no shell-injection risk through `Invoke-CiProcess`'s underlying `ProcessStartInfo` argument handling.
- Testability: no Pester test exercises this script (expected — it mutates a real remote, which is exactly the kind of operation the repo's testing conventions would want to keep out of an automated suite without a disposable throwaway remote). This is an accepted qualification gap rather than an oversight, consistent with how `New-QuietPreviewTag.ps1` tests only the local, non-networked tag-creation step and leaves pushing untested.

## Verdict

Functionally correct and appropriately minimal for what it does, but needs a small rework: remove the unused `-Repository` parameter (or wire it to real behavior) and add `SupportsShouldProcess`/`-WhatIf` before this script's irreversible remote push, matching the safety bar `New-QuietPreviewTag.ps1` already sets in the same folder.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
