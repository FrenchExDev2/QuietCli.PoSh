# Commit-Workspace.ps1

## Purpose

Creates one monorepo commit. By default it refreshes the source lock and stages all changes.
`-NoAll` instead commits only the prepared index, without refreshing the working-tree lock or
staging any file. Both modes check documentation compliance and support `-WhatIf`/`-Confirm`.
An optional, deduplicated `Co-Authored-By` trailer is supported; no push occurs.

It also warns (non-blocking) about a changed file that is binary content or larger than
`-MaxChangedFileSize` (default `500KB`), unless the path is already declared `binary` in
`.gitattributes`. This follows an incident in this repository where SQLite/tokenizer/YamlDotNet
native binaries were committed into history and had to be untracked and purged; the check reads
the pending change set via `quiet -AsObject ... git status` (the only place in this script that
imports and calls the `quiet` module itself, rather than `Invoke-CiProcess`/raw `git` - by the time
this script runs, the workspace is assumed functional, so using `quiet` here is a deliberate, live
example of the module exercising itself). Override (silence) with `-NoCommitFileSnifferWarning`.

Per the repository's own prior audit (`docs/audits/2026-11-08-ecosystem-usage-review.md`, GAP-01, lines 23-27), **no caller was found anywhere in this repository**: not in any `.github/workflows/*.yml`, not dot-sourced or invoked by any other script in `scripts/`. It appears to be intended for direct, ad hoc invocation, not as part of any automated pipeline. This is now exercised by `Test-QuietCommitWorkspace` in `FrenchExDev2.QuietCli.Core.Tests.PoSh/CommitWorkspace.Tests.ps1` (run via `Invoke-QuietCoreTests`), closing the test-coverage half of GAP-01; no `.github/workflows/*.yml` caller was added, since this script is still meant for ad hoc, not automated, invocation.

## Usage

| Parameter | Type | Mandatory | Default |
|---|---|---|---|
| `Message` | `string` | Yes | none |
| `WorkspaceRoot` | `string` | No | `Split-Path $PSScriptRoot -Parent` |
| `Repository` | `string` (`ValidateSet('Workspace')`) | No | `'Workspace'` |
| `CoAuthoredBy` | `string[]` | No | `$null` |
| `NoAll` | `switch` | No | `$false` |
| `NoScriptsReadmeCheck` | `switch` | No | `$false` |
| `NoDocsCreditsCheck` | `switch` | No | `$false` |
| `NoCreditsCheck` | `switch` | No | `$false` |
| `NoSyncChecks` | `switch` | No | `$false` |
| `NoScriptDocDriftWarning` | `switch` | No | `$false` |
| `MaxChangedFileSize` | `string` | No | `'500KB'` |
| `NoCommitFileSnifferWarning` | `switch` | No | `$false` |

```powershell
./scripts/Commit-Workspace.ps1 -Message "Add Build-Workspace DRY refactor" -CoAuthoredBy Claude

# Skip every documentation-sync gate and the script/doc drift warning, still commit:
./scripts/Commit-Workspace.ps1 -Message "Quick fix" -NoSyncChecks -NoScriptDocDriftWarning

# Preview: gates and the drift warning still run and report, nothing is refreshed/staged/committed.
./scripts/Commit-Workspace.ps1 -Message "Preview" -WhatIf

# Commit only the reviewed index, including a source lock matching those staged sources.
./scripts/Commit-Workspace.ps1 -Message "Commit selected changes" -NoAll -WhatIf
./scripts/Commit-Workspace.ps1 -Message "Commit selected changes" -NoAll

# Raise the binary/oversized-file sniffer's threshold to 2 MiB for this run only.
./scripts/Commit-Workspace.ps1 -Message "Vendor a tool" -MaxChangedFileSize 2MiB
```

`MaxChangedFileSize` accepts a bare integer (bytes), or a number with a decimal (`KB`/`MB`/`GB`/
`TB`) or binary (`KiB`/`MiB`/`GiB`/`TiB`) unit suffix - parsed by `Common.ps1`'s
`ConvertTo-QuietByteCount` (see [Common.md](Common.md)).

### Prepared-index mode

Before `-NoAll`, explicitly stage the intended source and documentation versions together with a
matching `repositories.lock.json`. `Update-WorkspaceLock.ps1` hashes the working tree: use it before
staging when that tree corresponds to the intended selection. When other changes must remain
unstaged, prepare the lock from the same selected source snapshot rather than from unrelated work.
`-NoAll` rejects a missing or stale staged lock instead of silently recomputing a lock from all files.

The script exports the index with `git checkout-index` into a unique temporary directory, checks
its repository/project source hashes and dependency lists, then runs the three documentation gates
against that snapshot. It removes the temporary directory in `finally`, including under `-WhatIf`.
Preview writes only that disposable snapshot: HEAD, the original index, working files and source
lock remain untouched. Missing staged changes, malformed/stale locks or failed gates block commit.
The drift warning considers staged paths only in this mode. No commit uses `git commit -a`.

## Dependencies

- Dot-sources `Common.ps1` for `Invoke-WorkspaceNative` and `ConvertTo-QuietByteCount` (used to
  resolve `-MaxChangedFileSize` once, at the top of the script).
- Runs three documentation-sync gates as child scripts before staging, each individually skippable
  (`-NoScriptsReadmeCheck`, `-NoDocsCreditsCheck`, `-NoCreditsCheck`, or all at once via
  `-NoSyncChecks`): `scripts/Sync-ScriptsReadme.ps1`, `scripts/Sync-DocsCredits.ps1`,
  `scripts/Sync-Credits.ps1`. Each throws on non-compliance exactly as it does standalone - skipping
  the gate here only removes this script's own check, it does not change the repository's actual
  compliance state.
- Queries `git diff --name-only HEAD` and `git ls-files --others --exclude-standard` (read-only) to
  compute the paths about to be committed, then warns (`Write-Warning`, never throws) when a changed
  script under `scripts/` has no matching change to its mirrored doc under `docs/scripts/`. Override
  (silence) with `-NoScriptDocDriftWarning`.
- Imports the `quiet` module (`FrenchExDev2.QuietCli.Core.PoSh`/`FrenchExDev2.QuietCli.Git.PoSh`,
  guarded the same way `Measure-ColdStart.ps1` does) to run the binary/oversized-file sniffer: a
  `quiet -AsObject ... git status` call enumerates pending changes, and a `git check-attr binary`
  call (also via `quiet`) checks each one against `.gitattributes` before reporting it. This is a
  deliberate, scoped exception to the rest of the script's `Invoke-CiProcess`-only pattern - by the
  time this script runs, the workspace is assumed to already be a functional repository, so using
  the product's own facade for this one check is safe and intentional. Override (silence) with
  `-NoCommitFileSnifferWarning`.
- Invokes `scripts/Update-WorkspaceLock.ps1` before staging in the default mode; `-NoAll` instead
  validates the already staged lock using `SourceIdentity.ps1` and `WorkspaceProjects.ps1`.
- The default mutating operations are `git add --all --` and `git commit -m`. `-NoAll` only
  commits the index, with additional read-only index queries and temporary index export.
- Assumes `git` is on `PATH` and `$WorkspaceRoot` is the root of a Git working tree.

## Side effects

- Runs the three documentation-sync gates, the drift-warning git queries and the binary/oversized-
  file sniffer unconditionally (unless skipped), including under `-WhatIf` - they are read-only and
  report the same way either way. The sniffer adds one read-only `git check-attr` call (via `quiet`)
  per changed, non-ignored file that is not a deletion.
- Under `-WhatIf`, or if `-Confirm` is declined: refreshes no working-tree lock, stages nothing,
  commits nothing. `-NoAll` still validates and removes its disposable index snapshot.
- Otherwise: runs `Update-WorkspaceLock.ps1`, mutating the workspace lock file; stages everything in
  the working tree with no path scoping (`git add --all --`); creates exactly one commit. Never
  pushes, per its own `.SYNOPSIS`.

## Findings

- DESIGN: `Repository` is `[ValidateSet('Workspace')]` with a single legal value. A parameter that can only ever take one value functions as documentation dressed up as a parameter — it does add a small amount of defensive "reject a request for an independent module commit" value per its own comment, but it is unusual API surface for a constant.
- RESOLVED (was DESIGN/BUG-risk): `git add --all --` stages absolutely everything in the working tree with no scoping. The script now has a `-WhatIf`/`SupportsShouldProcess` guard around the lock refresh, `git add` and `git commit`, closing the gap the repository's own prior audit flagged (GAP-01, lines 23-27, "medium severity").
- RESOLVED (was Testability): `FrenchExDev2.QuietCli.Core.Tests.PoSh/CommitWorkspace.Tests.ps1` exercises the real script in disposable repositories: default commit flow, `-WhatIf`, documentation gates and overrides, script/doc drift, the binary/oversized-file sniffer, and prepared-index behavior. It reports 25 property executions, ten fuzz inputs (`ConvertTo-QuietByteCount`'s valid/invalid cases) and eleven targeted mutations. It checks gate wiring and staged scope, rather than duplicating the three sync generators' internal rules.
- LIMITATION: the binary sniffer's content check is the standard git/diff NUL-byte heuristic (first ~8000 bytes), the same one `git diff` itself uses to decide "Binary files ... differ". It would false-positive on a legitimately UTF-16-encoded text file; this is accepted here because `AGENTS.md` already mandates UTF-8 everywhere in this repository.
- The `$knownCoAuthors` map hardcodes two agent identities (`Claude`, `Codex`) inline in the script body, even though the adjacent doc comment points to `docs/agents/README.md` as "the documented list" — so the script's actual single source of truth is this inline map, not the document it cites, and the two could silently drift apart.
- The new script/doc drift warning only compares file *paths* (did the mirrored `.md` change at all), never content - a doc touched for an unrelated reason (e.g. a credits-block refresh) silences the warning without the script's own documentation necessarily having been updated.
- **Prepared-index boundary:** `scripts/Commit-Workspace.ps1:81`'s `Assert-QuietStagedWorkspaceLock`
  checks staged sources and staged docs rather than assuming the current working tree will be
  committed. Tests preserve different staged/unstaged contents, unrelated unfinished scripts,
  Unicode/spaced paths, and the exact index under `-WhatIf` and rejected locks.
- **Mutation infrastructure:** `FrenchExDev2.QuietCli.Core.Tests.PoSh/CommitWorkspace.Tests.ps1`
  now copies the real script dependency layout for each mutant. Missing `Common.ps1` or another
  infrastructure error cannot count as an asserted behavior change; killed mutants require an
  expected independent assertion diagnostic. The prior five-mutant harness did not enforce that.
- **Coverage boundary:** prepared-index properties and four malformed staged-lock samples extend
  the existing gate tests, with eight targeted mutations. Snapshot export and final commit are
  separate Git operations; callers must keep the index stable throughout the invocation.

## Verdict

The default remains a whole-workspace checkpoint. `-NoAll` provides an exact prepared-index commit
with staged source-lock and documentation checks, preserving unrelated working changes. Tests use
disposable repositories and independent assertions for preview, scoping, lock validation, gate
wiring and the new binary/oversized-file sniffer. The drift warning remains path-based, the sniffer
never blocks a commit, and the index must remain stable during commit.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
