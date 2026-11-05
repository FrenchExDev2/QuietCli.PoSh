# FrenchExDev2.QuietCli.Git.Tests.PoSh

Module de tests compagnon séparé. Dépend de Git et des assertions de conformité du compagnon Core.

Les fixtures utilisent une identité Git dédiée, une configuration globale neutralisée et des dépôts sous `artifacts/git-fixtures`. Aucun dépôt de l’utilisateur n’est committé ou poussé. Le seul push de test vise un dépôt bare jetable local.

Les assertions vérifient l’état initial, les noms Unicode, une mutation commit exécutée une seule fois via un compteur de hook indépendant, HEAD observé, les références porcelain d’un push, le cache des sondes et la distinction entre `quiet -C contexte` et `git -C répertoire`.

Les 32 scénarios couvrent aussi les 14 familles spécialisées : patches fragmentés et combinés, bytes non UTF-8, formats demandés, historique, chemins NUL, blobs binaires et durée de vie des artefacts, listes et mutations de branches/stash/worktrees, add/checkout et fetch/pull vers des remotes locaux. Les assertions vérifient les effets indépendamment de l’objet renvoyé par le handler. Le répertoire `provenance/` conserve l’origine et la licence des fixtures adaptées ; aucun moteur tiers n’est exécuté.

L’inventaire reste explicitement non qualifié dans ces tests : ces scénarios ne certifient pas les 183 commandes, toutes leurs options ou les 17 versions.

Exécution : `./scripts/Invoke-WorkspaceCi.ps1 -Suite Git` depuis le workspace. Consulter `summary.json` et les fixtures du run pour analyser un échec ; ne pas relancer une mutation uniquement pour en lire la sortie.
