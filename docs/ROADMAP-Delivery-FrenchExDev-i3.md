# Livraison — FrenchExDev_i3 comme environnement du Manager local

Date : 10 novembre 2026. Statut : cible de livraison demandée, produit non implémenté. Cette passe porte sur le planning ; elle ne provisionne pas i3.

## Résultat utilisateur et frontière

Livrer **C:/code/FrenchExDev/FrenchExDev_i3**, environnement de travail équipé d'une installation versionnée de **SoftwareEcosystem.Manager**, capable de gérer plusieurs instances locales d'écosystèmes. Un dossier vide ou une copie de i2 ne satisfait pas ce résultat. Le workspace est l'hôte ; l'installation du Manager est un déploiement identifié ; son checkout de développement est une instance d'écosystème enregistrée. Ces trois identités restent distinctes.

Le chemin est la cible de cette livraison, même si le produit permet de configurer d'autres racines. i2 reste une source d'inventaire et de paquets préparés, sans modification par le Manager de i3 tant qu'une opération distincte ne le demande. L'inspection du 10 novembre a trouvé i3 déjà présent et vide ; ce constat ne prouve aucune installation.

La définition d'une roadmap, les kinds et les gates sont dans le [contrat commun](ROADMAP-Requirements-As-Code.md). Le [modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json) est la source des blocs de livraison générés ; les [exigences](requirements/software-ecosystem-factory.requirements.json) restent la source des AC. Les noms de modules et de commandes ci-dessous sont des contrats proposés, pas des paquets publiés.

## Contenu matériel attendu

```text
C:/code/FrenchExDev/FrenchExDev_i3/
  .softwareecosystem/
    workspace.json             # Workspace identity, allowed roots and policy references.
    instances.json             # Local instance catalogue, including Manager development.
    manager.deployment.json    # Installed version and candidate/active deployment identity.
    packages.lock.json         # Exact artifacts, dependencies, hashes and sources.
    operations/                # Durable receipts for explicitly applied local operations.
  tools/modules/               # Installed immutable module versions, separate from sources.
  scripts/                     # Thin documented entry points to installed commands.
  docs/scripts/                # Mirrored entry-point documentation and index.
  ecosystems/                 # Independent ecosystem repositories; configurable placement.
  AGENTS.md                    # Host scope, commands, ownership and validation policy.
```

Ce schéma n'est pas un manifeste déjà installé. Chaque dépôt sous ecosystems possède son propre Git, ses versions, ses paquets et sa politique CI. **Aucun dépôt Git englobant i3**, aucun .git enfant à l'intérieur d'un écosystème. Les caches et rapports locaux éphémères restent dans le répertoire temporaire système, séparés des reçus durables de gestion. Les credentials restent des références.

## Parcours minimal, puis extensions

| Lot | Livrable et dépendances | Sortie observable |
| --- | --- | --- |
| B0 | Préflight du poste et fermeture des artefacts d'amorçage | PowerShell Core 7.6+, Git et commandes disponibles ; versions réellement résolues et paquets identifiés ; aucun install automatique |
| FAC | Contrat RaC et règles de roadmapping | PlanConsistent sépare structure valide, décisions ouvertes et qualification produit |
| G0 | Kit minimal de génération, puis DOG0 | Plan/preview/apply local ; témoin vérifié par un oracle indépendant |
| HOST0 + GP0 | Modèle d'hôte et opérations Git locales | Catalogue local/placements ; init/clone local/fetch séparés ; refus des collisions et données dirty protégées |
| MIG0 | Inventaire des éléments réellement sélectionnés de i2 | Registre évalué avec provenance et décision par item ; inventaire global extensible sans migration globale préalable |
| SM0 | Manager local consommant HOST0 et GP0 packagés | Enregistrer, lister, inspecter, préparer et appliquer une opération d'instance ; aucun réseau requis |
| I3 | Installer les artefacts sélectionnés et exercer les scénarios ci-dessous | Session fraîche, deux instances isolées et auto-gestion N→candidate N+1 ; reprise contrôlée et preuves |
| Après I3 | GEN avancé, REG NuGet, ADP, FND, FSM, IEC, CORE, CON, MSG, EXT, MIG par vagues, DOG complet | Qualification séparée de chaque capacité ; aucune ne devient prérequis implicite de SM0 |

La découverte GitHub et la synchronisation distante sont une extension SM, pas une condition de lecture du catalogue local. Le déploiement B0 utilise des archives de modules vérifiées et un répertoire privé versionné ; il ne dépend pas d'un nouveau serveur de paquets. NuGet, PSResource et npm restent des canaux distincts. Leur support n'est pas déduit de celui d'un autre fournisseur.

Le Manager minimal est PowerShell-first ; un SDK .NET n'est requis que pour un composant sélectionné qui le déclare. Le bootstrap des outils actuels QuietCli utilise leurs binaires compatibles existants et leur runtime déclaré. Le build du futur Manager ne doit pas appeler ce même Manager non encore construit pour se rendre disponible. Les versions précises de futurs paquets restent à résoudre avant ImplementationReady ; aucun `latest` ou faux verrou ne les remplace.

## Scénarios d'acceptation de l'environnement

Les Given/When/Then canoniques sont I3-001 à I3-008 dans le registre. Chaque scénario doit produire son résultat, sa révision/configuration/toolchain et des empreintes des artefacts testés.

1. Partir d'une session PowerShell fraîche avec profil normal et config explicitement choisie : charger le Manager depuis tools/modules, afficher sa version et sa fermeture de dépendances sans source sœur ni chargement implicite depuis i2.
2. Enregistrer deux instances locales jetables d'un même repositoryId avec des instanceId et chemins différents, plus le checkout Manager. Une deuxième inscription identique ne crée aucun doublon ; une collision échoue sans mutation.
3. Lister et inspecter ces instances hors réseau. L'indisponibilité distante reste Unknown ; l'état local reste consultable. Ni identité ni placement ne découlent d'une branche ou du nom du dossier.
4. Préparer la création d'une instance depuis un dépôt local possédé ; WhatIf ne crée rien. À l'application, revérifier les préconditions et restituer Created/Refused/Failed/Unknown avec un reçu, sans écraser une destination occupée.
5. Avec un fichier humain modifié et deux opérations concurrentes, refuser l'opération conflictuelle ; une interruption ne provoque ni reset/clean ni répétition automatique d'un effet inconnu. La reprise exige un diagnostic explicite.
6. Réinstaller depuis les mêmes artefacts dans une racine temporaire isolée, sources i2 inaccessibles et cache vide. Obtenir le même catalogue sémantique et des chemins adaptés ; la comparaison exclut horodatages et identifiants de run documentés.
7. Développer une candidate Manager N+1 sans écraser la version N active. N prépare la candidate à partir d'artefacts figés ; une vérification indépendante décide de son éligibilité. La candidate ne s'active pas pendant ses propres tests. Retour local vers N vérifié, avec compatibilité du catalogue et des reçus.
8. Fournir les façades et docs miroir, instructions d'hôte, aide, diagnostic de santé et commande de réouverture des rapports. Chaque campagne locale possède son moniteur visible, ses bornes et son état terminal enregistré.

L'expérience attendue est « je gère mes instances locales depuis i3 ». Une CLI simulée, des fichiers de configuration seuls ou des tests déclarés ne constituent pas la recette. L'implémentation pourra proposer Get-SoftwareEcosystemInstance, Register-SoftwareEcosystemInstance et New/Invoke-SoftwareEcosystemInstancePlan ; leurs noms définitifs et paramètres sont une décision de design SM/HOST.

## Cycles et auto-gestion sur le poste de développement

La flèche du graphe signifie **consommateur dépend du producteur**. Distinguer graphes runtime, build/pack, bootstrap et qualification ; la génération de la structure d'un outil n'est pas une dépendance runtime de cet outil. Le [modèle](requirements/software-ecosystem-factory.roadmaps.json) fournit deux graphes acycliques contrôlables : lots de livraison et composants runtime minimaux.

- HOST0 n'appelle ni SM ni G ; GP0 ne connaît ni le placement ni G. SM0 compose HOST0/GP0, sans exiger le générateur à l'exécution. Les plans Generator avancés sont un adaptateur optionnel ultérieur.
- G0 se construit avec son kit initial possédé. Un registre de paquets ou un Manager non livré ne devient pas son prérequis. Une archive B0 est identifiée par version/hash ; elle est remplaçable après qualification.
- Le feedback DOG1→nouvelle conception G0 est une boucle d'apprentissage **entre révisions**. Il est exclu des dépendances bloquantes de la même révision. La fonction qui vérifie les graphes ne valide pas pour autant le graphe futur des PackageReference/RequiredModules : celui-ci devra être extrait des artefacts livrés.
- Tout cycle de build, de packages ou de démarrage entre composants est bloquant : extraire un contrat neutre justifié ou découper les lots avant de continuer. Une dérogation verbale « poste de dev » ne suffit pas. Un groupe mutuellement dépendant ne peut être toléré que comme un seul composant/versionnement explicitement décidé, sans prétendre à des paquets autonomes.
- Les boucles événementielles IEC/Core sont d'une autre nature : budgets, corrélation, détection de répétitions et annulation relèvent de leurs roadmaps. Aucun broker ni ordonnanceur Core n'est requis pour gérer deux dossiers locaux.

## Gates et décisions restantes

**PlanConsistent** est vérifiable maintenant : tous les fichiers ROADMAP-* sont classés, exigences/AC/kinds résolus, livrables explicites, graphes proposés sans cycles, blocs générés à jour. Ce résultat n'est ni une validation du besoin par l'utilisateur, ni une certification d'architecture.

**ImplementationReady**, par lot, ajoute responsable nommé, contrats d'API et de configuration figés, artefacts/versions résolus, budget chiffré des campagnes et procédure de retour. Les propriétaires restent Unassigned ; aucune de ces décisions n'est fabriquée par cette passe. **I3Accepted** exige les huit scénarios réussis sur les artefacts exacts, les propriétés/fuzz/mutations pertinentes par langage et une décision de recette explicite du responsable. **ReleaseReady** reste une gate séparée de qualification de toutes les plateformes effectivement promises.

Pas de date de fin inventée : ordonner par dépendances et risques. Les estimations arrivent après les contrats et l'inventaire, avec capacité réelle du responsable. La migration globale de i2 et la publication publique restent des livraisons séparées.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**I3** — delivery — Livrable utilisateur prioritaire.

Un environnement i3 équipé du Manager local, reproductible, permettant de gérer plusieurs instances et son propre développement.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Blueprint i3, contrats déploiement/catalogue, fermeture d'amorçage et recette I3-001..008 |
| impl | Déploiement Manager versionné, config/catalogue/lock réels, scripts/docs/AGENTS et deux instances locales |
| test | Recette huit scénarios en session fraîche, reproduction isolée et propriétés/fuzz/mutations des composants sélectionnés |
| obs | Rapport I3Accepted, versions actives/candidates, dépendances, diagnostics et procédure de retour vérifiée |

Traçabilité : I3-001, I3-002, I3-003, I3-004, I3-005, I3-006, I3-007, I3-008. Lots : I3. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| I3-001 | i3 contient une installation Manager versionnée utilisable en session fraîche sans sources i2. | I3-001-AC1 → I3-001-T1 (integration, NotRun) |
| I3-002 | Le catalogue gère au moins deux instances locales distinctes d'un même dépôt et le checkout Manager. | I3-002-AC1 → I3-002-T1 (property, NotRun) |
| I3-003 | La consultation et l'inspection locales de i3 fonctionnent hors réseau. | I3-003-AC1 → I3-003-T1 (integration, NotRun) |
| I3-004 | Une création d'instance locale propose puis applique des effets bornés avec préconditions revérifiées. | I3-004-AC1 → I3-004-T1 (fault, NotRun) |
| I3-005 | Le travail humain et les instances concurrentes restent protégés pendant échec, interruption et reprise. | I3-005-AC1 → I3-005-T1 (fault, NotRun) |
| I3-006 | L'environnement peut être reproduit depuis les artefacts figés dans une racine isolée. | I3-006-AC1 → I3-006-T1 (integration, NotRun) |
| I3-007 | L'auto-gestion du Manager sépare la version N active et la candidate N+1 avec retour local contrôlé. | I3-007-AC1 → I3-007-T1 (fault, NotRun) |
| I3-008 | i3 fournit les commandes documentées, diagnostics et preuves nécessaires à sa recette. | I3-008-AC1 → I3-008-T1 (contract, NotRun) |

**Décision de patterns : Composition root + immutable deployment + staged self-hosting.**

Contexte : Le Manager est développé et consommé sur le même poste.

Problème : Développer directement la version active peut supprimer le moyen de récupérer l'environnement.

Forces : Usage quotidien, plusieurs instances et rollback local.

Participants : Workspace héberge ; déploiement installe ; checkout développe ; catalogue identifie ; gate décide.

Collaboration : N reste actif pendant le développement de N+1 ; activation explicite après recette.

Conséquences : Pas de Git racine i3 ; sources et modules installés séparés ; chemin cible fixé pour cette recette.

Alternative : Dossier vide, simple clone i2 ou import direct de ses sources considéré comme livraison rejeté.

Oracle indépendant : Session fraîche sans source i2, deux instances isolées, preview sans mutation et retour vers N démontrés.

**SOLID / DRY / MODULAR :** SRP hôte/déploiement/source ; DIP vers paquets figés ; DRY des commandes HOST/GP ; frontières de versions propres à chaque écosystème.

Entrée : SM0/MIG0/DOG0 réellement disponibles et décisions ImplementationReady levées.

Sortie : Huit AC I3 réussis sur les artefacts exacts et recette explicitement décidée ; release publique séparée.

Risque : Présence de fichiers ou contrôle documentaire Passed ne prouve pas un environnement utilisable.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
