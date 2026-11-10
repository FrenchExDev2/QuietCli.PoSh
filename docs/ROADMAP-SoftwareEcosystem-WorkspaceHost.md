# WorkspaceHost — héberger des instances selon plusieurs organisations

Date : 10 novembre 2026. Statut : sous-plan proposé, non implémenté et non qualifié.

## Objectif, périmètre et dépendances

Gérer une ou plusieurs racines de travail, leurs outils scripts/fonctions et les instances d’écosystèmes, sans imposer une hiérarchie par langage.

G0 produit la structure, sans devenir une dépendance runtime de HOST. HOST0 possède le modèle workspace/instance et la résolution de placement ; il ne dépend pas de Manager. GP reçoit un chemin déjà résolu ; Manager consomme HOST et GP packagés. HOST ne réimplémente ni discovery distante ni clone et ne dépend pas en retour de SM.

Références : [ensemble](ROADMAP-Ecosystem-Generator.md), [contrats RaC/kinds](ROADMAP-Requirements-As-Code.md), [registre machine-readable](requirements/software-ecosystem-factory.requirements.json). Origine : demande utilisateur du 10 novembre 2026.

## Patterns et frontières

Strategy de placement ; Ports/Adapters de configuration/discovery ; Facade des commandes hôte. Une vue de classement n’est pas une frontière de versionnement.

## Plan par kind

### design

Un workspace est un hôte configurable, pas un super-écosystème. Une instance est identifiée par repositoryId + instanceId, son chemin canonique, sa racine autorisée et son état. Langages, logiciel, intérêts et provenance GitHub sont des facettes indépendantes, éventuellement multiples. Profils de placement Language, Software, Interest, DirectRepository et CustomTemplate ; aucune dimension obligatoire nommée Language. Les templates sont des données à tokens autorisés, jamais du code évalué. Un alias/vue ne crée pas un second clone.

### impl

Fonctions exportées Get/New-SoftwareEcosystemWorkspace, Resolve-EcosystemPlacement, Register-SoftwareEcosystemInstance, New-WorkspaceToolingPlan et Test-WorkspaceSanity. Chaque workspace peut avoir scripts/ et docs/scripts/ : les .ps1 appellent le module HOST versionné installé explicitement. Le chemin C:/code/FrenchExDev/FrenchExDev_i2/scripts est un exemple réel à adopter, pas un dossier à écraser. Le propriétaire/version du tooling reste explicite, sans CPM ou release partagé par tous les dépôts hébergés.

### test

Profils langue/logiciel/intérêt/direct, instance existante hors convention, root configurable, multi-root, collision de facettes et déplacement planifié. Propriétés unicité/containment, fuzz templates/segments/liens, mutants d’isolation/config. Éprouver une instance LLVM comme clone direct sans lui imposer FrenchExDev2 ou une langue.

### obs

Catalogue d’instances, placement résolu et raisons, version tooling, diagnostics de collision, opérations prévues/appliquées/refusées. Config locale et tokens non exposés ; pas de scan réseau implicite.

## Outillage propre de chaque hôte

Le module propriétaire des fonctions est distribué et épinglé ; les scripts restent des entrées locales stables. Les noms ci-dessous sont proposés et seront confrontés à l’inventaire des quatre scripts déjà présents avant création.

| Entrée dans <workspace>/scripts/ | Fonction réutilisable | Doc miroir dans <workspace>/docs/scripts/ |
| --- | --- | --- |
| Initialize-Workspace.ps1 | New-WorkspaceToolingPlan puis application explicite | Initialize-Workspace.md |
| Get-Instances.ps1 | Get-SoftwareEcosystemInstance | Get-Instances.md |
| New-InstancePlan.ps1 | New-SoftwareEcosystemClonePlan | New-InstancePlan.md |
| Test-WorkspaceSanity.ps1 | Test-WorkspaceSanity | Test-WorkspaceSanity.md |
| New-MigrationPlan.ps1 | New-FrenchExDev2MigrationPlan | New-MigrationPlan.md |

La future initialisation génère les façades des seules capacités installées, leur aide/index et les règles d'hôte. HOST0 fournit Initialize-Workspace, Get-Instances et Test-WorkspaceSanity ; les entrées de clone Manager et de migration n'apparaissent qu'avec leurs modules correspondants, jamais comme commandes vides réputées utilisables. Aucun clone produit, changement de profil personnel ou dépôt Git englobant n'est implicite. Les fonctions sont consommables directement depuis une autre automatisation.

Les règles AGENTS d’hôte décrivent le registre d’instances, les portées autorisées et l’usage de ces commandes. Les AGENTS des écosystèmes restent propriétaires de leurs builds/tests/releases. Une règle d’hôte ne substitue pas son CPM, ses secrets ou son outillage produit à ceux d’une instance.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Given/When/Then et états détaillés sont dans le registre. Tous les tests sont prévus ; aucune preuve produit n’est déclarée.

## Démo de contrat proposée

```powershell
# Proposed APIs; no migration or file operation has been executed.
$placement = Resolve-EcosystemPlacement -Workspace $workspace -Profile 'DirectRepository' -Repository 'llvm/llvm-project' -Instance 0
$plan = New-WorkspaceToolingPlan -Workspace $workspace -ScriptsPath 'scripts' -DocumentationPath 'docs/scripts'
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

## Sortie du plan

Propriétaire et décisions de contrat à affecter ; fixtures indépendantes, matrice de qualification et conservation des diagnostics à détailler avant implémentation. Le présent plan n’autorise aucun déplacement, clone distant, commit, publication ou suppression de données existantes.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**HOST** — product — Modèle local nécessaire au Manager.

Identifier et héberger des instances sans déduire leur identité du classement des dossiers.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Schémas workspace/instances, racines autorisées, placements et transactions du catalogue |
| impl | Paquet HOST0 : résolution, enregistrement/listing local et façades d'hôte documentées |
| test | Containment canonique, collisions Unicode/casse/reparse, propriétés d'unicité et mutants de portée |
| obs | Raisons du placement, état du catalogue, conflits et version de tooling |

Traçabilité : HOST-001, HOST-002, HOST-003, HOST-004, HOST-005, HOST-006. Lots : HOST0. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| HOST-001 | Un workspace permet un classement par langage, logiciel, intérêt ou dépôt direct sans dimension obligatoire. | HOST-001-AC1 → HOST-001-T1 (property, NotRun) |
| HOST-002 | L’identité d’une instance est indépendante de ses facettes et de son emplacement. | HOST-002-AC1 → HOST-002-T1 (contract, NotRun) |
| HOST-003 | Chaque hôte dispose de fonctions réutilisables et de façades scripts documentées. | HOST-003-AC1 → HOST-003-T1 (contract, NotRun) |
| HOST-004 | Un hôte ne partage pas les versions et secrets de ses écosystèmes hébergés. | HOST-004-AC1 → HOST-004-T1 (integration, NotRun) |
| HOST-005 | Les changements de placement restent des opérations explicites et réversibles selon leur portée. | HOST-005-AC1 → HOST-005-T1 (fault, NotRun) |
| HOST-006 | Les templates de placement ne sont jamais évalués comme code. | HOST-006-AC1 → HOST-006-T1 (fuzz, NotRun) |

**Décision de patterns : Strategy placement + Repository catalogue + Ports/Adapters.**

Contexte : Les vues langage, logiciel et intérêt peuvent désigner le même checkout.

Problème : Une taxonomie physique rigide crée des clones en double ou des chemins dangereux.

Forces : Facettes multiples, portabilité des chemins et aucune exécution de template.

Participants : Résolveur produit un emplacement ; catalogue possède les identités ; adaptateur persiste atomiquement.

Collaboration : Manager demande un placement puis enregistre seulement l'opération Git aboutie.

Conséquences : HOST ne clone pas et ne dépend pas de Manager ; un catalogue corrompu reste une erreur diagnostiquée.

Alternative : Déduire repositoryId d'un dossier ou imposer Language à toutes les instances rejeté.

Oracle indépendant : Plusieurs facettes conservent une seule instance ; traversal, lien sortant et collision sont refusés avant écriture.

**SOLID / DRY / MODULAR :** SRP identité/placement/persistance distincts ; OCP des stratégies ; DRY du containment ; module sans dépendance retour SM/G.

Entrée : G0/DOG0 pour la structure ; contrat de persistance et d'ownership arrêté.

Sortie : Catalogue et placements fiables sur deux instances ; fonctions consommables sans scripts.

Risque : Une simple comparaison de préfixes de chemin n'assure pas le containment réel.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
