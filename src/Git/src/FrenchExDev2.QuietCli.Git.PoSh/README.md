<p align="center">
  <img src="../../../../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Git.PoSh

> **Status: under development (`0.2.0-preview`).** This module is the worked example of a QuietCli companion module. Its catalogue is growing, its API may change, and **the complete inventory is not qualified**. Read [Coverage and limits](#coverage-and-limits) before relying on a command.

Git business handlers for the [QuietCli](../../../../README.md) engine. Instead of writing `-Output` and `-Complete` callbacks, run `quiet -AsObject git <command>` and the module supplies a parser that turns output into typed business data. The existing Gallery package is FrenchExDev2.QuietCli.Git.PoSh and its dependency is FrenchExDev2.QuietCli.Core.PoSh. Its independently versioned package is enabled in the qualified tag-publication workflow; partial inventory/command/version qualification remains explicit.

Install a published version with `Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Repository PSGallery`, adding `-Prerelease` for previews, then `Import-Module FrenchExDev2.QuietCli.Git.PoSh`. A compatible published Core dependency must be available. Source development uses both projects from the same checkout.

## Quick start

[Checkout and build](#check-out-and-build) · [Import, execute and read YAML](#import-execute-and-read-yaml)

### Check out and build

Use PowerShell Core 7.6+, Git and the exact .NET SDK pinned in `global.json` (currently `11.0.100`). Build before importing the local modules. Close sessions that already loaded this checkout's assemblies before rebuilding.

The commands start in a parent directory of your choice and clone the whole monorepo into `$HOME/src/QuietCli`. For an existing checkout, set `$checkout` to its root and skip the clone. Git performs this initial bootstrap before local `quiet` is available; the build script uses the engine-independent process helper.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
New-Item -ItemType Directory -Path (Split-Path $checkout -Parent) -Force | Out-Null
git clone --branch develop https://github.com/FrenchExDev2/QuietCli.PoSh.git $checkout
if ($LASTEXITCODE -ne 0) { throw 'CheckoutFailed' }
Set-Location $checkout
./scripts/Initialize-Workspace.ps1 -Restore
./scripts/Build-Workspace.ps1
```

All paths are relative to the monorepo root. `Initialize-Workspace.ps1` validates projects discovered from their manifests; `-Restore` also restores and verifies pinned external Core resources. Git identifies committed internal sources, while build/test artifacts retain actual source and binary identities. Internal edits require no committed source-lock refresh. A successful build creates the compiled engine and companion binaries; it does not publish or install a Gallery package.

### Import, execute and read YAML

**Open a new PowerShell Core 7.6+ session with its normal profile**, then paste the following block. Reassigning `$checkout` makes the new session independent of variables from the build session.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
Set-Location $checkout
Import-Module ./Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Import-Module ./Git/src/FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1 -ErrorAction Stop
Get-Alias quiet

# The checkout is itself an existing Git repository.
$repository = $checkout
$statusView = {
    param($data, $budget)
    [pscustomobject]@{
        Branch = $data.Branch
        Staged = $data.Counts.Staged
        Unstaged = $data.Counts.Unstaged
        Untracked = $data.Counts.Untracked
    }
}
$r = quiet -AsObject -C project -WorkingDirectory $repository -Projection $statusView git status
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteGitStatus'
}
Out-QuietResult $r -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

Illustrative YAML excerpt for a clean checkout of `develop`; invocation IDs and other envelope metadata are omitted. Branch and counters reflect your repository's actual state.

```yaml
"Outcome": "Success"
"Context": "project"
"Data":
  "Branch": "develop"
  "Staged": 0
  "Unstaged": 0
  "Untracked": 0
"Completeness":
  "Source": true
  "Analysis": true
```

The registered `git status` handler is the execution contract: it parses porcelain v2 into the complete local object in `$r.Data`. `$statusView` selects the four business fields delivered as YAML. `-AsObject` keeps the object local; `Out-QuietResult -AsYaml` formats that same result without rerunning Git.

To demonstrate both option separators against the real `README.md` path, in the same initialized session:

```powershell
$fileStatus = quiet -AsObject -C readme-only -WorkingDirectory $repository -Projection $statusView -- git status -- README.md
if ($fileStatus.Outcome -ne 'Success' -or !$fileStatus.Completeness.Source -or !$fileStatus.Completeness.Analysis -or $fileStatus.Error.Count) { throw 'IncompleteGitStatus' }
Out-QuietResult $fileStatus -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

For a clean checkout, the excerpt is:

```yaml
"Outcome": "Success"
"Context": "readme-only"
"Data":
  "Branch": "develop"
  "Staged": 0
  "Unstaged": 0
  "Untracked": 0
```

This second contract scopes observation to `README.md`; a modification to that file changes its counters. QuietCli options precede `git`; Git's global options follow it. Business input is never sent to a probe or an observation. Machine-format parsers require separate pipes; incompatible PTY requests fail before business execution.

Import registers an inert catalogue. The first invocation observes the Git binary version; later probes use an identity-bound cache. The declared range is stable Git `>= 2.40.0 < 2.57.0`, including `.windows.N` variants. A declared range is not qualification of every version.

## `git status`: repository states, profiles and adaptive view

`git status` (output schema `git.status.v4`) first classifies where it runs, then observes, then decides what is worth showing. `$r.Data` always stays complete (every entry); only the presentation adapts.

**Repository kind.** One `rev-parse` probe sets `Data.Repository.Kind`:

| Kind | Outcome | What you get |
| --- | --- | --- |
| `NotARepository` | `Success` | Classified answer; `SearchBoundary` when discovery stopped at a mount point. Status is not run, `Counts` is `$null`. |
| `Bare` | `Success` | Classified answer with the HEAD branch (`Data.Branch`). |
| `InsideGitDir` | `Success` | Classified answer (the working directory is inside `.git`). |
| `WorkTree` | `Success` | Full porcelain v2 observation plus the facts below. |

Flags on `Data.Repository`: `LinkedWorktree`, `Submodule`/`Superproject`, `Shallow`, `PartialClone`, `Sparse{Enabled,Cone,SparseIndex}`, `ObjectFormat`, `RefFormat`.

**Branch and tracking.** `Branch`, `HeadOid`, `Unborn`, `Detached`, `Upstream`, `Ahead`/`Behind`, `AheadBehindComputed` (`$false` with `--no-ahead-behind`), `UpstreamGone` (configured upstream whose remote-tracking ref no longer exists) and `StashCount` (`--show-stash` is on by default; `--no-show-stash` gives `$null`).

**In-progress operations.** Porcelain v2 does not print them, so the handler reads Git's state files the way `git status` long format does. `Data.Operations` is a list, since operations can coexist (for example bisect during a rebase): `Merge` (`ReadyToCommit` once conflicts are resolved), `Rebase`/`RebaseApply` (`Interactive`, `Branch`, `Onto`, `Step`/`Total`), `Am`, `CherryPick`, `Revert`, `Sequence` and `Bisect` (`From`).

**Errors.** A real failure stays `Failed`. Its message starts with a stable code: `GitDubiousOwnership` (with a `safe.directory` hint), `GitBrokenGitFile`, `GitBareRepositoryForbidden`, `GitUnsupportedRepositoryFormat`, `GitCorruptIndex`, `GitPathspecOutsideRepository`, `GitInvalidArgument`, `GitUnclassified`. A `warning: could not open directory` on a successful run becomes an `UnreadableDirectory` diagnostic and sets `AnswerComplete` to `$false`.

**Profile.** These measurements are cheap and never walk history: the index header gives the checkout size; the pack index fan-out headers (1 KiB per pack) and the loose object names give the history size, read in process like `count-objects -v` (alternates excluded); one `config` read gives the relevant settings. `Data.Profile` holds:

- `Checkout.Class` (index entries): Small < 1 000 ≤ Medium < 20 000 ≤ Large < 200 000 ≤ Huge;
- `History.Class` (objects): Small < 10 000 ≤ Medium < 500 000 ≤ Large < 5 000 000 ≤ Huge;
- `Changes.Class`: Clean, Few ≤ 20, Many ≤ 1 000, Massive;
- `Archetype`: `Small`, `DeepHistory` (large history, small checkout), `WideCheckout` (large checkout, small history, for example a vendored tree or a shallow CI clone), `Monorepo` or `Standard`;
- `Objects`: `Loose`, `Packed`, `Packs`, `PackBytes`, `Alternates`, and `Approximate` (set when more than 200 000 loose names were extrapolated or a pack index was unreadable);
- `Hints`: fsmonitor or untracked cache off on a large checkout, a status slower than 2 s with `-uall`, a shallow clone with an upstream.

The thresholds are returned in `Profile.Thresholds`.

**Adaptive view (`Data.Digest`).**

| Mode | When | Content |
| --- | --- | --- |
| `Classified` | not a work tree | the repository kind only |
| `Clean` | no change | branch, tracking, stash, operations |
| `List` | ≤ 20 changes | every entry, conflicts first, then tracked changes, then untracked files |
| `HotPaths` | > 20 changes | the **10 hottest paths** plus conflicts (up to 50), and `Omitted` |

Hot paths are disjoint directories, files or a `Rest` remainder, and together they cover every change: on a monorepo with 2 000 changes you get the ten subtrees that concentrate them, each with its staged/unstaged/untracked/conflicted split and share. A `Rest` item folds the smaller children of a directory that could not be split within the budget (`Groups` tells how many).

**Presentation.** The handler publishes the view without changing Core:

- `-Listeners` receives `QuietCli2.Event` objects whose `Type` is `GitStatusRepository`, `GitStatusOperation`, `GitStatusSummary`, `GitStatusHotPath` or `GitStatusEntry`, then `GitStatusDiagnostic`; business fields are under `Data` (for example `$event.Data.Counts` for a summary);
- `-UI` draws a three-line header (repository, branch, profile) and one lane per operation, hot path or entry.

```powershell
quiet -UI git status                                          # live view
quiet -AsObject -Projection { $args[0].Digest } git status    # compact delivered result
```

Known limit: on a very large change set, the default text delivery budget (4 KiB) can still drop `Data`. Use `-UI`, `-Listeners` or `-Projection { $args[0].Digest }`, or keep the object local with `-AsObject`.

The worktree case costs two extra short Git processes (one probe that also asks for the work-tree root, and one `config` read), plus two `rev-parse --verify` under the reftable backend. Bare repositories and the git directory repeat the probe once, because `--show-toplevel` fails there. On Windows this measured about 195 ms over a raw `git status`. Measurements are in the [status audit](../../../../docs/audits/2026-11-14-git-status-states-profiles.md).

## Implemented command families

The catalogue holds **58 specialized handlers** out of the 183 entries of the locked official inventory. Each runs one business execution and, for mutations, observes local state before and after. Observations are not atomic snapshots, and they do not prove the side effects of hooks or external processes.

| Family | Commands | What the handler returns |
| --- | --- | --- |
| Working tree and index | `status`, `add`, `rm`, `mv`, `restore`, `reset`, `clean`, `checkout`, `switch` | Porcelain v2 status with branch, HEAD, initial/detached state, divergence of local references, entries and counters, plus repository kind, in-progress operations, profile and hot-path digest ([above](#git-status-repository-states-profiles-and-adaptive-view)); observed HEAD/index/worktree changes after a mutation. `clean --dry-run` keeps the requested plan records. |
| History and objects | `commit`, `log`, `show`, `diff`, `tag`, `describe`, `name-rev`, `shortlog`, `blame`, `annotate`, `reflog` | Full identities, parents, author, committer, subject and body with no hidden commit cap; files, hunks and combined patches with end-of-line markers preserved; line-porcelain attribution; observed ref changes. |
| Integration | `merge`, `rebase`, `cherry-pick`, `revert`, `fetch`, `pull`, `push` | One native operation with local before/after state and ref changes. A non-zero exit is a failure; unmerged entries are reported as `FailedWithConflicts`. No automatic resolution, abort, continue or retry. |
| Branches and remotes | `branch`, `stash`, `worktree`, `remote`, `config`, `init`, `clone` | Structured lists and mutations observed before and after; NUL-delimited config records that keep duplicate, multiline and valueless settings. |
| Queries and plumbing | `ls-files`, `ls-tree`, `for-each-ref`, `show-ref`, `ls-remote`, `rev-parse`, `rev-list`, `merge-base`, `hash-object`, `write-tree`, `count-objects`, `symbolic-ref`, `check-ref-format`, `check-attr`, `check-ignore`, `check-mailmap`, `grep`, `version` | NUL-framed records, validated full object identities, quiet predicates, bounded scalars. |
| Index and raw diffs | `update-index`, `read-tree`, `checkout-index`, `diff-files`, `diff-index`, `diff-tree` | Mode/object/stage/path tuples observed before and after; raw diff records with lossless paths. |

Explicit alternative output formats generally stay *requested-format* records: the handler preserves the native text instead of pretending it parsed it. Some forms are refused before execution (for example alternate `read-tree` index-output destinations); native Git validates the options it receives.

## Coverage and limits

`metadata/Git.Inventory.json` lists the 183 entries of the locked official inventory with their versions; upstream sources and hashes are under `metadata/locks`. The pure argument grammar preserves option arity and separators but does not establish semantic validity.

`Get-QuietGitCoverage` separates **inventory**, **implementation** and **qualification**:

| Dimension | Current state |
| --- | --- |
| Inventory | 183 entries declared |
| Implementation | 58 `StreamingBusinessHandler` entries; 125 `PartialOrMissing` |
| Qualification | `Pending` for all 183 entries; `EntireInventoryQualified` is `False` |

Commands without a contract fail explicitly; there is no universal capture fallback. Private protocols, binary content and complex integrations need their own handlers. Reflog operations other than `show` and `exists` keep their requested records without a recovery claim; recursive submodule state, bisect and maintenance workflows have no handler. Per-command evidence and known gaps are in the audits: [principal commands](../../../../docs/audits/2026-11-05-git-principal-commands.md), [queries](../../../../docs/audits/2026-11-05-git-queries.md), [attribution](../../../../docs/audits/2026-11-05-git-attribution.md), [path queries](../../../../docs/audits/2026-11-05-git-path-queries.md), [revisions](../../../../docs/audits/2026-11-05-git-revisions.md).

## Output retention

Outputs are not kept by default: each parser retains only the business values it needs. For `show` on a blob, the explicitly requested content is streamed into a local business artifact together with its size, SHA-256 and completeness. Call `Remove-QuietGitArtifact -Artifact $r.Data.Artifact` after consuming it; only an artifact owned by the current module session can be removed. This file is neither an engine capture nor SQLite data.

`ls-remote` may contact its source when you request it. No other query adds a hidden fetch or network observation.

## Tests

[Qualification: when, where and how](../../../../readmes/README-qualification-when-where-how.md) maps Git PR triggers to actual Windows/Linux test execution, local entry points and qualification limits.

The companion project [`FrenchExDev2.QuietCli.Git.Tests.PoSh`](../../test/FrenchExDev2.QuietCli.Git.Tests.PoSh/README.md) runs functional scenarios against disposable local repositories, with compiled C# cases and targeted mutation catalogues. Counts and dates change as handlers are added, so they live in the audits and in the generated reports rather than here. A passing local campaign does not qualify other Git versions or platforms; see [Tests and qualification](../../../../readmes/README-qualification.md).

## Third-party material

`THIRD_PARTY_NOTICES.md` and `licenses/` record the upstream material this module adapts. Official Git documentation: [git](https://git-scm.com/docs/git), [status](https://git-scm.com/docs/git-status), [commit](https://git-scm.com/docs/git-commit), [push](https://git-scm.com/docs/git-push).
