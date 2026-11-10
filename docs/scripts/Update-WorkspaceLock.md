# Update-WorkspaceLock.ps1

## Purpose

Writes `repositories.lock.json` at the workspace root — a single-repository, multi-project
content-identity record (per-project source SHA-256, declared inter-project dependencies, and the
pinned SDK/runtime versions) for this monorepo. This gives the monorepo a cheap, deterministic way to
answer "has any project's source changed since the last recorded state" without re-hashing everything
ad hoc each time, and records inter-project dependency edges discovered from each project's manifest.
`AGENTS.md:43` documents it as a required step: "Before an explicit commit, refresh
`scripts/Update-WorkspaceLock.ps1`." It is called by `Commit-Workspace.ps1:28` (unconditionally before
every commit) and by `Initialize-Workspace.ps1:27` (as part of first-time workspace setup), and is
exposed as the VS Code task `"QuietCli2: source lock"` in `.vscode/tasks.json:6`. It is explicitly
*not* a publish step — its own returned object states `Published=$false` and the doc comment stresses
it never "tries to pin a repository to its own future commit."

## Usage

```
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
```

- `WorkspaceRoot` (string, optional) — the QuietCli2 monorepo root. Defaults to the script's parent
  directory. This is the only parameter; there is no `-Apply`/report-only distinction — it always
  writes.

Example:

```powershell
./scripts/Update-WorkspaceLock.ps1
```

## Dependencies

- Dot-sources `Common.ps1` (line 10), which provides `Write-WorkspaceJson` (used at line 15) and
  transitively loads `SourceIdentity.ps1` for `Get-QuietWorkspaceIdentity` (called at line 11) and
  `WorkspaceProjects.ps1` for `Get-QuietWorkspaceProjects` (called at line 13).
- `Get-QuietWorkspaceIdentity` (see `SourceIdentity.ps1` review) shells out to `git` for revision,
  remote URL, dirty-state, and tracked-file listing, when `.git` exists at `WorkspaceRoot`.
- No filesystem pre-conditions beyond what `Get-QuietWorkspaceIdentity`/`Get-QuietWorkspaceProjects`
  already require (presence of `global.json`, `protocol.json`, `Directory.Packages.props`, and every
  discovered project's manifest).

## Side effects

- Overwrites `repositories.lock.json` at `WorkspaceRoot` unconditionally (line 15), via
  `Write-WorkspaceJson`'s atomic-rename write.
- Indirectly, through `Get-QuietWorkspaceIdentity`, issues several read-only `git` subcommands
  (`rev-parse`, `remote get-url`, `status --porcelain`, `ls-files`) — no git state is mutated.
- Returns a `[pscustomobject]` summary (`Repositories`, `Projects` count,
  `RevisionRecordedOnlyInBuildReports=$true`, `Published=$false`) — the field names themselves
  document two explicit non-goals (revision is *not* recorded in this file; this is *not* a publish).

## Findings

- BUG (minor/latent): line 15 hardcodes `SDK='11.0.100-rc.3.26522.148'` and
  `Runtime='11.0.0-rc.3.26522.148'` as literal string constants in the lock file, while the
  repository's actual pinned SDK version lives in `global.json` and is read dynamically elsewhere
  (e.g. `Test-SdkReadiness.ps1`'s `Get-QuietPinnedSdk`). If `global.json` is ever bumped to a newer
  SDK/runtime version without someone remembering to also edit this literal in
  `Update-WorkspaceLock.ps1`, every subsequent lock-file regeneration will silently record a stale,
  incorrect SDK/Runtime value — there is no cross-check between this hardcoded string and the actual
  `global.json` content. This is exactly the kind of "hardcoded value that should be a parameter (or
  at least read from its source of truth)" the review brief asks to flag.
- PREVIEW: the entry-point ShouldProcess guard now supports `-WhatIf`/`-Confirm` before lock
  generation. WhatIf previews the operation without writing or computing a prospective lock;
  it is not a content diff. Commit-Workspace also retains its own guarded lock-refresh boundary.
- CONVENTION: no async-I/O violation specific to this file — it delegates all actual I/O to
  `Write-WorkspaceJson` and `Get-QuietWorkspaceIdentity`, which this review covers separately; this
  script's own body (lines 11-16) is just four lines of orchestration with no direct file I/O of its
  own.
- Testability gap: no Pester test references `Update-WorkspaceLock.ps1` directly by name (searched,
  no hits in either `*.Tests.PoSh` project) even though
  `FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1:663` calls it as part of some larger test-support
  workflow (`$null=& (Join-Path $WorkspaceRoot 'scripts/Update-WorkspaceLock.ps1') -WorkspaceRoot
  $WorkspaceRoot`) — that confirms the script is *exercised* as a side effect of another test support
  routine, but there is no assertion anywhere found that checks the *content* of the resulting
  `repositories.lock.json` (e.g. that the hardcoded SDK/Runtime strings match `global.json`, or that
  `Dependencies` correctly reflects each project's `RequiredModules`). Given the hardcoded-version risk
  identified above, a simple assertion comparing the lock file's `SDK` field against `global.json`'s
  `sdk.version` would have caught drift immediately and is currently missing.
- No security concern: purely local metadata generation from already-trusted repository content.

## Verdict

Functionally does what AGENTS.md requires (a pre-commit source lock refresh), but the hardcoded
`SDK`/`Runtime` version literals (line 15) are a silent-drift risk that should instead be read from
`global.json` the way `Test-SdkReadiness.ps1` already does — that is the single highest-priority fix,
ideally paired with a test asserting the two stay in sync.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Updates project hashes without committing, pushing or trying to pin a repository to its own future commit.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
