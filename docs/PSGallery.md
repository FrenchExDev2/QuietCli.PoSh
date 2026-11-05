# Installer et publier QuietCli2 sur PSGallery

Les paquets publics sont `FrenchExDev2.QuietCli.Core.PoSh` et `FrenchExDev2.QuietCli.Git.PoSh`. Les compagnons de tests ne sont pas publiés. Git déclare Core dans `RequiredModules`, et son nupkg contient la dépendance NuGet correspondante.

## Installation après publication

```powershell
# Objectif : installer QuietGit et sa dépendance Core depuis PowerShell Gallery.
Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Repository PSGallery -Version 0.1.0 -Scope CurrentUser

# Objectif : charger les handlers Git installés et observer le dépôt courant.
Import-Module FrenchExDev2.QuietCli.Git.PoSh
$result = quiet -AsObject git status
$result.Data
```

Ces commandes deviennent utilisables depuis PSGallery une fois la publication réellement effectuée. Préparer un nupkg local ne rend pas sa version disponible sur la galerie.

La version 0.1.0 des deux modules est effectivement publiée et son téléchargement public avec dépendance Core a été validé le 5 novembre 2026. `scripts/Invoke-PublishedGallery.ps1 -Version 0.1.0` reproduit ce contrôle sans installer de module globalement et avec le moniteur visible.

PowerShell Core 7.6+, Git et le **runtime .NET 11 RC `11.0.0-rc.3.26522.148`** de l’architecture courante doivent être installés séparément. Le SDK n’est pas requis pour utiliser les modules. L’installation du module ne télécharge et n’installe aucun runtime système.

Le paquet Core embarque les publications C# suivantes, chacune avec assembly, apphost et manifeste de build :

| Système / libc | x86-64 | ARM64 |
|---|---|---|
| Windows | `win-x64` | `win-arm64` |
| Linux glibc | `linux-x64` | `linux-arm64` |
| Linux musl / Alpine | `linux-musl-x64` | `linux-musl-arm64` |

La façade choisit le RID réel du processus PowerShell. Les assemblies utilisent le `PlatformTarget` correspondant ; les apphosts PE/ELF et les dépendances SQLite correspondent également à leur architecture. Les bridges PTY Linux sont statiques, construits depuis la source C livrée avec un compilateur Zig épinglé. Les licences Zig/musl sont conservées. Linux x86 32 bits et ARM32 ne sont pas inclus.

Linux démarre le DLL du RID choisi avec `dotnet` afin de fonctionner aussi quand l’installation du nupkg ne préserve pas les permissions exécutables de l’apphost. Le bridge PTY est vérifié puis copié dans un répertoire temporaire privé appartenant au moteur, avec permissions 0700 ; le module installé reste inchangé, y compris en installation système en lecture seule. Ce fichier est du code exécutable distribué, jamais une capture de sortie native.

## Préparation locale

```powershell
# Objectif : reconstruire les six moteurs et les fixtures, sans publication.
./scripts/Build-Workspace.ps1

# Objectif : tester les paquets hors des sources avec le moniteur visible.
./scripts/Invoke-WorkspaceCi.ps1 -SkipBuild

# Objectif : préparer deux nupkg installables et leur plan de publication haché.
./scripts/New-QuietGalleryPackage.ps1 -OutputDirectory ./artifacts/gallery/release-0.1.0 -Version 0.1.0

# Objectif : vérifier la livraison sans clé, sans réseau et sans publication.
./scripts/Publish-QuietGallery.ps1 -PackageDirectory ./artifacts/gallery/release-0.1.0 -Version 0.1.0 -ValidateOnly
```

`New-QuietGalleryPackage.ps1` utilise `Compress-PSResource` de PSResourceGet ; il ne renomme pas un ZIP en nupkg. Il vérifie versions, identités NuGet, dépendance Core, six moteurs, SQLite et PTY. Les sources C#, outils, fixtures et compagnons de tests ne deviennent pas des dépendances des modules métier.

Une modification de la source du bridge impose sa reconstruction explicite :

```powershell
# Objectif : reconstruire les bridges statiques avec un téléchargement vérifié dans les artefacts Windows uniquement.
./scripts/Build-PtyBridge.ps1 -DownloadCompiler
```

Sous Linux, fournir `-CompilerPath` vers la version de Zig verrouillée dans `build/zig.lock.json`. Une construction normale vérifie les bridges déjà livrés et ne télécharge pas de compilateur C.

## Workflow GitHub manuel

`.github/workflows/publish-psgallery.yml` se lance avec `workflow_dispatch`, une version explicite et le booléen `publish`. Le défaut `false` construit et valide. Seul `true` publie publiquement **Core, puis Git** sur PSGallery. Aucun push de branche, tag, build, test ou pull request ne déclenche cette publication.

Préparer :

1. Le monorepo public `FrenchExDev2/FrenchExDev2.QuietCli.PoSh`, contenant les quatre projets et le verrouillage des sources schéma 3. Un seul checkout de la révision du workflow suffit ; aucun remote enfant n’est requis.
2. Les [Dockerfiles et le cache GHCR](ci/linux-images.md) remplacent les quatre variables d’images préconfigurées. Les runners x64 et ARM64 construisent leurs images nativement. Le jeton éphémère GitHub du job Linux possède `packages: write` pour publier le premier cache depuis `main` ; aucune clé de registre personnelle n’est nécessaire.
3. Un compte PowerShell Gallery autorisé à publier les deux noms. Créer une clé API limitée aux opérations et modules nécessaires.
4. L’environnement GitHub `psgallery` et son secret **`PSGALLERY_API_KEY`**. Ils sont configurés sur le dépôt à partir du `PSGALLERY_TOKEN` fourni dans le `.env` du workspace, sans afficher sa valeur. Configurer les protections de l’environnement selon la politique du dépôt. Ne jamais placer la clé dans le code, les arguments CLI, les rapports ou le chat.

Le workflow appelle la CI commune : deux runners Windows et quatre combinaisons Linux/libc/architecture. Le RID attendu est contrôlé jusqu’à l’invité et au moteur. Une image ARM absente, une version non verrouillée ou un scénario en échec bloque la publication. La CI ARM doit fournir sa propre preuve d’exécution ; une compilation croisée n’est pas une qualification native.

Les premiers runs du 5 novembre 2026 ont réussi sur Windows x64/ARM64 et échoué au prérequis des quatre anciennes variables d’images Linux. Le workflow a depuis été adapté pour construire et mettre en cache ces images automatiquement ; consulter les nouveaux runs pour leurs résultats effectifs. La première version 0.1.0 a été publiée par invocation locale explicite, après les suites Windows/Alpine et les contrôles des six binaires. La validation publique avec PSResourceGet a ensuite confirmé le téléchargement de Git et de Core et leur exécution. Cette première publication n’est pas une certification des quatre jobs Linux hébergés.

Après les six jobs, le job de publication reconstruit et teste son propre payload, vérifie les deux nupkg puis lit la clé uniquement pendant l’étape explicite de publication. Aucun upload des paquets vers les artefacts GitHub n’est configuré. Les rapports de tests existants restent disponibles.

La publication locale explicite utilise le même script et lit la clé depuis l’environnement sécurisé :

```powershell
# Objectif : publier une livraison déjà validée en utilisant PSGALLERY_API_KEY fourni hors de la ligne de commande.
./scripts/Publish-QuietGallery.ps1 -PackageDirectory ./artifacts/gallery/release-0.1.0 -Version 0.1.0
```

Une version existante est refusée, sans écrasement ni répétition automatique. Le reçu `publication.json` distingue modules confirmés et module dont une requête interrompue peut avoir eu un effet inconnu. En cas de publication partielle, consulter la galerie et ce reçu avant toute action ; le script ne rejoue pas aveuglément une publication.

Le flux manuel reprend les recommandations [Microsoft sur les manifestes et dépendances](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines) et utilise [Publish-PSResource](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource). L’upload GitHub et la publication automatique sur tag ont été refusés par le contrôle automatique d’approbation ; cette implémentation conserve un déclenchement manuel explicite vers la destination PSGallery demandée.

## Revision-bound release gate

Every Gallery run calls ci.yml with suite=All. Native PTY baseline tests and the 23 targeted mutations run in all four native pty-mutation jobs (glibc/musl, x64/ARM64), alongside the Windows and Linux matrix. The qualification-gate job runs even when a dependency fails and rejects failure, cancellation, missing results or skipped required jobs. Tests cover positive and negative job-result combinations.

Only a complete success emits qualified_sha for that workflow revision. The publish job requires both a successful reusable workflow and qualified_sha == github.sha, then checks out github.sha explicitly. Each delivery is qualified again; an older green run cannot authorize another revision. Mutation reports and the qualification decision are uploaded on failure too.

These changes govern the Actions delivery path after they are committed and pushed. Making QuietCli2 qualification gate a required pull-request check is a separate repository ruleset setting; workflow YAML alone does not configure merge protection. Local standalone publishing scripts remain explicit administrative entry points.

Native qualification also requires all 35 baseline assertions (including process properties) and 20,000 coverage-guided decoder executions under ASan/UBSan. CI images contain GCC, G++, Clang and compiler-rt (Debian: libclang-rt-dev; Alpine: compiler-rt). The ordinary CI process runner has no product-engine dependency. A successful native matrix is required before the .NET matrix starts and before any Gallery publication can be authorized.

The dependency order is native source-only qualification, then the .NET Windows/Linux matrix, then the revision-bound release gate. The native phase neither loads QuietCli nor requires its compiled engine. It must also provide an independence receipt with zero product build files, zero loaded product modules and zero AI command calls, and the guest must exit with code zero.

## Prerelease packages

The current development manifests declare `ModuleVersion='0.2.0'` and `PrivateData.PSData.Prerelease='preview'`, producing **0.2.0-preview** for both modules. This is independent of the PowerShell stable/preview host. A build or test never publishes it.

Preparation, validation, manual workflow inputs and public identity checks accept the complete version, including `-preview` or `-preview1`. A request for `0.2.0` cannot validate `0.2.0-preview`. PowerShell Gallery prerelease labels use the supported alphanumeric/hyphen form; dotted SemVer 2 labels and build metadata are rejected explicitly.

PowerShell's `RequiredModules.ModuleVersion` remains numeric (`0.2.0`). Before hashing a newly compressed Git nupkg, the packager pins its NuGet dependency to **[0.2.0-preview]**. This prevents dependency resolution from selecting the older stable Core or silently substituting a different preview. Validators check both package versions and that exact dependency. Installed module directories use the numeric base version; display/package identity retains the prerelease suffix.

```powershell
# Objective: Prepare and validate the prerelease without publishing or using an API key.
./scripts/New-QuietGalleryPackage.ps1 -OutputDirectory ./artifacts/gallery-preview -Version 0.2.0-preview
./scripts/Publish-QuietGallery.ps1 -PackageDirectory ./artifacts/gallery-preview -Version 0.2.0-preview -ValidateOnly

# Objective: Install an explicitly chosen prerelease after it has actually been published.
Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Version 0.2.0-preview -Prerelease -Repository PSGallery
```

The example installation is not evidence that this prerelease is already public. The historical stable **0.1.0** publication remains unchanged. See Microsoft's [prerelease module guidance](https://learn.microsoft.com/powershell/gallery/concepts/module-prerelease-support).