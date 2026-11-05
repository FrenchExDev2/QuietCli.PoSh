<p align="center">
  <img src="./../icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Git.Tests.PoSh

Module de tests compagnon séparé. Dépend de Git et des assertions de conformité du compagnon Core.

Les fixtures utilisent une identité Git dédiée, une configuration globale neutralisée et des dépôts sous `artifacts/git-fixtures`. Aucun dépôt de l’utilisateur n’est committé ou poussé. Le seul push de test vise un dépôt bare jetable local.

Les assertions vérifient l’état initial, les noms Unicode, une mutation commit exécutée une seule fois via un compteur de hook indépendant, HEAD observé, les références porcelain d’un push, le cache des sondes et la distinction entre `quiet -C contexte` et `git -C répertoire`.

Les 32 scénarios couvrent aussi les 14 familles spécialisées : patches fragmentés et combinés, bytes non UTF-8, formats demandés, historique, chemins NUL, blobs binaires et durée de vie des artefacts, listes et mutations de branches/stash/worktrees, add/checkout et fetch/pull vers des remotes locaux. Les assertions vérifient les effets indépendamment de l’objet renvoyé par le handler. Le répertoire `provenance/` conserve l’origine et la licence des fixtures adaptées ; aucun moteur tiers n’est exécuté.

L’inventaire reste explicitement non qualifié dans ces tests : ces scénarios ne certifient pas les 183 commandes, toutes leurs options ou les 17 versions.

Exécution : `./scripts/Invoke-WorkspaceCi.ps1 -Suite Git` depuis le workspace. Consulter `summary.json` et les fixtures du run pour analyser un échec ; ne pas relancer une mutation uniquement pour en lire la sortie.

## Principal-command qualification

RepositoryCommands.Tests.ps1 owns nine additional workflows: switch/restore/reset/rm/mv/clean; conflicting merge and explicit abort; cherry-pick/revert/rebase; tag list/create/delete; remote config; lossless config queries; init/clone; non-repository/native-failure boundaries; and generated PowerShell interaction guards. Never place a destructive non-repository test beneath the actual checkout: use an external temporary directory, block parent discovery with GIT_CEILING_DIRECTORIES and use a non-destructive missing-path operation.

The compiled runner now contains 22 cases. RepositoryCommandCases adds 2,000 generated config/remote cases, outcome invariants and 20,000 bounded malformed remote records with retained seeds; push retains its earlier generated/fuzz cases. The PowerShell guard has 240 generated vectors and two isolated in-memory mutants. These deterministic campaigns do not claim coverage-guided fuzzing.

Set QUIETCLI2_GIT_COMMAND_MUTATION=1 to request eight source-checked C# repository-format/outcome mutants with the shared monitored launcher. QUIETCLI2_GIT_PUSH_MUTATION=1 requests the separate eight push mutants. Ordinary development runs omit compiler-based campaigns unless needed. The reusable CI enables both in the Windows Preview x64 qualification job and retains artifacts/git-repository-mutation and artifacts/git-push-mutation. A baseline must pass, then every selected mutant must be detected; report survivors, invalid builds, timeouts and infrastructure failures separately. Mutation compilation uses the short owned staging directory documented by each receipt.

## Query parser qualification

Queries.Tests.ps1 adds five independent native workflows for twelve commands. QueryCases.cs adds six compiled cases: generated SHA-1/SHA-256 IDs/parents (seed 73051), generated index modes/stages/path boundaries (seed 73052), symbolic/peeled/raw refs, counters/alternates/rejection, versions, and 20,000 bounded malformed inputs across four parsers (seed 73053). No partial rows may survive rejection.

The compiled runner now contains 28 cases. Set QUIETCLI2_GIT_QUERY_MUTATION=1 for the eight source-checked query mutations. Parser.Mutation.ps1 is the shared runner; mutation/catalogues.json owns the separate Push, Repository and Query catalogues. The old environment selectors still work. The common CI selects Query alongside the earlier catalogues only in Windows Preview x64 qualification. A normal development run has 48 scenarios; enabling only Query produces 49. Reports are retained under artifacts/git-query-mutation and artifacts/tests/git-query-{stable,preview}-1. Timing is bounded per build/execution; survivors, invalid mutants, timeouts and infrastructure errors fail the campaign.

## Attribution qualification

Attribution.Tests.ps1 adds native blame/annotate, requested incremental-format and reflog/predicate workflows. Native read blocks use the supported minimum of 1 KiB. AttributionCases.cs adds five compiled cases with generated octal-path round trips (seed 74051), grouped metadata/content/line invariants (seed 74052), raw/uncommitted/truncated state, fixed reflog fields and 20,000 malformed inputs (seed 74053). The compiled runner now contains 33 cases.

QUIETCLI2_GIT_ATTRIBUTION_MUTATION=1 selects eight targeted attribution mutants through the shared runner. The Preview qualification ran all four catalogues after the runner refactor: 32/32 mutants detected, with no invalid builds, survivors, timeouts or infrastructure failures. Normal development has 52 scenarios; selecting only Attribution yields 53; selecting all four catalogues yields 56. These counts are scenario counts, not exhaustive Git-command qualification.

## Search/path/raw-diff qualification

PathQueries.Tests.ps1 adds seven workflows for grep modes, canonical attributes, ignore negation/nonmatches/caller stdin, mailmap, three plumbing diffs, rename path pairs and generated mode/guard properties. Native test calls preserve literal separators using an outer PowerShell -- before git. The -p regression separates display modes from actual patch selection.

PathQueryCases.cs adds six cases: generated raw fields (seed 75051), truncation/status checks, attribute and ignore properties (seed 75052), canonical contacts (seed 75053), literal NUL stdin encoding, and 20,000 malformed inputs across four parsers (seed 75054). The generated PowerShell grep-mode test uses seed 75055 and 500 cases with two isolated mutants.

The compiled runner now has 39 cases. QUIETCLI2_GIT_PATH_QUERY_MUTATION=1 selects eight source-checked PathQuery mutants. Both Windows host qualifications passed 60 scenarios with this catalogue selected. Baseline development has 59 scenarios; other compiler catalogues remain opt-in locally and required in the Preview CI qualification job. Native PTY code was unchanged and its unrelated campaign was not repeated.
