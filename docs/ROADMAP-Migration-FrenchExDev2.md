# Migration FrenchExDev → FrenchExDev2 — inventaire, vagues et bascule

Date : 10 novembre 2026. Statut : sous-plan proposé, non implémenté et non qualifié.

## Objectif, périmètre et dépendances

Produire un plan de migration contrôlé de l’existant PoSh/Net et des autres catégories du workspace, fondé sur l’inventaire et les dépendances réelles.

GEN/HOST/GP/REG selon profil et disponibilité effective ; SM facultatif pour nouvelles instances. Une migration n’est ni un renommage global ni une obligation de déplacer tous les dossiers.

Références : [ensemble](ROADMAP-Ecosystem-Generator.md), [contrats RaC/kinds](ROADMAP-Requirements-As-Code.md), [registre machine-readable](requirements/software-ecosystem-factory.requirements.json). Origine : demande utilisateur du 10 novembre 2026 ; extension des plans A/M/Adoption.

## Patterns et frontières

Migration progressive par capacités ; adaptateurs de compatibilité ; versionnement des contrats ; fenêtres de coexistence. Ni duplication durable du métier ni remplacement global de chaînes.

## Plan par kind

### design

Périmètre d’inventaire : PoSh/FrenchExDev, Net/FrenchExDev, NodeJs, Rust, VsCode, Wsl, LLVM et scripts du workspace ; profils configurables pour d’autres racines. Distinguer dépôt autonome, projet interne, script d’hôte, configuration de logiciel, laboratoire, fork et clone upstream. Ne pas supposer que chaque dossier est un langage ou un produit à publier. Pour chaque item : owner, git root/remotes, états local/stagé/ignoré, dépendances, usages, paquet/module/namespace, licences, secrets par référence, tests, scripts/docs/AGENTS, destination et stratégie proposées.

### impl

Première livraison : inventaire structuré et graphe des dépendances ; deuxième : plans par vagues et par item ; troisième seulement : exécution explicitement choisie des opérations. Stratégies Keep/Register, AdoptInPlace, CloneAsNewInstance, ExtractProjects, RenamePublicIdentity, Deprecate ont préconditions/compatibilité propres. Les dépôts upstream/forks conservent leurs identités et licences sauf décision distincte. Une nouvelle identité FrenchExDev2 pour du code possédé exige mapping de paquets/modules/namespaces et transition de consommateurs.

### test

Qualification par vague avec paquets installés/caches isolés, comparaison avant/après des contrats, aucun sibling source link, scripts/lifecycle et consommateurs dépendants. Propriétés inventaire stable/idempotence, fuzz manifests et chemins, mutants de fermeture de graphe/ownership ; rollback et reprise simulés dans fixtures possédées.

### obs

Table de migration par item : Discovered/Assessed/Blocked/Planned/Ready/Applied/Qualified/Cutover/Retired. Conserver source/destination, versions, preuves, décisions de bascule et de retour. Un projet non évalué ne devient pas Migrated ; ne jamais supprimer l’original à partir du seul succès du clone.

## Livraisons du plan de migration

1. **Inventaire évalué** : identité locale et origine, nature de l’item, propriétaire, état Git et travail non versionné, contrats publics, consommateurs et fermeture des dépendances. Lire les manifestes/configs comme données ; ne pas importer les modules ou exécuter leurs scripts pendant discovery.
2. **Décision par item** : stratégie, destination résolue via HOST, identité FrenchExDev2 éventuelle, exceptions upstream/forks, préconditions, mapping ancien→nouveau et période de coexistence. Un dossier de catégorie ne reçoit pas automatiquement un .git.
3. **Plan par vague** : producteurs/consommateurs, disponibilité des artefacts, transformations prévues, fichiers humains à protéger, tests indépendants, critères de cutover et scénario de retour. Bloquer les cycles de dépendance ou prévoir leur découplage, sans source links de secours.
4. **Plan d’exécution révisable** : aperçu et préconditions vérifiées à l’application ; opérations locales réversibles distinctes des effets GitHub/publication ; journal d’actions et arrêts partiels. Une version déjà publiée n’est pas annulée en écrasant le registre.
5. **Bilan de bascule** : preuves d’installation/usage, compatibilité des consommateurs, écarts restants, pointeurs documentaires actualisés vers une cible existante et décision séparée de retrait. Les sources non migrées restent accessibles.

Les inventaires, décisions et vagues seront des artefacts structurés versionnés, avec vues lisibles et liens RaC, plutôt qu’un grand script de remplacement de noms. Le stockage exact et les schémas sont des décisions du lot design ; ils ne doivent contenir ni valeurs de secrets ni copie de sorties métier.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Given/When/Then et états détaillés sont dans le registre. Tous les tests sont prévus ; aucune preuve produit n’est déclarée.

## Démo de contrat proposée

```powershell
# Proposed APIs; no migration or file operation has been executed.
$inventory = Get-WorkspaceMigrationInventory -Workspace $workspace -Roots $selectedRoots
$plan = New-FrenchExDev2MigrationPlan -Inventory $inventory -PlacementPolicy $placementPolicy
Show-EcosystemPlan -Plan $plan
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

## Sortie du plan

Propriétaire et décisions de contrat à affecter ; fixtures indépendantes, matrice de qualification et conservation des diagnostics à détailler avant implémentation. Le présent plan n’autorise aucun déplacement, clone distant, commit, publication ou suppression de données existantes.

## Whitelist et gate de dépendances

La [whitelist versionnée](requirements/migration-whitelist.json) est **deny-by-default**. Ses 13 entrées sont des candidats à évaluer, pas une sélection de tout i2 ni une autorisation de migrer. Chaque item porte Assess/Migrate/Create/Exclude et une approbation distincte. Les candidats actuels incluent Result, Builder, FSM, IEC, Requirements PS/.NET, QuietCli, GitHub, DevPoSh et moyens Docker/Compose/Nexus ; Kubernetes PowerShell est explicitement candidat. Aucun autre dossier n'est repris par simple découverte.

`scripts/Test-MigrationDependencies.ps1` est la façade de `Get-MigrationDependencyReport` dans `scripts/lib/Migration.Dependencies.psm1`. Le code s'exécute maintenant pour produire un constat ; il n'exécute jamais les scripts inspectés ni MSBuild. Pour chaque fichier sélectionné, il conserve chemin/kind/SHA-256 et les dépendances déclarées : AST `.ps1/.psm1/.psd1`, `#requires`, imports/using/dot-sourcing, manifestes, solutions `.sln/.slnx`, `.csproj`, `.props/.targets`, projets/packages/imports.

Les calculs dynamiques, conditions MSBuild, dépendances manquantes ou hors whitelist restent explicites et bloquent. Le graphe MSBuild **évalué**, les imports implicites/SDK et les dépendances réellement restaurées nécessitent une preuve complémentaire : le parseur XML statique ne prétend pas les résoudre. Dépendances natives, réflexion, code généré et noms de commandes construits exigent une revue/qualification indépendante. L'analyse n'est pas un remplacement de Roslyn ou de restore/build isolés.

La gate de bascule MIG1 exige **le rapport du validateur lui-même qualifié**, ses versions/empreintes, la whitelist approuvée, la fraîcheur des identités source/politique, la fermeture résolue, les consommations packagées à cache froid, les tests métier et le retour vérifié. `MigrationDependencies=Passed` est une sous-gate nécessaire ; `MigrationQualification=NotAssessed` ne satisfait jamais la gate complète. `-RequireGate` retourne une erreur si la sous-gate est bloquée. `-OutputPath` honore `-WhatIf` et n'écrase pas une preuve existante.

### Kubernetes et structures vides

L'inspection du 10 novembre trouve dans `PoSh/FrenchExDev/FrenchExDev.Kubernetes.PoSh` un manifeste `Kubernetes.PoSh.psd1`, un module `Kubernetes.PoSh.psm1` et `src/Variables/KubernetesSymbols.ps1`. README et `.gitignore` sont vides ; **le module n'est pas vide**. Il reste Assess, avec ses dépendances et comportements à qualifier avant migration en écosystème. Un répertoire `.gitkeep` seul est ScaffoldCandidate : une décision Create peut y préparer la structure SoftwareContract, sans inventer un logiciel historique ou un succès de migration. Les sous-répertoires vides n'effacent jamais le code du parent.

### Exports réels après chargement

À la demande utilisateur, compléter l'AST par `scripts/Test-PowerShellModuleExports.ps1` : charger explicitement le `.psd1` ou `.psm1` sélectionné, puis appeler **Get-Module** dans un processus PowerShell frais. Relever identité/chemins/hash, **ExportedFunctions**, **ExportedCmdlets**, alias et origine des commandes, ainsi que RequiredModules réellement chargés. Comparer au contrat attendu ; les noms définis dans le source ou `FunctionsToExport='*'` ne suffisent pas. Un import impossible est Failed, pas une liste vide qualifiée.

Le paramètre `-StageCopy` permet une copie vérifiée dans les rapports temporaires pour préserver l'état source et séparer les caches du loader ; le rapport attribue le résultat à cette copie, pas à l'installation d'origine. Le processus séparé protège l'état du contrôleur mais n'est pas une sandbox OS. WhatIf ne crée ni copie, ni processus, ni rapport. Sélection explicite, deadline et moniteur visible sont requis.

Le 10 novembre, la sonde sur une copie Kubernetes vérifiée charge réellement le module `0.0.1` et observe **0 fonction, 0 cmdlet et 0 alias**. Ce constat caractérise la surface actuelle ; sans contrat d'exports attendu, Qualification reste NotAssessed. Il ne prouve ni une fonctionnalité Kubernetes ni une migration réussie.

`scripts/Test-MigrationGate.ps1` appelle `Test-MigrationQualification` : la gate revalide sources/politique/contrôleur, exige que les bibliothèques du contrôleur figurent dans la qualification complète réussie avec campagnes property/fuzz/mutation, puis exige les preuves d'exports réels et tests/restauration/retour du produit. Elle bloque en leur absence. Le validateur est ainsi un moyen **lui-même qualifié** de la migration, et pas seulement un document joint au plan.

### Moyens et stratégie de qualification

### Compilation .NET Release

`scripts/Test-DotNetMigrationBuild.ps1` découvre `.slnx`, `.sln` et `.csproj` sous `Net/FrenchExDev`. La bibliothèque réutilisable sépare découverte en lecture seule, exécution et tableau. Par défaut les builds portent sur les entrées de whitelist ; `-ItemId`/`-Target` bornent précisément la sélection, `-AllDiscovered` étend explicitement le diagnostic sans approuver de migration. Les dossiers de build/cache/mutation sont exclus. Chaque solution et chaque projet sélectionné ont leur propre reçu, même lorsqu'un projet figure déjà dans une solution.

Commande réelle : **`dotnet build <fichier> --configuration Release`** (`-c`, en minuscule). Le script résout le SDK depuis le dossier cible, impose UTF-8 dans le processus enfant, borne chaque build et la campagne, poursuit après un échec et conserve état/code retour/durée/hash/arguments/logs par entrée. `-WhatIf` ne lance ni SDK, ni restore/build, ni processus ou écriture. Tableau Unicode et `build-results.json` accompagnent l'exécution ; `-OutputFormat Json` fournit du JSON seul dans le pipeline, `Object` permet la composition.

Le validateur existant expose aussi `-BuildDotNet` avec `-BuildTarget`, `-NoRestore` et les chemins/bornes de rapport. La gate complète exige désormais `-DotNetBuildReportPath` pour les entrées .NET et la qualification actuelle de la bibliothèque de build. Elle refuse un plan, un résultat incomplet/échoué, un hash différent ou une entrée manquante. **Build Release réussi reste une preuve de compilation** ; le graphe MSBuild évalué exhaustif, les tests métier, la restauration depuis paquets et le retour restent des exigences distinctes. [Référence CLI officielle](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-build).

Le validateur est du code PowerShell utilisant les AST PowerShell et les API XML .NET ; il ne nécessite pas de compiler une nouvelle bibliothèque C# pour démarrer. Ses contrats permettraient un extracteur Roslyn/MSBuild ultérieur séparé. Son compagnon de tests doit vérifier whitelist/containment/liens, scripts non exécutés, imports et chemins, XML hostile, packages/versions et cycles, avec propriétés, corpus malformé et mutations des refus. Le rapport garde les écarts par langage et reste distinct de la qualification du logiciel inspecté.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**MIG** — product — Inventaire sélectionné avant i3 ; bascules ultérieures.

Choisir et qualifier la reprise des éléments existants sans déplacement global ni réécriture d'identités upstream.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Inventaire typé, graphe réel, décisions par item et plan de coexistence/retour |
| impl | Commandes d'inventaire read-only puis plans de vagues et opérations sélectionnées |
| test | Stabilité d'inventaire, fixtures dirty/ignorées, paquets isolés, fuzz chemins et mutants d'ownership |
| obs | États Discovered→Assessed→Planned→Qualified→Cutover par item et preuves de retour |

Traçabilité : MIG-011, MIG-010, MIG-007, MIG-008, MIG-009, MIG-001, MIG-002, MIG-003, MIG-004, MIG-005, MIG-006. Lots : MIG0, MIG1. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| MIG-011 | La migration .NET découvre solutions/projets et exige des builds Release réels, avec WhatIf sans effet, tableau et résultats JSON par entrée. | MIG-011-AC1 → MIG-011-T1 (integration, NotRun) |
| MIG-010 | La qualification PowerShell observe Get-Module après import réel isolé et compare les fonctions/cmdlets réellement exportées au contrat attendu. | MIG-010-AC1 → MIG-010-T1 (integration, NotRun) |
| MIG-007 | La migration est deny-by-default et ne sélectionne que des items de whitelist avec décision explicite Assess/Migrate/Create/Exclude. | MIG-007-AC1 → MIG-007-T1 (property, NotRun) |
| MIG-008 | Chaque ps1/psm1/psd1 et solution/projet C# sélectionné est analysé par une bibliothèque réutilisable comptée dans la gate de migration. | MIG-008-AC1 → MIG-008-T1 (fault, NotRun) |
| MIG-009 | Une structure vide ou .gitkeep est un candidat à créer ; un module partiellement rempli conserve son code et ses écarts sans succès de migration inventé. | MIG-009-AC1 → MIG-009-T1 (property, NotRun) |
| MIG-001 | L’inventaire couvre les catégories réelles sans les confondre avec des langages. | MIG-001-AC1 → MIG-001-T1 (integration, NotRun) |
| MIG-002 | Chaque item possède une décision de migration et un mapping d’identité explicites. | MIG-002-AC1 → MIG-002-T1 (review, NotRun) |
| MIG-003 | Les vagues respectent la fermeture réelle des dépendances et le contrat des consommateurs. | MIG-003-AC1 → MIG-003-T1 (integration, NotRun) |
| MIG-004 | La migration préserve données locales et secrets et n’effectue aucun déplacement implicite. | MIG-004-AC1 → MIG-004-T1 (fault, NotRun) |
| MIG-005 | La bascule et le retrait sont conditionnés aux preuves de compatibilité et à un retour prévu. | MIG-005-AC1 → MIG-005-T1 (integration, NotRun) |
| MIG-006 | Les scripts d’hôte et ressources de logiciel suivent une migration distincte des packages. | MIG-006-AC1 → MIG-006-T1 (contract, NotRun) |

**Décision de patterns : Incremental migration + compatibility adapters.**

Contexte : i2 contient produits autonomes, projets, forks et scripts d'hôte.

Problème : Un remplacement global de noms perd provenance, travail local et compatibilité.

Forces : Versions publiques, droits sur upstream et bascule progressive.

Participants : Inventaire constate ; décideur choisit ; HOST place ; GP applique ; tests consommateurs qualifient.

Collaboration : Producteurs packagés précèdent leurs consommateurs ; retrait est une décision séparée.

Conséquences : MIG0 est borné aux entrées i3 sélectionnées ; MIG1 ne bloque pas le premier usage local.

Alternative : Copie exhaustive i2→i3 ou renommage global FrenchExDev2 rejetés.

Oracle indépendant : Un item non évalué reste non migré ; la source dirty et les identités upstream sont préservées.

**SOLID / DRY / MODULAR :** SRP inventory/decision/apply ; DRY des transformations ; modules par propriétaire ; pas de moteur Git parallèle.

Entrée : FAC/B0 pour MIG0 ; contrats des producteurs avant les vagues MIG1.

Sortie : Décision et preuve par item ; aucune suppression de source autorisée par un succès de clone.

Risque : Les fichiers ignorés et usages non inventoriés peuvent invalider une bascule apparemment réussie.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| MIG0 | Get-MigrationDependencyReport → Test-MigrationQualification | Evidence | I3SEED, RESULT, RACPKG, MIG1 | migration-decisions | Proposed |
| MIG1 | Invoke-QualifiedMigrationPlan → Test-MigrationQualification | Evidence |  | migration-decisions, i3-host-index | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
