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
2. Quatre références d’images immuables contenant PowerShell 7.6+, .NET 11 RC et Git : `QUIETCLI2_DEBIAN_IMAGE`, `QUIETCLI2_ALPINE_IMAGE`, `QUIETCLI2_DEBIAN_ARM64_IMAGE`, `QUIETCLI2_ALPINE_ARM64_IMAGE`, toutes sous la forme `image@sha256:...`.
3. Un compte PowerShell Gallery autorisé à publier les deux noms. Créer une clé API limitée aux opérations et modules nécessaires.
4. L’environnement GitHub `psgallery` et son secret **`PSGALLERY_API_KEY`**. Ils sont configurés sur le dépôt à partir du `PSGALLERY_TOKEN` fourni dans le `.env` du workspace, sans afficher sa valeur. Configurer les protections de l’environnement selon la politique du dépôt. Ne jamais placer la clé dans le code, les arguments CLI, les rapports ou le chat.

Le workflow appelle la CI commune : deux runners Windows et quatre combinaisons Linux/libc/architecture. Le RID attendu est contrôlé jusqu’à l’invité et au moteur. Une image ARM absente, une version non verrouillée ou un scénario en échec bloque la publication. La CI ARM doit fournir sa propre preuve d’exécution ; une compilation croisée n’est pas une qualification native.

Après les six jobs, le job de publication reconstruit et teste son propre payload, vérifie les deux nupkg puis lit la clé uniquement pendant l’étape explicite de publication. Aucun upload des paquets vers les artefacts GitHub n’est configuré. Les rapports de tests existants restent disponibles.

La publication locale explicite utilise le même script et lit la clé depuis l’environnement sécurisé :

```powershell
# Objectif : publier une livraison déjà validée en utilisant PSGALLERY_API_KEY fourni hors de la ligne de commande.
./scripts/Publish-QuietGallery.ps1 -PackageDirectory ./artifacts/gallery/release-0.1.0 -Version 0.1.0
```

Une version existante est refusée, sans écrasement ni répétition automatique. Le reçu `publication.json` distingue modules confirmés et module dont une requête interrompue peut avoir eu un effet inconnu. En cas de publication partielle, consulter la galerie et ce reçu avant toute action ; le script ne rejoue pas aveuglément une publication.

Le flux manuel reprend les recommandations [Microsoft sur les manifestes et dépendances](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines) et utilise [Publish-PSResource](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource). L’upload GitHub et la publication automatique sur tag ont été refusés par le contrôle automatique d’approbation ; cette implémentation conserve un déclenchement manuel explicite vers la destination PSGallery demandée.
