# Initialize-Workspace.ps1

## Purpose

Verifies that a checked-out monorepo is structurally sound as a single-repository, multi-project
layout: every discovered internal project has its own manifest (`<name>.psd1`), none of them is secretly
a nested git repository, and (when `-Restore` is passed) the recorded source lock
(`repositories.lock.json`) matches the actual on-disk source hashes, then restores Core's pinned
third-party resources (`Restore-CoreResources.ps1`) so a fresh clone is ready to build. This operationalizes the
`AGENTS.md` "Monorepos multi-projets" rule that a monorepo has one `.git` at its root and no child
submodules. It is a verification/bootstrap step rather than something invoked by other scripts in this
folder (no caller was found via grep across `scripts/`); it is meant to be run directly by a developer
or CI step at workspace setup/restore time.

## Usage

Parameters:
- `-WorkspaceRoot` (string, optional, default `(Split-Path $PSScriptRoot -Parent)`) — the QuietCli2 monorepo root.
- `-Restore` (switch, optional, default `$false`) — verifies the existing source lock instead of regenerating it; does not modify source files or select a branch.

Example:
```powershell
./scripts/Initialize-Workspace.ps1 -WorkspaceRoot C:\code\FrenchExDev\FrenchExDev_i2\PoSh\FrenchExDev\QuietCliEcosystem\FrenchExDev2.QuietCli.PoSh -Restore
```

## Dependencies

- Dot-sources `Common.ps1` (line 12), which in turn dot-sources `ReportPaths.ps1`, `Ci.Process.ps1`, `SourceIdentity.ps1`, `RuntimeTargets.ps1`.
- Calls `Get-QuietWorkspaceProjects` (presumably defined in one of the dot-sourced files or a lib module — not located within this review's scope; likely `WorkspaceProjects.ps1`, which is not dot-sourced here directly, so it must come transitively or this is a latent dependency gap) and `Get-QuietWorkspaceIdentity`.
- When `-Restore` is set, delegates to `Restore-CoreResources.ps1` (line 27) after the lock check succeeds,
  to populate Core's untracked SQLite/tokenizers/YamlDotNet binaries from their pinned NuGet sources.
- When `-Restore` is *not* set, delegates to `Update-WorkspaceLock.ps1` (line 28) to regenerate the lock.
- Reads `repositories.lock.json` from `$WorkspaceRoot` with `Get-Content -Encoding utf8 -Raw` (line 22).
- Filesystem assumption: `$WorkspaceRoot/.git` must exist (line 14); each project folder named by `Get-QuietWorkspaceProjects` must contain `<name>.psd1` and must *not* contain a `.git` folder.
- No external native tool invocation (no git/dotnet/docker shell-outs) in this file itself.

## Side effects

- Throws (no writes) on structural violations; otherwise read-only except that the non-`-Restore` path invokes `Update-WorkspaceLock.ps1`, whose side effects (presumably writing/refreshing `repositories.lock.json`) are opaque from this file and not reviewed here.
- Returns a `[pscustomobject]` summary (`Layout`, `Repositories`, `Projects`, `Restored`, `Verified`) — note `Restored` is hardcoded to `$false` (line 28) even when `-Restore` was passed and succeeded; see Findings.

## Findings

- BUG: Line 28 always reports `Restored=$false` in the returned object, even when `-Restore` was specified and the restore-path validation succeeded. A caller inspecting this return value to determine whether a restore happened would always see `false`, which is misleading/incorrect.
- CONVENTION: No explicit UTF-8 output enforcement; the one explicit read (line 22) does specify `-Encoding utf8`, which is good, but console output (the final `[pscustomobject]`) and error messages do not enforce an encoding — likely inherited from the calling profile's UTF-8 initialization per `AGENTS.md`, but this script does not independently guarantee it if run standalone without a profile.
- DESIGN: `Get-QuietWorkspaceProjects` and `Get-QuietWorkspaceIdentity` are used but their defining file is not dot-sourced in this script directly (only `Common.ps1` is, at line 12, and `Common.ps1` itself does not dot-source `WorkspaceProjects.ps1` per the file shown). This script likely relies on these functions already being loaded by caller context or a module auto-load mechanism not visible here — worth confirming, since direct execution of this script without that context would fail with "command not found" at line 15/24.
- Missing input validation: `-WorkspaceRoot` has no existence check before `[IO.Path]::GetFullPath` (line 13); a typo'd path produces a generic `.git` missing error (line 14) rather than a clearer "workspace root not found" message.
- No dedicated Pester test (`*.Tests.ps1`) was found for `Initialize-Workspace.ps1` in the repo.
- No other script in `scripts/` calls this one (confirmed via grep across the folder), meaning it is only a manual/CI entry point; this is consistent with its verification purpose but means any regression here is caught only by direct invocation, not by the rest of the pipeline.

## Verdict

Mostly fit for purpose as a structural guard rail, but the hardcoded `Restored=$false` on line 28 is a real correctness bug in its reported output and should be fixed first; secondarily, confirm `Get-QuietWorkspaceProjects`/`Get-QuietWorkspaceIdentity` are reliably in scope when this script runs standalone.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
