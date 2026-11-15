# Git status: repository states, classified errors, profiles and adaptive view — 14 November 2026

This audit covers the rewrite of the `git status` handler of `FrenchExDev2.QuietCli.Git.PoSh` (output schema `git.status.v4`). It records:

- what was observed by execution;
- defects found and corrected along the way;
- the measured overhead;
- remaining gaps.

Git's source (v2.50 `setup.c`, `wt-status.c`, `builtin/commit.c`) was read as a **behavior reference only**: message wording, state-file names and detection order. No Git code was copied.

## Behavior established by execution

The cases below run from `FrenchExDev2.QuietCli.Git.Tests.PoSh/Status.Tests.ps1` against disposable local repositories, with Git 2.56.0.windows.4 on win-x64.

| Scenario | Observed answer |
| --- | --- |
| Directory outside any repository (`GIT_CEILING_DIRECTORIES`) | `Success`, `Repository.Kind=NotARepository`, `Digest.Mode=Classified`, `Counts=$null`, no business process |
| Bare repository (`--initial-branch=trunk`) | `Success`, `Kind=Bare`, `Branch=trunk` |
| Working directory inside `.git` | `Success`, `Kind=InsideGitDir` |
| Clean branch without upstream | `Clean=$true`, `Mode=Clean`, `AheadBehindComputed=$null`, `StashCount=0`, `Archetype=Small` |
| Upstream equal, ahead 1, behind 1 | exact `Ahead`/`Behind` |
| `--no-ahead-behind` while behind | `AheadBehindComputed=$false`, `Ahead`/`Behind` `$null` (native `+? -?`) |
| Remote-tracking ref deleted | `UpstreamGone=$true`, `Upstream` kept |
| Unborn branch with a staged file | `Unborn=$true`, `Mode=List` |
| Detached HEAD | `Detached=$true`, `Branch=$null`, full `HeadOid` |
| Merge conflict, then resolved | `Operations[0]=Merge`, `ReadyToCommit` false then true |
| `rebase -i` stopped on `edit` | `Rebase`, `Interactive`, `Branch=main`, `Step 1/Total 2` |
| Cherry-pick and revert conflicts | `CherryPick`, `Revert` |
| `bisect start` | `Bisect`, `From=main` |
| `am` of a non-applying patch | `Am`, `Step 1/Total 1` |
| Stash | `StashCount=1`; `--no-show-stash` gives `$null` |
| Sparse cone checkout | `Sparse.Enabled`, `Sparse.Cone` |
| Linked worktree | `LinkedWorktree=$true` |
| Dirty submodule (superproject view, inside view) | `Counts.Submodules=1`, `Submodule.TrackedChanges`; inside: `Repository.Submodule`, `Superproject` |
| `clone --depth 1` over `file://` | `Shallow=$true`, `ShallowDivergence` hint |
| `.git` file pointing to a missing directory | `Failed`, `GitBrokenGitFile:` |
| `core.repositoryformatversion=99` | `Failed`, `GitUnsupportedRepositoryFormat:` |
| 2 500 changes over 11 directories | `Mode=HotPaths`, 10 items summing to 2 500, `Changes.Class=Massive`, stable across runs |
| `-Listeners` | `GitStatusRepository`, `GitStatusSummary`, `GitStatusEntry`, in that order |

The compiled suite (`parser-tests/StatusCases.cs`, 10 new cases, 67 in total) covers what end-to-end runs cannot reproduce portably:

- the classifier table, including dubious ownership and mount-point boundaries;
- finalization of `+? -?`, gone and missing upstreams;
- submodule field decoding;
- index headers v2, v3 and v4, and truncated, bad-signature or unknown-version headers;
- pack index v1 and v2 fan-out counts, loose-name filtering for SHA-1 and SHA-256, orphan or truncated packs, alternates and loose extrapolation;
- size-class boundaries;
- the hot-path split at its exact budget boundary;
- a seeded hot-path property campaign (seed 41017, 200 rounds, random fan-out and width): coverage sum, at most K items, disjoint and ordered, independent of input order.

The `Status` mutation catalogue (`mutation/catalogues.json`, 13 mutants, `QUIETCLI_GIT_STATUS_MUTATION=1`) kills all 13 mutants. It targets:

- the classifier rules, the usage exit code and the excerpt bound;
- completeness;
- `branch.ab` and gone-upstream finalization;
- submodule decoding;
- the index signature;
- the checkout and change thresholds;
- the hot-path split rule;
- the pack index fan-out offset and the loose object name length.

On the first run, `hot-split-room` (`<= room` relaxed to `<= room + 1`) survived. The property generator placed so many root files that the frontier never reached the budget exactly. An exact-boundary case was added and the generator now draws fan-out and width per round; the mutant is killed since.

## Defects found and corrected

1. **`# branch.ab +? -?` was rejected.** The previous parser raised `MalformedBranchDivergence` when `--no-ahead-behind` was used against a diverged upstream. The parser now accepts exactly `+N -M` or `+? -?` and rejects mixed forms.
2. **A gone upstream was silent.** Git expresses it by omitting `branch.ab` when an upstream is configured. Finalization now derives `UpstreamGone`.
3. **The submodule field was ignored.** `S<C|.><M|.><U|.>` is decoded and validated character by character; `Counts.Submodules` is new.
4. **Outside a work tree, `git status` failed unclassified.** Git exits 128 there, and stderr was never read. The probe now classifies these locations before status runs.
5. **Git 2.5x wording for a broken gitfile.** The message `gitfile does not point to a valid repository` was not covered by the first classifier draft and surfaced as `GitUnclassified` during smoke testing. A rule and its path extraction were added.
6. **Excerpt bound off by one.** The truncation marker made excerpts one character longer than `MaxExcerptCharacters`. The compiled suite found it, and the marker now counts toward the bound.
7. **`--no-show-stash` was not curated.** The argument schema blocked it as `ArgumentGrammarIncomplete`. It is now declared (an `OPT_BOOL` in `builtin/commit.c`).

## Measured overhead

Median of 15 runs of `quiet -AsObject git status`, Windows 11, Git 2.56.0, warm cache. The raw column is a `quiet` invocation of `git status --porcelain=v2 -z` without the handler.

| Target | Raw | Handler, first version | Handler, final | Status process alone |
| --- | ---: | ---: | ---: | ---: |
| QuietCli checkout (22 changes, 901 index entries, 5 091 objects) | 118–128 ms | 597 ms | 322 ms | 89–95 ms |
| Synthetic repository, 2 500 untracked files | 108–114 ms | 550 ms | 408 ms | 213–231 ms |

Overhead over raw went from about 478 ms to 194 ms on the checkout, and from 441 ms to 294 ms on the synthetic repository. Each `quiet` child process costs 70–100 ms on this host, so the first version paid mostly for process count:

- `count-objects -v` alone took about 250 ms. It is replaced by an in-process read of each pack index fan-out header (1 KiB), the `.pack` sizes and the loose object names, never stat'ed. On the checkout it gives the same 5 091 objects that `count-objects` reported.
- The second `rev-parse` (work-tree root and superproject) is merged into the probe. Only bare repositories and the git directory, where `--show-toplevel` fails with `must be run in a work tree`, repeat the probe.

What remains is one probe, one `config` read, and the digest over the entries; the last dominates on the synthetic repository.

## Gaps and limits

- `HEAD detached from <ref>` (Git reads the reflog for it) is not reported.
- Hot paths are ranked by entry count, not by changed lines; `--numstat` on thousands of entries is too expensive.
- Thresholds are constants exposed in `Profile.Thresholds`; they are not yet configurable through Core configuration.
- The default text delivery budget (4 KiB) can drop `Data` on very large change sets. `-UI`, `-Listeners`, `-Projection { $args[0].Digest }` or `-AsObject` avoid it; Core has no default projection.
- `GitDubiousOwnership`, `GitCorruptIndex` and `UnreadableDirectory` are covered by authored messages only. They need ownership changes, index corruption or permission changes that are not portable in the shared fixture.
- Only win-x64 with Git 2.56.0 was executed; other Git versions in the declared range and Linux are not qualified by this run.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
