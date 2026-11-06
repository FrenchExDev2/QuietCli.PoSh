<p align="center">
  <img src="./../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Git.PoSh

> **Status: under development (`0.2.0-preview`).** This module is the worked example of a QuietCli companion module. Its catalogue is growing, its API may change, and **the complete inventory is not qualified**. Read [Coverage and limits](#coverage-and-limits) before relying on a command.

Git business handlers for the [QuietCli](../README.md) engine. Instead of writing `-Output` and `-Complete` callbacks, you run `quiet -AsObject git <command>` and the module supplies a parser that turns Git's output into typed business data. It depends explicitly on `FrenchExDev2.QuietCli.Core.PoSh >= 0.2.0`.

## Quick start

From a source checkout, import the Core and Git manifests, then run inside an existing Git repository:

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1
Import-Module ./FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1

# Goal: observe the repository selected by -WorkingDirectory, labelled "project" in measurements.
$r = quiet -AsObject -C project -WorkingDirectory $repository git status
$r.Outcome
$r.Completeness
$r.Data

# Goal: separate the PowerShell option separator from the native one.
$r = quiet -AsObject -- git status -- 'a file'
```

QuietCli options precede `git`; Git's global options follow `git`. Business input is never sent to a probe or an observation. Parsers for machine formats require separate pipes: a PTY request that is incompatible fails explicitly before the business execution. A direct callback can still supply its own analysis of a merged terminal stream.

Importing the module registers an inert catalogue. The first invocation observes the Git binary version; later probes use a cache tied to its identity. The declared range is stable Git `>= 2.40.0 < 2.57.0`, including `.windows.N` variants. A declared range is not a qualification of every version in it.

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

The companion project [`FrenchExDev2.QuietCli.Git.Tests.PoSh`](../FrenchExDev2.QuietCli.Git.Tests.PoSh/README.md) runs functional scenarios against disposable local repositories, with compiled C# cases and targeted mutation catalogues. Counts and dates change as handlers are added, so they live in the audits and in the generated reports rather than here. A passing local campaign does not qualify other Git versions or platforms; see [Tests and qualification](../README-qualification.md).

## Third-party material

`THIRD_PARTY_NOTICES.md` and `licenses/` record the upstream material this module adapts. Official Git documentation: [git](https://git-scm.com/docs/git), [status](https://git-scm.com/docs/git-status), [commit](https://git-scm.com/docs/git-commit), [push](https://git-scm.com/docs/git-push).
