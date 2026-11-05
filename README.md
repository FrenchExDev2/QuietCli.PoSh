<p align="center">
  <img src="./icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# QuietCli2 — monorepo multi-projets

Moteur C# **.NET 10 / .NET 11 RC**, façade **PowerShell Core 7.6+**, analyse en flux destinée en premier lieu aux IA.

The current development release is **0.2.0-preview**, declared by numeric `ModuleVersion='0.2.0'` and `PSData.Prerelease='preview'` in Core and Git. It is not published by a build or test. The previously published stable 0.1.0 remains a separate historical release. Gallery packaging preserves the suffix and pins Git's package dependency to the exact matching Core preview; PowerShell's manifest dependency remains numeric.

The same engine now also targets **.NET 10** for direct hosting in PowerShell 7.6. Set `$env:QUIETCLI2_ENGINE_MODE='InProcess'` before the first call (or call `Stop-QuietEngine` before changing modes). This removes the engine subprocess and pipe IPC. Native blocks, fixed read metadata and input/lifecycle controls cross direct C# method boundaries without JSON. Startup and telemetry also use closed local metadata operations in integrated mode. Internal raw queries and rejected-request diagnostics retain bounded JSON; SQLite keeps its validated JSON storage representation. `Auto` is the default: the actual CLR selects the integrated net10.0 build on .NET 10 or net11.0 build on .NET 11 and later. Set `Process` explicitly for the isolated .NET 11 host. Git byte-record framing runs in a verified caller-local compatible assembly in either mode. See [performance and hosting](docs/performance-and-hosting.md) for measured scope, reproduction and limitations.

A second pass moves incremental UTF-8 text framing and measurement aggregation to C#. Text framing stays caller-local in both hosting modes, and gain reports transfer aggregate groups instead of original SQLite events. See [PowerShell/C# boundaries](docs/powershell-csharp-boundaries.md) for the remaining candidates and measurement scope.

Le [dépôt public unique](https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh) contient quatre projets : Core, Core.Tests, Git et Git.Tests. Ouvrir `QuietCli2.code-workspace` dans VS Code pour les parcourir. Source Control utilise le seul dépôt racine ; il n’y a ni dépôt Git enfant ni sous-module. Les deux modules métier restent publiés séparément sur PSGallery.

## État réel

Le moteur, SQLite, le protocole binaire, les bytecounts, les callbacks imbriqués et les transports pipe/PTY sont implémentés. Les modules compagnons exécutent des assertions indépendantes.

**Git complet n’est pas encore livré.** L’inventaire officiel verrouillé contient 183 entrées pour les versions 2.40 à 2.56. Fifty-five command families now have specialized handlers, including init/clone, switch/restore/reset, rm/mv/clean, merge/rebase/cherry-pick/revert and tag/remote/config. Common workflows are covered; advanced forms and the full version/platform matrix remain explicitly unqualified. Les familles restantes et toutes les variantes de ces commandes ne sont pas qualifiées. `Get-QuietGitCoverage` conserve explicitement cette distinction. Une énumération de l’inventaire n’est pas une preuve de support.

Les workflows Core et Git sont filtrés par chemins et appellent la CI commune. Core déclenche aussi les tests Git ; Git peut être validé seul. Le workflow de publication PSGallery est manuel et revalide tous les projets et plateformes. Les révisions réellement exécutées figurent dans les rapports.

QuietGit lance directement le binaire Git. Le projet consulté comme référence n’est ni exécuté ni chargé : seuls les documents de provenance et de licence en conservent l’attribution. Aucun identifiant exécutable n’en reprend le nom.

## Démarrage dans VS Code

Les modules disposent d’une [installation et publication PSGallery](docs/PSGallery.md). Le workflow manuel publie Core puis Git après la CI ; les paquets embarquent les moteurs Windows/Linux x64 et ARM64, pour glibc et musl. La disponibilité publiée et les preuves d’installation sont indiquées ci-dessous.

Les versions **0.1.0 sont publiées** : [Core](https://www.powershellgallery.com/packages/FrenchExDev2.QuietCli.Core.PoSh/0.1.0), [Git](https://www.powershellgallery.com/packages/FrenchExDev2.QuietCli.Git.PoSh/0.1.0). Le téléchargement depuis PSGallery, la résolution de la dépendance Core et l’exécution des modules téléchargés ont été vérifiés dans une installation temporaire isolée.

La validation locale initiale du monorepo comporte 63 scénarios réussis sur Windows x64 et Alpine x64. Les jobs GitHub Windows x64 **et Windows ARM64** ont également réussi dans [le run du 5 novembre](https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh/actions/runs/41943788968). La CI Linux prépare désormais ses images avec les Dockerfiles multiétapes du dépôt, sur des runners natifs x64 et ARM64. Le premier run sur `main` publie les images manquantes dans GHCR ; les runs suivants réutilisent leur digest tant que les entrées verrouillées restent identiques. Les résultats de cette nouvelle chaîne sont distincts des preuves antérieures. Voir [le cache et les images CI](docs/ci/linux-images.md).

```powershell
# Objectif : installer QuietGit et Core depuis la galerie publique.
Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Version 0.1.0 -Repository PSGallery -Scope CurrentUser
```

Dans le terminal PowerShell du dossier **Workspace** :

```powershell
# Objectif : construire l’exécutable et les outils de tests avec le SDK épinglé.
./scripts/Build-Workspace.ps1

# Objectif : rendre les quatre modules locaux découvrables dans cette session uniquement.
$root = (Get-Location).Path
$env:PSModulePath = $root + [IO.Path]::PathSeparator + $env:PSModulePath
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1
Import-Module ./FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1

# Objectif : observer le dépôt choisi sans sérialiser l’objet métier.
$r = quiet -AsObject -C travail -WorkingDirectory $repository git status
$r.Data

# Objectif : produire une seule livraison JSON bornée puis consulter les mesures.
$json = $r | ConvertTo-QuietJson
Get-QuietCliGain -C travail
```

Définir `$repository` explicitement. Charger V1 et V2 dans des sessions séparées : leurs noms de fonctions publics se recouvrent. Aucun profil n’est modifié par ces scripts.

Le moteur démarre à la première invocation. Le SDK est `11.0.100-rc.3.26522.148`, le runtime `11.0.0-rc.3.26522.148`. Le runtime RC est requis pour le mode isolé ; le mode intégré utilise le runtime compatible de PowerShell. Le SDK est requis uniquement pour construire. Le mode isolé utilise ce runtime épinglé ; le mode intégré automatique utilise le runtime réel de PowerShell (.NET 10 ou .NET 11+).

## Flux et objets

Les blocs stdout/stderr sont comptés, transmis à `-Output`, puis libérés. Aucune capture brute, copie cumulative ou écriture temporaire des sorties n’est créée automatiquement. Les queues natives sont bornées à 16 blocs de 16 Kio par invocation. Un cadrage par délimiteur conserve uniquement le fragment inachevé, borné par `MaxRecordBytes`.

`-AsObject` ne parcourt pas `Data`, ne la sérialise pas et ne l’envoie pas au moteur. Il retourne l’enveloppe locale contenant l’objet métier. Les mesures ne consultent que les métadonnées et les compteurs. Un handler peut conserver explicitement des données nécessaires à son besoin métier.

```powershell
# Objectif : compter des bytes métier sans conserver le contenu des événements.
$r = quiet -AsObject -StdoutMode Bytes -Data @{ Count = 0L } -Output {
    param($event, $runtime)
    if ($event.Stream -eq 'stdout') { $runtime.Data.Count += $event.ByteCount }
} executable arguments
```

Les options QuietCli précèdent le binaire. Pour un séparateur natif littéral, fournir également le séparateur initial PowerShell : `quiet -AsObject -- git status -- 'un fichier'`. L’API structurée `-FilePath git -ArgumentList @('status','--','un fichier')` évite cette particularité PowerShell. `quiet -C contexte git -C /repo status` distingue le contexte de mesure et le répertoire Git.

`-Output` reçoit `(event, runtime)` et ne doit rien émettre. Utiliser `[void]` pour les méthodes qui retournent une valeur. `-Complete` reçoit le runtime et retourne au plus une valeur métier ; utiliser la virgule unaire pour retourner un tableau. Sans valeur retournée, `Data` est conservée. Après un échec d’analyse, le moteur continue de drainer ; `Complete` est appelé une fois et peut finaliser des données partielles.

Un enfant appelé depuis un callback hérite du contexte et retourne un objet par défaut. Son échec reste visible même si son résultat est affecté à une variable.

Le timeout arrête le processus natif détenu, pas un callback PowerShell arbitrairement bloqué. Les callbacks doivent coopérer. Aucune opération n’est rejouée automatiquement ; une rupture de communication peut laisser l’effet d’une mutation inconnu.

## Mesures

L’enveloppe conserve les compteurs stdin effectivement écrit, stdout/stderr effectivement lus et, en PTY, le flux terminal fusionné. Les compteurs stdout/stderr séparés sont inconnus en PTY.

Les rôles `Business`, `Probe`, `Observation` et `Infrastructure` séparent les volumes. Une sonde ne gonfle jamais le gain métier. Les totaux dédupliquent les sources ; les sous-totaux de contextes ne sont pas nécessairement additifs.

Avec `-AsObject`, taille de livraison et réduction restent inconnues. JSON/YAML sont mesurés uniquement lorsqu’ils sont réellement produits. Une projection ne provoque aucune sérialisation supplémentaire des données omises. Le dernier texte livré est conservé localement sous son `DeliveryId` ; les anciennes chaînes ne s’accumulent pas dans le résultat.

Le tokenizer est désactivé par défaut. `-Tokenizer o200k_base` ou `cl100k_base` compte exactement le texte livré déjà produit. Les tokens natifs restent inconnus : ni conservation des flux ni addition des tokens de blocs.

SQLite contient uniquement des métadonnées, compteurs, relations et erreurs structurées. Aucun objet métier, texte livré, environnement complet ou contenu natif n’y est enregistré. `QUIETCLI2_DATABASE` change son emplacement ; `QUIETCLI2_TRACKING=0` désactive l’écriture des mesures. Aucune configuration de contexte préalable n’est requise.

## Tests, CI et distribution

```powershell
# Objectif : exécuter les suites dans un worker avec fenêtre de suivi visible.
./scripts/Invoke-WorkspaceCi.ps1

# Objectif : utiliser une image Alpine locale déjà préparée, sans pull ni réseau invité.
./scripts/Invoke-ContainerCi.ps1 -Platform alpine -Image $image

# Objectif : construire quatre archives séparées, sans publication.
./scripts/New-WorkspacePackage.ps1 -OutputDirectory ./artifacts/package-001
```

Les rapports sont sous `artifacts/tests` et `artifacts/containers`. Le lanceur affiche la commande permettant de rouvrir le moniteur. Celui-ci ne lit que les fichiers du run et se ferme après sauvegarde d’un état terminal. `-Headless` est réservé aux environnements CI sans bureau.

La matrice Windows comprend aussi [`windows-11-arm` / `win-arm64`](docs/ci/windows-arm64.md), avec les mêmes suites et un contrôle de l’architecture de PowerShell et du moteur. Le module embarque les publications C# `win-x64` et `win-arm64`, avec apphosts natifs et manifestes vérifiés. La façade choisit celle du RID courant. Le job ARM est préparé ; son exécution distante reste à établir. Les versions d’image et identités réellement observées sont conservées dans les rapports, sans assimiler une exécution x64 émulée à une qualification ARM.

Les archives sont vérifiées sans import par défaut : `Test-WorkspacePackage.ps1` contrôle l’ensemble des quatre modules, les chemins, tailles et empreintes avant extraction. Ajouter `-TestImport` uniquement pour exécuter explicitement les modules ainsi contrôlés. `Verified=true` établit la cohérence des fichiers et manifestes ; `Authenticated=false` rappelle que cette vérification n’authentifie pas leur auteur.

La preuve locale du 4 novembre 2026 comporte 59 assertions réussies sous Windows, Debian/glibc et Alpine/musl : 27 pour le moteur et 32 pour Git. Les suites incluent les sept assertions C# du protocole/SQLite, les distributions extraites hors des sources, les flux de 64 Mio, les interactions PTY, le générateur et les durées du moniteur en cultures française et anglaise. Ces runs valident les scénarios exécutés avec les binaires présents ; ils ne certifient pas les 17 versions Git ni Dockur. Les échantillons de performance distinguent démarrage, callbacks et IPC ; leur durée native inclut le drainage et la contre-pression.

Après les correctifs de l’audit, la preuve du 5 novembre passe à **62 scénarios réussis par plateforme** (30 Core, 32 Git), avec 12 assertions C# internes et 18 contrôles de sécurité sous Windows, 19 sous Unix. Les détails et limites — construction du snapshot Debian, nettoyage Podman, exécution ARM distante — sont consignés dans le [bilan de correction](docs/audits/2026-11-04-remediation.md). Cette preuve précède l’ajout des distributions Linux par architecture et du workflow PSGallery ; leurs propres résultats sont à lire dans les nouveaux rapports de run.

`ci.yml` utilise Windows et les images Debian/Alpine configurées par `QUIETCLI2_DEBIAN_IMAGE` et `QUIETCLI2_ALPINE_IMAGE`. Elles doivent fournir PowerShell 7.6+, Git, .NET 11 RC et les dépendances nécessaires. La qualification complète nécessite le runner dédié Podman/KVM, les 17 versions verrouillées et une base Dockur préparée. Des scénarios absents font échouer la qualification ; ils ne deviennent pas des succès ignorés.

## Organisation Git et workflows

`Initialize-Workspace.ps1` vérifie le checkout unique et les quatre projets. `-Restore` contrôle le verrouillage des sources ; il ne clone plus de dépôt enfant. Le checkout GitHub Actions détermine la révision du monorepo.

`Commit-Workspace.ps1 -Message <texte>` et `Push-Workspace.ps1` agissent sur le seul monorepo. Les opérations de build/test ne committent et ne poussent jamais. Les anciennes métadonnées Git enfants sont conservées sous `artifacts/monorepo-migration`.

`Update-WorkspaceLock.ps1` recalcule les identités des quatre projets et du dépôt. Son schéma 3 décrit les dépendances des projets, pas des remotes enfants. Les [instructions monorepo](AGENTS.md) détaillent les filtres `paths`, les suites, les dépendances et la publication. `Invoke-RemoteWorkflow.ps1` déclenche un workflow uniquement avec dépôt et ref explicites, ou consulte ses états avec `-Status`.

## Documentation et maintenance

L’[audit sécurité et conception du 4 novembre 2026](docs/audits/2026-11-04-securite-logiciel.md) conserve les constats initiaux. Le [suivi des correctifs](docs/audits/2026-11-04-remediation.md) relie chaque constat à son changement et à ses critères de vérification. Les régressions bloquantes sont dans le compagnon Core.Tests et ne modifient aucune base utilisateur.

Les quatre modules possèdent leur README. Les scripts/fonctions PowerShell disposent d’une aide ; les signatures C# possèdent des commentaires XML. L’outil de maintenance de documentation sous le module compagnon s’exécute dans un processus .NET séparé et n’intervient jamais pendant un import, un build normal ou un test.

`New-QuietModule -Name Entreprise.QuietOutil.PoSh -Binary outil -OutputPath $destination` génère le module, son catalogue inerte et `src/Handler.ps1`, ainsi que le compagnon de tests. Les callbacks de sonde, politique de version, sélection et analyse sont à compléter à partir de la documentation du binaire. Le compagnon dépend du module métier et des assertions Core ; sa suite initiale échoue explicitement tant que les assertions métier ne sont pas écrites.

The principal-command implementation, validation and known limits are recorded in [the command audit](docs/audits/2026-11-05-git-principal-commands.md).

Local test reports default to `%TEMP%/QuietCli2/<workspace-id>/` (the system temporary directory on other platforms). Companion tests, container reports, Gallery validation and mutation reports use separate categories. The launcher prints the exact run/monitor path. An explicit `-RunDirectory` takes precedence. CI retains workspace `artifacts/` paths for upload contracts. Temporary storage can be cleared by the operating system; export evidence needed for durable retention.
