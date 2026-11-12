<p align="center">
  <img src="./../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Git.Tests.PoSh

## Owned metadata and scheduling

This companion owns its runner and complete literal `$caseMetadata` table in its own `.psm1`. Its manifest declares the RootModule, TestCatalogue runner/helper sources and TestExecution policy; shared infrastructure discovers/validates the declarations without a central Core-owned Git case list. The catalogue contains 78 cases, with 69 active by default and nine optional mutation cases. Each optional entry declares its exact EnabledWhen environment flag, statically checked against the registration guard; inactive campaigns are explicit and cannot hide an omitted active test.

MaxParallelCases is two, while the default remains Ordered: cases share mutable synthetic repositories, handler/probe state and earlier observations. Parser timing is explicitly Exclusive within this companion. No Git case opts into isolated parallel execution until its prerequisites and fixtures are independently isolated. Git and Vagrant can still run as separate suites after accepted Core; the parent divides its worker budget among suite slots. `-Case` and stop-on-first now apply to this runner as well and produce Partial/Incomplete reports. Inspect `scripts/Test-TestCaseMetadata.ps1 -Suite Git -Plan` before execution.

Separate companion test module. Depends on Git and the Core companion's conformance assertions.

See [Qualification: when, where and how](../README-qualification-when-where-how.md) for PR triggers, Windows runners, Linux containers, local commands and the distinction between building and executing tests.

Fixtures use a dedicated Git identity, disabled global configuration and repositories under `git-fixtures` in the private RunDirectory (under the shared temporary root locally). No commits or pushes are made to the user's repositories. The only test push targets a disposable local bare repository.

Assertions check the initial state, Unicode names, a commit mutation executed exactly once using an independent hook counter, the observed HEAD, porcelain push references, probe caching and the distinction between `quiet -C contexte` and `git -C répertoire`.

The 32 scenarios also cover the 14 specialized families: fragmented and combined patches, non-UTF-8 bytes, requested formats, history, NUL-delimited paths, binary blobs and artifact lifetimes, branch/stash/worktree lists and mutations, add/checkout, and fetch/pull against local remotes. Assertions verify effects independently of the object returned by the handler. The `provenance/` directory retains the origin and license of adapted fixtures; no third-party engine is executed.

The inventory remains explicitly unqualified by these tests: these scenarios do not certify all 183 commands, all their options or all 17 versions.

Run `./scripts/Invoke-WorkspaceCi.ps1 -Suite Git` from the workspace root. Inspect `summary.json` and the run's fixtures to investigate a failure; do not repeat a mutation merely to read its output.

## Principal-command qualification

RepositoryCommands.Tests.ps1 owns nine additional workflows: switch/restore/reset/rm/mv/clean; conflicting merge and explicit abort; cherry-pick/revert/rebase; tag list/create/delete; remote config; lossless config queries; init/clone; non-repository/native-failure boundaries; and generated PowerShell interaction guards. Never place a destructive non-repository test beneath the actual checkout: use an external temporary directory, block parent discovery with GIT_CEILING_DIRECTORIES and use a non-destructive missing-path operation.

The compiled runner is checked against 57 independent cases. RepositoryCommandCases adds 2,000 generated config/remote cases, outcome invariants and 20,000 bounded malformed remote records with retained seeds; push retains its earlier generated/fuzz cases. The PowerShell guard has 240 generated vectors and two isolated in-memory mutants. These deterministic campaigns do not claim coverage-guided fuzzing.

Set QUIETCLI_GIT_COMMAND_MUTATION=1 to request eight source-checked C# repository-format/outcome mutants with the shared monitored launcher. QUIETCLI_GIT_PUSH_MUTATION=1 requests the separate eight push mutants. Ordinary development runs omit compiler-based campaigns unless needed. The reusable CI enables both in the Windows Preview x64 qualification job and retains artifacts/git-repository-mutation and artifacts/git-push-mutation. A baseline must pass, then every selected mutant must be detected; report survivors, invalid builds, timeouts and infrastructure failures separately. Mutation compilation uses the short owned staging directory documented by each receipt.

## Query parser qualification

Compiler mutation catalogues run after shared repository scenarios, in isolated processes capped at two by the existing worker budget. Measurement barriers remain exclusive. Each catalogue owns a short build tree, restores packages once, resets pristine sources before every mutant and forces compilation with `--no-incremental`; subsequent builds use `--no-restore`. Every baseline still requires all 57 assertions, and every mutant still executes the complete assertion runner. Reports expose build/restore counts with separate per-mutant diagnostics. Concurrent catalogues share neither assemblies nor mutable build trees.

The shared parser mutation runner stages `global.json`, `Directory.Build.props` and
`Directory.Packages.props` above every isolated project. Baselines and mutants therefore
retain the workspace SDK selection, central package versions and warning-as-error policy.
Missing build inputs fail explicitly. A failed build reports its log path and up to three
distinct compiler/restore error lines (at most 1,200 characters) in the CI case error;
the complete diagnostic stays in the campaign's `baseline/build.log` or mutant `build.log`.

Queries.Tests.ps1 adds five independent native workflows for twelve commands. QueryCases.cs adds six compiled cases: generated SHA-1/SHA-256 IDs/parents (seed 73051), generated index modes/stages/path boundaries (seed 73052), symbolic/peeled/raw refs, counters/alternates/rejection, versions, and 20,000 bounded malformed inputs across four parsers (seed 73053). No partial rows may survive rejection.

The compiled runner now contains 28 cases. Set QUIETCLI_GIT_QUERY_MUTATION=1 for the eight source-checked query mutations. Parser.Mutation.ps1 is the shared runner; mutation/catalogues.json owns the separate Push, Repository and Query catalogues. The old environment selectors still work. The common CI selects Query alongside the earlier catalogues only in Windows Preview x64 qualification. A normal development run has 48 scenarios; enabling only Query produces 49. Reports are retained under artifacts/git-query-mutation and artifacts/tests/git-query-{stable,preview}-1. Timing is bounded per build/execution; survivors, invalid mutants, timeouts and infrastructure errors fail the campaign.

## Attribution qualification

Attribution.Tests.ps1 adds native blame/annotate, requested incremental-format and reflog/predicate workflows. Native read blocks use the supported minimum of 1 KiB. AttributionCases.cs adds five compiled cases with generated octal-path round trips (seed 74051), grouped metadata/content/line invariants (seed 74052), raw/uncommitted/truncated state, fixed reflog fields and 20,000 malformed inputs (seed 74053). The compiled runner now contains 33 cases.

QUIETCLI_GIT_ATTRIBUTION_MUTATION=1 selects eight targeted attribution mutants through the shared runner. The Preview qualification ran all four catalogues after the runner refactor: 32/32 mutants detected, with no invalid builds, survivors, timeouts or infrastructure failures. Normal development has 52 scenarios; selecting only Attribution yields 53; selecting all four catalogues yields 56. These counts are scenario counts, not exhaustive Git-command qualification.

## Search/path/raw-diff qualification

PathQueries.Tests.ps1 adds seven workflows for grep modes, canonical attributes, ignore negation/nonmatches/caller stdin, mailmap, three plumbing diffs, rename path pairs and generated mode/guard properties. Native test calls preserve literal separators using an outer PowerShell -- before git. The -p regression separates display modes from actual patch selection.

PathQueryCases.cs adds six cases: generated raw fields (seed 75051), truncation/status checks, attribute and ignore properties (seed 75052), canonical contacts (seed 75053), literal NUL stdin encoding, and 20,000 malformed inputs across four parsers (seed 75054). The generated PowerShell grep-mode test uses seed 75055 and 500 cases with two isolated mutants.

The compiled runner now has 39 cases. QUIETCLI_GIT_PATH_QUERY_MUTATION=1 selects eight source-checked PathQuery mutants. Both Windows host qualifications passed 60 scenarios with this catalogue selected. Baseline development has 59 scenarios; other compiler catalogues remain opt-in locally and required in the Preview CI qualification job. Native PTY code was unchanged and its unrelated campaign was not repeated.

## Revision parser qualification

Revisions.Tests.ps1 adds four native workflows. RevisionCases.cs adds five compiled cases: 1,000 fragmented scalar properties (seed 76051), scalar bounds/state and exact booleans, 1,000 long-description properties (seed 76052), native label/summary parsing, and 20,000 malformed inputs (seed 76053). The compiled runner has 44 cases. Baseline development has 63 scenarios; selecting only QUIETCLI_GIT_REVISION_MUTATION=1 yields 64. All six compiler mutation catalogues yield 69 scenarios and 48 mutants. Revision selects eight source-checked mutations with distinct boundary, terminator, boolean, tag, distance, revision label, undefined and count invariants. CI selects this catalogue in Preview x64; reports remain under artifacts/git-revision-mutation.

Git.Tests also owns the reference-case and private temporary-artifact security regressions formerly mixed into the Core audit. Core no longer imports Git for these assertions.
