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
