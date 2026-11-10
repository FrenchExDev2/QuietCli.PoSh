# Software ecosystem factory — roadmap corrigée et sous-plans

Date : 10 novembre 2026. Statut : base de conception proposée, corrigée à partir du plan Claude et des demandes utilisateur. Aucun comportement produit n’est implémenté ou qualifié par ces documents.

## 1. Objectif et décisions applicables

Livrer d'abord **C:/code/FrenchExDev/FrenchExDev_i3 comme environnement de travail équipé de SoftwareEcosystem.Manager**, permettant de gérer plusieurs instances locales d'écosystèmes, dont le développement du Manager lui-même. La [roadmap de livraison i3](ROADMAP-Delivery-FrenchExDev-i3.md) fixe le contenu matériel et huit scénarios de recette. Le dossier seul ne suffit pas.

La **software ecosystem factory** réutilisable fournit les capacités de génération, adoption, mise à jour, hébergement, tests et observabilité. Son périmètre complet dépasse le premier environnement utilisable : les domaines .NET, IEC, messaging et les évolutions Core sont des extensions selon besoin. Core reste un consommateur spécialisé. Cette passe formalise et valide le planning ; elle n'installe pas le Manager.

Cette roadmap est le plan directeur corrigé. Le [challenge daté](ROADMAP-Factory-Review.md) explique les écarts du plan Claude ; les sous-plans ci-dessous portent les décisions corrigées et leurs critères. Les anciennes sections du plan source ne constituent pas des décisions concurrentes.

1. **Un écosystème, un dépôt et sa politique de livraison.** Plusieurs projets internes et paquets sont permis ; aucun .git enfant ni CPM partagé entre écosystèmes. SDK/outillage, manifests, editorconfig/gitignore, workflows, secrets par référence et cycles de publication sont possédés localement.
2. **Des artefacts entre écosystèmes.** .NET via .nupkg + CPM consommateur et sources déclarées ; modules PS via dépôt PSResource ; npm via manifeste/lock/registry propre. Aucun source link voisin, import de CPM parent ou DLL de bin sœur. Herméticité des versions/configurations ne promet pas un build universellement hors réseau.
3. **Identités distinctes.** Dépôt GitHub, projets internes, modules/paquets, namespaces, instance et chemin ne sont pas déduits les uns des autres. Un dépôt .Ecosystem ne publie pas automatiquement un paquet du même nom. Le paquet public actuel reste **QuietCli**, même si le projet source s’appelle FrenchExDev2.QuietCli.Core.PoSh.
4. **Placement configurable, non limité aux langages.** Une racine d’hébergement peut classer par langage, logiciel, intérêt ou dépôt direct. PoSh, Net, NodeJs, Rust, VsCode, Wsl et LLVM sont des catégories existantes à inventorier, pas un enum universel de langages.
5. **i3 comme recette, migration par décisions.** FrenchExDev_i3 est la cible demandée de cette livraison ; le produit conserve des racines configurables. FrenchExDev_i2 est préservé et peut être inventorié/enregistré explicitement. Un fork/clone upstream ne devient pas FrenchExDev2 par son emplacement.
6. **Fonctions/cmdlets d’abord, façades présentes.** Chaque opération réutilisable porte le métier, validation, lifecycle et ShouldProcess. Les .ps1 délèguent ; code consommateur appelle les fonctions directement. Générer aide, docs de commande, docs/scripts miroir/index, tests et instructions consommateurs ensemble.
7. **RaC obligatoire, moteur interchangeable.** Chaque capacité, y compris hôte/scripts/docs/obs/bootstrap, possède besoin, AC, liens design/impl/test/obs, tests prévus puis preuves. Les checklists sont des vues ; la DSL .NET n’est pas imposée aux autres langages.
8. **Dogfooding vérifiable.** La factory version N produit une candidate N+1 avec les mêmes interfaces publiques, à partir d’artefacts identifiés. Un oracle indépendant du templating doit pouvoir rejeter un défaut que le générateur aurait recopié dans ses tests.
9. **Opérations et autorisations séparées.** Préparer des fichiers ne crée ni remote, ni secret, ni publication. New/Show/Invoke plan, WhatIf et effets bornés ont des contrats explicites ; pas de retry/compensation automatique d’un effet externe inconnu.

## 2. Responsabilités et bootstrap sans cycle

| Propriétaire | Responsabilité | Dépendances runtime autorisées |
| --- | --- | --- |
| Generator G0 | Modèle de plan, génération minimale, kit interne unique | Aucun QuietCli, IEC, GP ou registry manager source |
| WorkspaceHost HOST0 | Workspace/instance/facettes/placement/config et fonctions d’hôte | Contrats neutres ; pas de Generator ou SM runtime requis |
| GitProject GP | Git mono-dépôt : init/clone/fetch/commit/push/checks | Outils Git et contrats de checks ; reçoit un Path déjà résolu |
| Generator G2 | Compose profils et opérations de HOST/GP packagés | HOST/GP → jamais de dépendance retour vers G |
| Manager SM0 puis SM1 | Gestion locale multi-instance puis catalogue distant optionnel | HOST et GP packagés ; pas de Generator runtime requis en SM0 |
| Registry R | Registres/config/restauration par instance | Fournisseurs compatibles et profils choisis |
| Domaines | FSM, IEC, Bundle, Core et leurs adaptateurs | Fermeture de paquets explicite ; aucun checkout voisin |

Les structures de GP/HOST/R peuvent être générées par G sans que leur runtime dépende de G. HOST ne dépend pas de Manager pour savoir où placer une instance ; Manager consomme HOST. GP ne connaît pas le moteur de contenu G et ne résout pas une taxonomie de workspace. Le pipeline de checks est indépendant de QuietCli ; ses adaptateurs spécifiques restent dans leurs domaines.

G0 conserve seulement le minimum nécessaire à sa première livraison. Les extractions de kit/profils se font ensuite en artefacts épinglés, jamais en latest implicite. Aucun nouveau dépôt de contrats n’est imposé sans besoin démontré ; si une extraction est nécessaire, vérifier le graphe avant de la réaliser.

## 3. Hébergement des instances et scripts du workspace

Un **workspace** possède racines autorisées, configuration locale, catalogue d’instances et tooling. Une **instance** possède repositoryId, instanceId, emplacement canonique et état. Ses facettes (langages, logiciels, intérêts, provenance) sont multivaluées. Une vue requirements et une vue LLVM peuvent désigner la même instance ; elles ne créent pas deux clones.

Exemples de profils, pas chemins obligatoires :

| Profil | Organisation illustrative |
| --- | --- |
| Language | <root>/PoSh/<org>/<repo>/<instance> |
| Software | <root>/VsCode/<org>/<repo>/<instance> |
| Interest | <root>/requirements/<org>/<repo>/<instance> |
| DirectRepository | <root>/LLVM/llvm-project ou chemin existant explicitement enregistré |
| CustomTemplate | Tokens de placement autorisés avec validation de containment/collisions |

Le patron i{0} peut rester un défaut pour de nouvelles instances ; un clone existant sans ce segment reste adoptable. Une branche feature n’est pas à elle seule une dérive. develop est le défaut proposé des nouveaux dépôts, pas un renommage ou une correction des existants.

Chaque hôte peut fournir **<root>/scripts/** et **<root>/docs/scripts/**. Pour ce workspace, cela vise notamment C:/code/FrenchExDev/FrenchExDev_i2/scripts. Les quatre scripts actuellement observés (Invoke-ArtifactsCleanup, Invoke-PSMutationCampaign, Sync-AgentsRepo, Watch-PSMutationCampaign) sont des entrées à évaluer/adopter, pas une preuve de conformité ou une liste à écraser. Leurs fonctions propriétaires et versions seront déterminées par l’inventaire.

Les façades proposées de l’hôte incluent Initialize-Workspace, Get-Instances, New-InstancePlan, Test-WorkspaceSanity et New-MigrationPlan ; elles consomment les fonctions versionnées de HOST/SM/MIG. Le workspace n’acquiert pas pour autant un CPM, un secret ou une release commune à ses produits hébergés.

## 4. Fabrique d’opérations, façades et instructions

Le [sous-plan Generator](ROADMAP-SoftwareEcosystem-Generator.md) reprend les dix générateurs de façades : New-Ecosystem, New-Operation, New-CommandFacade, New-CheckFacade, New-TaskFacade, New-WorkerFacade, New-MonitorFacade, New-ConsumerInstructions, Update-Facades et Test-Facades.

Chaque générateur est une commande réutilisable et possède sa façade .ps1, aide/docs/scripts et tests. Les spécialisations partagent la même fabrique ; elles apportent un contrat de check/task/worker/monitor, pas une copie du templating. Les commandes et profils restent proposés, pas installables aujourd’hui.

```powershell
# Proposed authoring flow: preview file changes, never run the generated operation.
$operation = New-EcosystemOperationPlan -EcosystemPath $root -ModuleName 'Acme.Tools' -CommandName 'New-AcmePackage' -Implementation PowerShellFunction
Invoke-EcosystemPlan -Plan $operation -WhatIf

$facade = New-EcosystemScriptPlan -EcosystemPath $root -Name 'Pack-Workspace' -Template 'PowerShell.CommandFacade' -CommandModule 'Acme.Tools' -CommandName 'New-AcmePackage'
Invoke-EcosystemPlan -Plan $facade -WhatIf
```

Les signatures, mappings, versions, valeurs par défaut et sorties sont explicitement déclarés ; un changement incompatible est détecté. Les façades ne dupliquent pas ShouldProcess et ne polluent pas le pipeline. Les opérations nouvelles non remplies sont Draft et échouent explicitement.

AGENTS généré contient règles de conception/réutilisation, usage des commandes versus scripts, frontières de dépendance, ressources possédées, nettoyage, tests/moniteurs, confidentialité et compatibilité. Les instructions consommateurs décrivent installation publique, import/appel direct et façade optionnelle ; elles sont séparées des règles de développement et ne remplacent pas automatiquement un AGENTS existant.

## 5. Sous-plans et exigences initiales

Le [registre RaC](requirements/software-ecosystem-factory.requirements.json) contient les exigences et workItems identifiés, Proposed/Planned et sans preuves produit exécutées. Le [modèle de contrats](requirements/software-ecosystem-factory.roadmaps.json) définit les livrables par fiche et les graphes proposés ; leurs comptes sont calculés par `scripts/Invoke-RoadmapContract.ps1`. Le [contrat commun](ROADMAP-Requirements-As-Code.md) définit roadmaps, kinds, liens, états et gates. Les propriétaires restent Unassigned : PlanConsistent ne vaut pas ImplementationReady.

| Famille | Sous-plan et résultat attendu |
| --- | --- |
| I3 | [ROADMAP-Delivery-FrenchExDev-i3.md](ROADMAP-Delivery-FrenchExDev-i3.md) — Installer explicitement les paquets retenus et accepter l'environnement Manager local avec deux instances et auto-gestion contrôlée. |
| FAC | [ROADMAP-Requirements-As-Code.md](ROADMAP-Requirements-As-Code.md) — Traçabilité commune obligatoire |
| GEN | [ROADMAP-SoftwareEcosystem-Generator.md](ROADMAP-SoftwareEcosystem-Generator.md) — Produire, adopter et mettre à jour un écosystème autonome à partir de capacités composables ; être son propre premier consommateur. |
| GP | [ROADMAP-GitProject.md](ROADMAP-GitProject.md) — Réutiliser création, validation, identité source, commit et push sans fusionner les dépôts ou confondre leurs identités. |
| SM | [ROADMAP-SoftwareEcosystem-Manager.md](ROADMAP-SoftwareEcosystem-Manager.md) — Découvrir et gérer plusieurs instances d’écosystèmes sans modifier silencieusement le travail local. |
| REG | [ROADMAP-Local-NuGet-Registry.md](ROADMAP-Local-NuGet-Registry.md) — Publier et restaurer des .nupkg identifiés, sans accès source voisin et sans configuration globale implicite. |
| ADP | [ROADMAP-Socle-Adoption.md](ROADMAP-Socle-Adoption.md) — Valider les abstractions communes sur deux domaines réels sans effacer leurs contrats propres. |
| FND | [ROADMAP-Shared-Foundations.md](ROADMAP-Shared-Foundations.md) — Planifier une seule reprise de chaque fondation requise au lieu de la cacher dans les consommateurs. |
| FSM | [ROADMAP-FiniteStateMachine.md](ROADMAP-FiniteStateMachine.md) — Préserver les comportements Dynamic/Typed/Rich et les générateurs en consommation packagée. |
| IEC | [ROADMAP-IEC61499.md](ROADMAP-IEC61499.md) — Faire converger exécution dynamique et génération C# sur un modèle neutre, avec contrats événement/données vérifiables. |
| CON | [ROADMAP-Conduit.md](ROADMAP-Conduit.md) — Traduire des événements entre domaines sans recréer leur routage, moteur ou scheduler. |
| MSG | [ROADMAP-Messaging-DockerCompose.md](ROADMAP-Messaging-DockerCompose.md) — Réutiliser le Bundle typé avec contributeurs RabbitMQ/NATS et façade PowerShell compatible. |
| EXT | [ROADMAP-Bundle-Extensions.md](ROADMAP-Bundle-Extensions.md) — Préparer deux reprises distinctes à partir des capacités communes validées, sans imposer un pattern par analogie. |
| DOG | [ROADMAP-Factory-Dogfooding.md](ROADMAP-Factory-Dogfooding.md) — Faire exercer à la factory ses propres capacités sur son cycle complet, avec des preuves indépendantes de ce qu’elle génère. |
| CORE | [ROADMAP-Core-Pipelines.md](ROADMAP-Core-Pipelines.md) — Conserver la roadmap Core détaillée et la rattacher à des exigences vérifiables. |
| HOST | [ROADMAP-SoftwareEcosystem-WorkspaceHost.md](ROADMAP-SoftwareEcosystem-WorkspaceHost.md) — Gérer une ou plusieurs racines de travail, leurs outils scripts/fonctions et les instances d’écosystèmes, sans imposer une hiérarchie par langage. |
| MIG | [ROADMAP-Migration-FrenchExDev2.md](ROADMAP-Migration-FrenchExDev2.md) — Produire un plan de migration contrôlé de l’existant PoSh/Net et des autres catégories du workspace, fondé sur l’inventaire et les dépendances réelles. |

Chaque sous-plan a objectif/frontières/dépendances, décision de patterns à affiner, design/impl/test/obs, exigences avec AC dans le registre, démo d’usage, preuves attendues et décisions ouvertes. Les preuves absentes ne sont jamais marquées réussies. Le [challenge de complétude](ROADMAP-Factory-Review.md) conserve l’analyse de la version Claude antérieure.

## 6. Migration FrenchExDev vers FrenchExDev2

Le [sous-plan MIG](ROADMAP-Migration-FrenchExDev2.md) inventorie d’abord les sources existantes :

- PoSh/FrenchExDev et Net/FrenchExDev : modules, bibliothèques, générateurs, companions et dépôts autonomes.
- NodeJs, Rust : produits/labs/forks et dépendances propres ; ne pas imposer un profil npm à Rust.
- VsCode, Wsl : extensions, configurations et scripts selon leur nature réelle.
- LLVM : clones upstream et laboratoires, provenance et identité conservées.
- scripts du workspace : fonctions propriétaires, façades, docs et lifecycle de l’hôte.

Livrer un inventaire structuré, un graphe de dépendances et une décision par item avant toute migration. Les choix Keep/Register, AdoptInPlace, CloneAsNewInstance, ExtractProjects, RenamePublicIdentity ou Deprecate ont des préconditions propres. Source locale dirty/ignorée et secrets exigent un traitement explicite ; pas de déplacement, suppression ou remplacement global FrenchExDev→FrenchExDev2.

Les vagues suivent les producteurs puis consommateurs réels. Une nouvelle identité publique exige mapping de package/module/namespace, installation depuis artefacts, qualification des consommateurs, coexistence et retour prévu. Un cutover n’autorise pas automatiquement le retrait de l’original.

## 7. Domaines et corrections de contrats

- **R** : feed filesystem initial, config NuGet complète explicitement choisie par instance ; immutabilité ID/version/hash, atomicité/concurrence et caches de qualification isolés. PSResource/npm distincts.
- **Fondations** : Result, Builder et adaptateurs Requirements ont chacun leur fermeture de dépendances à vérifier ; ne pas supposer que FSM requiert Builder. Les générateurs doivent fonctionner depuis les paquets, sans nouvel émetteur Builder parallèle.
- **FSM** : préserver Dynamic/Typed/Rich et le défaut réel ConcurrencyMode.None ; choisir Semaphore explicitement pour la démo qui le demande.
- **IEC** : modèle neutre sans QuietCli/Roslyn/PowerShell, runtime et génération équivalents, ordre événement/données défini, algorithmes extensibles. EI(A=2,B=3), Gain=2 → Sum=10 puis EO. Pas de conformité IEC présumée.
- **Conduit** : unique adaptateur entre IEC et QuietCli ; producteurs fixtures avant vm.ready. Pas de faux binaire iec61499, moteur ou scheduler parallèle.
- **M** : un Bundle typé Compose réutilisé par PS ; conserver Services/Volumes/Networks/File avec adaptateur testé. Profil dev avec ports explicitement loopback, schémas/images identifiés, config/up/handshake/down distincts. Infra optionnelle pour le runtime.
- **Packer/Vagrant** : plans distincts, mécanismes partagés sans modèle imposé. Les parseurs Vagrant packagés ne doivent pas contourner le lanceur QuietCli ou lancer une deuxième fois la CLI.
- **Core** : conserver [tous les contrats détaillés](ROADMAP-Core-Pipelines.md) : événements hors résultats, exécuteur hérité, middleware explicite, routage explicable sans probe, runspace, drainage, queues bornées, politique des listeners, InProcess/externe, redelivery/effet inconnu, santé persistante et arrêt propre.

Les profils de publication sont **par cible**. NuGet.org Trusted Publishing ne démontre pas un support Gallery équivalent ; MSG-004 exige une capacité fournisseur prouvée. Les politiques existantes ne sont pas remplacées implicitement. Aucun conteneur Running ne prouve un broker Ready ou une VM Healthy.

## 8. Séquencement corrigé et gates

1. **B0 + FAC** : préflight du poste, fermeture des archives d'amorçage, exigences et contrôle du planning. Pas de serveur de registre ou nouveau Manager pour amorcer leurs propres producteurs.
2. **G0 + DOG0** : kit minimal, plan/preview/apply et témoin à oracle indépendant.
3. **HOST0 et GP0** : paquets de gestion locale du catalogue/placement et des opérations mono-dépôt, sans dépendance retour. **MIG0** inventorie en parallèle les seules entrées i2 nécessaires à la première livraison.
4. **SM0 puis I3** : Manager local hors réseau ; installation versionnée à la cible demandée ; huit scénarios de recette, auto-gestion candidate N+1 et retour vers N. G1/G2, registry .NET et domaines métier ne bloquent pas ce minimum.
5. **G1/G2, REG et SM1** : générateurs complets, profils d'orchestration, parcours NuGet et découverte distante optionnelle. Les canaux PSResource/npm sont qualifiés séparément.
6. **ADP, FND et MIG1** : témoins QuietCli/GitHub, fondations réellement requises et vagues sélectionnées avec leurs prérequis ; aucune migration globale obligatoire.
7. **FSM puis IEC ; MSG et EXT** selon leur fermeture réelle. **CORE** progresse indépendamment de SM0 ; Conduit commence par fixture puis intègre les contrats CORE nécessaires à sa concurrence. InProcess ne dépend jamais de MSG.
8. **DOG1** : étendre la qualification N→N+1 aux profils, distribution, pannes et consommateurs déclarés. Le feedback de conception porte sur une révision suivante et n'introduit pas de cycle bloquant dans celle en cours.

DOG et RaC ne sont pas repoussés à la fin ; la dernière étape étend une vérification présente dès G0. Toutes les branches de ce séquencement n’ont pas à attendre un ordre linéaire artificiel.

**PlanConsistent** exige structure/AC/kinds/livrables/décisions de patterns et graphes proposés cohérents. **ImplementationReady**, par lot, exige propriétaire nommé, contrats figés, versions/fermeture résolues, budgets des campagnes et retour. **I3Accepted** exige la recette locale sur les artefacts exacts. **ReleaseReady** exige la matrice promise complète, avec property/fuzz/mutation selon scope/langage, états terminaux sauvegardés et moniteur visible en local. Aucune date de fin n'est inventée avant connaissance des contrats et de la capacité de réalisation.

## 9. Livrables présents et limites

Cette passe livre le planning, des contrats de livraison par roadmap, le registre RaC, les graphes proposés et un contrôleur documentaire avec ses tests. Les fonctions produit, migrations, registres, workflows et packages restent à réaliser dans leurs lots. i3 n'est pas provisionné. Les résultats du contrôleur portent exclusivement sur le planning et son tooling.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**MASTER** — portfolio — Pilotage de la livraison i3 et des extensions.

Ordonner des résultats utilisateurs, décisions et gates ; la cible de recette est i3 équipé du Manager local.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Carte des capacités, frontières et dépendances typées du portefeuille |
| impl | Manifeste de lots et liens vers les livrables possédés par chaque roadmap |
| test | Contrôle des références, de la couverture des roadmaps et du graphe proposé |
| obs | Vue des gates, décisions ouvertes, preuves manquantes et blocages par lot |

Traçabilité : FAC-011, FAC-001, FAC-002, FAC-003, FAC-004, FAC-005, FAC-006, FAC-007, FAC-008, FAC-009, FAC-010. Lots : I3, DOG1. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| FAC-011 | Chaque roadmap définit résultat utilisateur, livrables par kind, dépendances typées, décision de patterns et gates distinctes. | FAC-011-AC1 → FAC-011-T1 (contract, NotRun) |
| FAC-001 | Tout écosystème possède ses propres versions, configuration et release, sans dépendance source externe. | FAC-001-AC1 → FAC-001-T1 (integration, NotRun) |
| FAC-002 | Toute capacité est liée à un besoin, un AC, un plan par kind, un test et une preuve. | FAC-002-AC1 → FAC-002-T1 (contract, NotRun) |
| FAC-003 | Les quatre kinds design, impl, test et obs sont explicites et indépendants. | FAC-003-AC1 → FAC-003-T1 (contract, NotRun) |
| FAC-004 | Chaque opération définit succès, refus, erreur, annulation, timeout et nettoyage possédé. | FAC-004-AC1 → FAC-004-T1 (fault, NotRun) |
| FAC-005 | Toute façade et commande disposent de docs et instructions consommateurs cohérentes. | FAC-005-AC1 → FAC-005-T1 (contract, NotRun) |
| FAC-006 | Les profils sont versionnés, composables et mis à jour explicitement. | FAC-006-AC1 → FAC-006-T1 (fuzz, NotRun) |
| FAC-007 | Une release publie exactement les artefacts qualifiés avec autorisation et cible explicites. | FAC-007-AC1 → FAC-007-T1 (integration, NotRun) |
| FAC-008 | Les choix de patterns sont justifiés et relient forces, conséquences et vérifications. | FAC-008-AC1 → FAC-008-T1 (review, NotRun) |
| FAC-009 | Les preuves de test respectent scope, moniteur, stockage et confidentialité. | FAC-009-AC1 → FAC-009-T1 (integration, NotRun) |
| FAC-010 | La configuration est résolue explicitement et protège les frontières de portée. | FAC-010-AC1 → FAC-010-T1 (property, NotRun) |

**Décision de patterns : Dependency-oriented portfolio / rolling-wave planning.**

Contexte : Plusieurs produits autonomes doivent contribuer à un poste utilisable.

Problème : Une liste linéaire de technologies masque le chemin critique.

Forces : Valeur utilisateur, dépendances partielles et capacité de réalisation inconnue.

Participants : Plan directeur priorise ; sous-plans possèdent contrats et implémentations.

Collaboration : Les producteurs livrent des artefacts avant le passage de gate des consommateurs.

Conséquences : Les extensions ne bloquent pas le minimum i3 ; les estimations restent révisables.

Alternative : Big-bang de tous les domaines rejeté : il retarde le premier usage local.

Oracle indépendant : I3 n'a aucun ancêtre FSM, IEC, MSG, EXT ou CORE dans le graphe de livraison.

**SOLID / DRY / MODULAR :** SRP par capacité ; DRY des exigences dans le registre ; modules versionnés entre écosystèmes, sans dépôt parent commun.

Entrée : Demande de livraison et périmètre explicités.

Sortie : Chaque lot a un propriétaire avant exécution, des prérequis identifiés et une gate fondée sur ses preuves.

Risque : Un graphe proposé n'est pas l'inventaire vérifié des dépendances futures.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
