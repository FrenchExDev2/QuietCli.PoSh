<p align="center">
  <img src="./../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Git.PoSh

> **Status: under development (`0.2.0-preview`).** This module is the worked example of a QuietCli companion module. Its catalogue is growing, its API may change, and **the complete inventory is not qualified**. Read [Coverage and limits](#coverage-and-limits) before relying on a command.

Git business handlers for the [QuietCli](../README.md) engine. Instead of writing `-Output` and `-Complete` callbacks, run `quiet -AsObject git <command>` and the module supplies a parser that turns output into typed business data. The existing Gallery package is FrenchExDev2.QuietCli.Git.PoSh and its dependency is FrenchExDev2.QuietCli.Core.PoSh. Its independently versioned package is enabled in the qualified tag-publication workflow; partial inventory/command/version qualification remains explicit.

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

All paths are relative to the monorepo root. `-Restore` verifies the committed source lock; on an intentionally edited checkout, `./scripts/Initialize-Workspace.ps1` without `-Restore` refreshes the local lock. A successful build creates the compiled engine and companion binaries; it does not publish or install a Gallery package.

### Import, execute and read YAML

**Open a new PowerShell Core 7.6+ session with its normal profile**, then paste the following block. Reassigning `$checkout` makes the new session independent of variables from the build session.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
Set-Location $checkout
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Import-Module ./FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1 -ErrorAction Stop
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

## Implemented command families

The catalogue holds **58 specialized handlers** out of the 183 entries of the locked official inventory. Each runs one business execution and, for mutations, observes local state before and after. Observations are not atomic snapshots, and they do not prove the side effects of hooks or external processes.

| Family | Commands | What the handler returns |
| --- | --- | --- |
| Working tree and index | `status`, `add`, `rm`, `mv`, `restore`, `reset`, `clean`, `checkout`, `switch` | Porcelain v2 status with branch, HEAD, initial/detached state, divergence of local references, entries and counters; observed HEAD/index/worktree changes after a mutation. `clean --dry-run` keeps the requested plan records. |
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

Commands without a contract fail explicitly; there is no universal capture fallback. Private protocols, binary content and complex integrations need their own handlers. Reflog operations other than `show` and `exists` keep their requested records without a recovery claim; recursive submodule state, bisect and maintenance workflows have no handler. Per-command evidence and known gaps are in the audits: [principal commands](../docs/audits/2026-11-05-git-principal-commands.md), [queries](../docs/audits/2026-11-05-git-queries.md), [attribution](../docs/audits/2026-11-05-git-attribution.md), [path queries](../docs/audits/2026-11-05-git-path-queries.md), [revisions](../docs/audits/2026-11-05-git-revisions.md).

## Output retention

Outputs are not kept by default: each parser retains only the business values it needs. For `show` on a blob, the explicitly requested content is streamed into a local business artifact together with its size, SHA-256 and completeness. Call `Remove-QuietGitArtifact -Artifact $r.Data.Artifact` after consuming it; only an artifact owned by the current module session can be removed. This file is neither an engine capture nor SQLite data.

`ls-remote` may contact its source when you request it. No other query adds a hidden fetch or network observation.

## Tests

[Qualification: when, where and how](../README-qualification-when-where-how.md) maps Git PR triggers to actual Windows/Linux test execution, local entry points and qualification limits.

The companion project [`FrenchExDev2.QuietCli.Git.Tests.PoSh`](../FrenchExDev2.QuietCli.Git.Tests.PoSh/README.md) runs functional scenarios against disposable local repositories, with compiled C# cases and targeted mutation catalogues. Counts and dates change as handlers are added, so they live in the audits and in the generated reports rather than here. A passing local campaign does not qualify other Git versions or platforms; see [Tests and qualification](../README-qualification.md).

## Third-party material

`THIRD_PARTY_NOTICES.md` and `licenses/` record the upstream material this module adapts. Official Git documentation: [git](https://git-scm.com/docs/git), [status](https://git-scm.com/docs/git-status), [commit](https://git-scm.com/docs/git-commit), [push](https://git-scm.com/docs/git-push).
