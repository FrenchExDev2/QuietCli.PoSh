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

Traçabilité : MIG-001, MIG-002, MIG-003, MIG-004, MIG-005, MIG-006. Lots : MIG0, MIG1. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
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

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
