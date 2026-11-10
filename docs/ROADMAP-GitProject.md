# GitProject — opérations Git mono-dépôt et chemins d’instances

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Réutiliser création, validation, identité source, commit et push sans fusionner les dépôts ou confondre leurs identités.

Dépendances : G0 crée sa structure ; module GitProject indépendant du moteur de génération. Les bindings Generator consomment GP, pas l’inverse. HOST résout les placements et Manager les orchestre ; GP reçoit un Path déjà résolu et n’impose pas de taxonomie.

Origine : plan Claude §4 GP.1–GP.6. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Facade pour les .ps1 ; pipeline de checks ; Strategy pour les conventions ; frontière Git/hosting explicite.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Le défaut develop concerne les nouveaux dépôts seulement. Un dépôt peut publier zéro, un ou plusieurs paquets, chacun avec son identité explicite. Le résolveur de chemins configurable distingue workspace, org, repo et instance. Valider containment canonique, chemins absolus injectés, segments réservés, collisions de casse et liens/reparse points ; une règle anti-dossier numérique n’est pas suffisante.

### impl

New-GitProject, Invoke-GitProjectCommit et Push-GitProject sont des commandes proposées à exporter ; leurs façades et docs consomment ces commandes. Préserver le snapshot stagé de -NoAll ; réutiliser les adaptateurs de checks sans reprendre les noms QuietCli. **GP0 inclut clone depuis un dépôt local possédé**, validation de destination et reçu, nécessaires à SM0 (GP-005). Fetch et pull ont des contrats distincts ; le réseau reste explicitement choisi. Ces opérations sont à implémenter, pas installées par le présent plan.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Dépôts jetables possédés, jamais le checkout réel. Exemples, générateurs de noms/chemins, fuzz traversal et formes Unicode, mutants de sélection d’index/WhatIf/gates. Branches feature locales autorisées ; contrôler la branche distante configurée sans assimiler une branche feature à une anomalie.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Identité repo/révision/index, gates bloquantes ou diagnostics, état commit/push, branche réelle, codes d’erreurs et effets inconnus. Aucun retry automatique de push.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$placement = Resolve-EcosystemPlacement -Workspace $workspace -Profile 'Interest' -Repository 'Acme/Tools' -Instance 0
New-GitProject -Path $placement.Path -Name 'Acme.Tools' -InitialBranch 'develop' -WhatIf
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**GP** — product — Opérations locales nécessaires au Manager.

Gérer un seul dépôt au chemin fourni en préservant index, contenu humain et identité.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Contrats init/clone local/fetch/commit/push, préconditions et résultat d'effet inconnu |
| impl | Paquet GitProject et fonctions exportées avec façades, aide et docs miroir |
| test | Dépôts jetables indépendants, snapshot -NoAll, WhatIf, fuzz arguments et mutants d'isolation |
| obs | Reçu repo/HEAD/index/opération et états terminaux ; fetch et pull distincts |

Traçabilité : GP-005, GP-001, GP-002, GP-003, GP-004. Lots : GP0. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| GP-005 | Le Manager peut créer une instance depuis un dépôt local sans écraser une destination existante. | GP-005-AC1 → GP-005-T1 (integration, NotRun) |
| GP-001 | Les conventions de dépôt ne réécrivent jamais les identités de paquets existantes. | GP-001-AC1 → GP-001-T1 (contract, NotRun) |
| GP-002 | Le résolveur garantit que chaque instance appartient à la racine autorisée. | GP-002-AC1 → GP-002-T1 (fuzz, NotRun) |
| GP-003 | Un commit -NoAll valide exactement le snapshot stagé et préserve le reste. | GP-003-AC1 → GP-003-T1 (integration, NotRun) |
| GP-004 | Création et push restent des opérations explicites sans modification rétroactive de branche. | GP-004-AC1 → GP-004-T1 (contract, NotRun) |

**Décision de patterns : Facade + Ports/Adapters + explicit check pipeline.**

Contexte : Le même dépôt est manipulé depuis l'hôte, le générateur et le Manager.

Problème : Les wrappers peuvent dupliquer les gates ou sélectionner des fichiers non demandés.

Forces : Index exact, opérations Git non atomiques et aucun retry d'effet inconnu.

Participants : Commande possède politique ; exécuteur Git injecté ; adaptateurs de checks ; façade transmet.

Collaboration : HOST fournit le chemin ; GP valide sa portée et exécute une opération Git explicite.

Conséquences : Le code Git ne dépend ni de SM ni de G ; la résolution du placement reste à HOST.

Alternative : Copier les scripts QuietCli avec leurs noms et politiques rejeté.

Oracle indépendant : Un commit -NoAll correspond exactement au snapshot stagé ; une destination occupée ne subit aucun écrasement.

**SOLID / DRY / MODULAR :** SRP mono-dépôt ; DIP sur exécution/checks ; DRY des gates ; pas de taxonomie du workspace dans GP.

Entrée : G0/DOG0 pour sa structure ; Git présent et version supportée explicitée.

Sortie : Clone local et préservation démontrés avant SM0 ; push distant qualifié séparément.

Risque : Les hooks et un push interrompu peuvent avoir des effets impossibles à annuler automatiquement.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| GP0 | New-GitProjectPackage → Test-GitProject | BootstrapArchive | SM0, G2 | source-GP | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
