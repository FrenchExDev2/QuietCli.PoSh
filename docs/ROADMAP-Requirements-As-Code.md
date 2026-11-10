# Requirements-as-Code — contrat commun de la software ecosystem factory

Date : 10 novembre 2026. Statut : contrat de travail proposé. Un contrôle documentaire exécutable est fourni ; les adaptateurs de traçabilité produit et l'évaluation de satisfaction métier restent à réaliser.

## Définition d'une roadmap et contrat de validation

Une **roadmap** est un contrat de progression versionné vers un résultat utilisateur : périmètre, livrables vérifiables, dépendances, décisions et conditions de passage. Elle se raffine par lots à mesure que l'incertitude diminue. Un backlog détaille les tâches ; un design décrit la solution ; un calendrier engage des dates selon une capacité connue. Aucun des trois ne remplace à lui seul une roadmap. Ici, le plan directeur pilote le portefeuille, la revue conserve des constats datés, le contrat RaC est transversal et les autres fiches possèdent des capacités ou une recette. On ne force pas un paquet logiciel pour une fiche de revue.

Chaque fichier ROADMAP-* a un contrat dans [le modèle canonique des roadmaps](requirements/software-ecosystem-factory.roadmaps.json) : identité/type, résultat, rôle pour i3, lots, quatre livrables par kind, entrée/sortie, risque et décision de patterns. Le bloc `roadmap-contract` est une projection générée, jamais une deuxième source éditable. Le registre d'exigences conserve les AC ; `roadmap:<ID>/<kind>` relie un workItem à son livrable planifié dans ce modèle, sans prétendre que l'artefact existe.

La cible demandée est [i3 équipé du Manager local](ROADMAP-Delivery-FrenchExDev-i3.md). Les dépendances de lots sont des prérequis de disponibilité/qualification ; les dépendances runtime sont un autre graphe. Les PackageReference/RequiredModules et outils de build réels devront ensuite être extraits des manifestes et paquets : le graphe de planning ne les prouve pas. Chaque arête future indique consommateur/producteur, nature, version/contrat, caractère requis/optionnel, source du constat et gate. Un cycle bloquant dans une même révision est refusé ; le feedback entre révisions reste contrôlé et séparé.

```powershell
# Read-only planning assessment. This does not execute product acceptance tests.
$report = ./scripts/Invoke-RoadmapContract.ps1
$report.Passed
$report.ReadinessGaps

# Explicitly regenerate the managed delivery views and work-item references.
./scripts/Invoke-RoadmapContract.ps1 -Apply -WhatIf
./scripts/Invoke-RoadmapContract.ps1 -Apply
```

Le contrôle est une fonction PowerShell réutilisable, avec façade documentée. Il vérifie inventaire des fichiers, IDs/liens, quatre kinds, livrables, champs de décision POSA, cohérence déclarée des états de preuve, graphes proposés et fraîcheur des vues. Son compagnon éprouve des erreurs injectées, propriétés de graphes, entrées malformées et mutations ciblées. Cela valide des invariants documentaires ; la pertinence des forces/alternatives, les responsabilités SOLID et l'acceptation du besoin restent une revue d'ingénierie puis des preuves produit.

Gates : **PlanConsistent** (structure cohérente), **ImplementationReady** par lot (responsable nommé, contrats/versions/fermeture résolus, budgets de campagnes et retour), **I3Accepted** (recette locale sur artefacts exacts) et **ReleaseReady** (matrice promise complète). Le contrôleur courant ne délivre que PlanConsistent et expose les manques des gates suivantes. Un plan cohérent peut rester Proposed ; Passed documentaire ne devient jamais Passed d'un AC produit.

## Références d'ingénierie et application locale

Les références suivantes cadrent la revue : [ISO/IEC/IEEE 29148:2018](https://www.iso.org/standard/72089.html) pour l'ingénierie des exigences, [ISO/IEC/IEEE 42010:2022](https://www.iso.org/standard/74393.html) pour les descriptions d'architecture et [ISO/IEC 25010:2023](https://www.iso.org/standard/78176.html) pour définir/mesurer les qualités produit. Les notices et résumés officiels ont été consultés ; aucune conformité intégrale à leurs clauses ni certification n'est revendiquée. La politique ci-dessous est une application locale, pas une citation de normes.

- Exigences : intention identifiable, source, propriétaire, AC observable, dépendances et test indépendant ; scinder les exigences composées avant le lot d'exécution.
- Architecture : parties prenantes, préoccupations, frontières, vues de dépendances, décisions/alternatives et conséquences. SOLID/DRY/MODULAR se jugent sur responsabilités, substitutions, points d'extension et direction des dépendances.
- Qualité : disponibilité hors réseau, intégrité du catalogue, isolation, récupérabilité et compatibilité ont des AC concrets. Temps/mémoire/concurrence/durée des campagnes reçoivent des budgets chiffrés avant ImplementationReady ; aucune performance n'est présumée.
- Patterns : [POSA, A System of Patterns](https://www.wiley.com/en-gb/pattern-oriented-software-architecture-volume-1-a-system-of-patterns-p-9781118725269) guide l'analyse contexte/problème/forces/solution/conséquences. [Ports/Adapters](https://alistair.cockburn.us/hexagonal-architecture) sert aux frontières testables. Strategy/Adapter/Observer/Builder sont des patterns de conception ; tous ne sont pas des patterns POSA. Les kinds design/impl/test/obs classent les artefacts et restent orthogonaux ; ils ne sont ni un catalogue de patterns ni une séquence en cascade.

Chaque fiche doit pouvoir réfuter un choix : qui possède la règle, quel consommateur substituable l'éprouve, quelle duplication est éliminée, quelle complexité est ajoutée, quel test pourrait rejeter l'invariant ? Une liste de noms ne satisfait pas FAC-008/FAC-011.

## Décision et périmètre

La traçabilité est obligatoire pour **toutes** les capacités de la factory, y compris PowerShell, Git, documentation, configuration, bootstrap, profils, registres, tests et observabilité. Le choix d’un moteur particulier reste interchangeable ; l’obligation de traçabilité ne l’est pas. Une checklist humaine seule ne couvre pas cette demande.

Le [registre JSON versionné](requirements/software-ecosystem-factory.requirements.json) contient les exigences identifiées, leurs AC Given/When/Then, IDs de vérifications prévues, états de preuves et liens aux quatre kinds. Les comptes sont calculés par le contrôleur. Ce registre ne prétend pas que les tests produit existent ou que le comportement est réalisé. La complétude finale nécessite les raffinements et décisions encore ouverts de chaque sous-plan.

Le JSON est un **format d’échange/bootstrap**, pas une troisième DSL métier à maintenir en parallèle. Avant implémentation, inventorier Requirements-As-Code.PoSh/Requirements.ts cités par Claude, le module legacy PowerShell et FrenchExDev.Net.Requirements. Le README du module PowerShell legacy inspecté est vide : aucune capacité n’en est déduite.

## Chaîne et autorité

Requirement (WHY) ↔ Feature (WHAT) ↔ Acceptance Criterion (HOW) ↔ Test (PROOFING) ⇒ Coverage et résultats (PROOF / EVIDENCE). Les liens sont navigables dans les deux sens ; design, symboles implémentés et observabilité précisent les relations. Propriétés, fuzzing et mutations éprouvent les assertions ; la couverture et les résultats consignent ce qui a réellement été exercé, avec ses lacunes. Ils ne démontrent pas à eux seuls que le besoin métier est juste.

Une exigence a un propriétaire, une source, une priorité, ses dépendances et une version de contrat. Les propriétaires sont actuellement Unassigned ; cela bloque le passage à execution-ready. Les IDs restent stables ; renommer un fichier ou un symbole ne recrée pas l’exigence. Une modification de sens invalide les preuves antérieures tant qu’une analyse d’impact n’a pas conclu à leur applicabilité.

Les REQUIREMENTS.md et tableaux sont des vues de lecture à générer depuis le modèle canonique choisi, pas des copies éditables indépendantes. Pour la future DSL .NET, typeof()/nameof() et les attributs existants conservent leurs garanties ; un adaptateur relie leurs symboles aux IDs communs. Compilation/analyzers prouvent les liens déclarés, pas la satisfaction métier. PowerShell et TypeScript doivent fournir des preuves équivalentes sans exiger Roslyn comme runtime universel.

## Kinds obligatoires et orthogonaux

| Kind | Livrable attendu | Condition de sortie |
| --- | --- | --- |
| design | Contrats, limites, patterns et décision justifiée | Invariants, alternatives et risques revus ; AC explicites |
| impl | Fonctions/cmdlets, adaptateurs et façades/docs | Symboles reliés aux exigences ; dépendances et compatibilité déclarées |
| test | Exemples, propriétés, fuzzing, mutations et scénarios de panne | Résultats exécutés avec scope/source/toolchain ; lacunes visibles |
| obs | Reçus, mesures, diagnostics et supervision | Terminal observable, confidentialité et conservation vérifiées |

Les kinds décrivent la nature d’un travail/artefact ; ils ne sont pas des langages, des dossiers imposés, des étapes exclusives ou des niveaux de maturité. Obs se conçoit dès design et s’éprouve pendant test. Le projet existant *.Design d’acquisition de schémas/help est un outil spécialisé ; il ne représente pas à lui seul tout le kind design.

## Patterns et grille POSA

Pour chaque composant : contexte → problème → forces → pattern retenu → participants/responsabilités → collaborations → conséquences → alternative rejetée → propriété à vérifier. Nommer les points d’extension et la direction des dépendances. SOLID/DRY/MODULAR sont évalués sur ces responsabilités, pas par le nombre d’interfaces ou de dépôts.

Familles candidates selon besoin : couches et Ports/Adapters pour séparer domaine/infrastructure ; Pipes and Filters pour des transformations explicites ; Broker uniquement à une vraie frontière de transport ; Reactor/Active Object comme analyses possibles du drainage et du scheduling. Aucun de ces noms n’impose un thread PowerShell supplémentaire ou de l’IPC. Les roadmaps donnent leurs choix locaux ; la future décision doit expliciter forces et conséquences. « Respecte POSA » sans analyse ni test n’est pas un critère satisfait.

Les règles locales de Skills/Net/Programming/REQUIREMENTS et DESIGN-PHASED-PROJECT servent de références inspectées. Les règles de patrons spécifiques (ex. projets/cibles de Bundle) doivent être confrontées au code actuel et au besoin ; ne pas les étendre mécaniquement à toute la factory. Une erreur de génération doit rester un diagnostic bloquant, même si un ancien patron recommande de l’écrire en commentaire.

## États, liens et vérification du modèle

Statut d’exigence : Proposed → Accepted → Implemented → Verified → Released, avec Retired/Blocked explicites. État de vérification : Planned/Implemented/Executed ; résultat séparé Passed/Failed/Skipped/NotRun/Unknown. Une exception est datée, motivée, bornée et validée par le propriétaire ; elle ne devient pas un Passed.

Dans le registre actuel, chaque AC possède un testId prévu, implementationRef=null et evidence.status=NotRun. kindLinks désigne quatre workItems réels du registre. Le contrôle documentaire vérifie les liens et dépendances déclarés, cycles, quatre kinds, Given/When/Then et cohérence de maturité/preuves ; les propriétaires manquants sont des gaps ImplementationReady. L'évaluation complète des preuves, couverture des frontières publiques et invalidation sémantique reste une capacité produit ultérieure.

Une preuve exécutée inclut : test réel/symbole, révision et empreintes, versions des contrats/profils/paquets, runtime/OS/architecture, configuration, seed/corpus si pertinent, commande/runner, état terminal, artefacts et leur empreinte. Ne jamais sérialiser un secret ou une sortie métier brute pour satisfaire la traçabilité.

Les rapports rendent distincts couverture de liens, couverture de tests exécutés, satisfaction des AC et qualification de release. Un taux de liens de 100 % ne prouve aucune validité du besoin métier.

## Démo de structure et usage futur

```json
{
  "id": "GEN-003",
  "kindLinks": ["GEN-design", "GEN-impl", "GEN-test", "GEN-obs"],
  "acceptance": [{
    "id": "GEN-003-AC1",
    "verification": {"id": "GEN-003-T1", "status": "Planned", "implementationRef": null},
    "evidence": {"status": "NotRun", "artifacts": []}
  }]
}
```

Ce fragment est une projection du registre complet, pas son schéma exhaustif.

```powershell
# Proposed commands; a preview must not fabricate executed evidence.
$report = Test-EcosystemRequirements -Path $requirementsPath
$report.Gaps
$plan = New-EcosystemRequirementsViewPlan -Path $requirementsPath
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

Test-EcosystemRequirements est une fonction réutilisable, exposée par une façade scripts/Test-Requirements.ps1 et docs/scripts/Test-Requirements.md. La génération de vues suit la même règle. Leur propre comportement est couvert par FAC-002/FAC-003 ; le validateur ne doit pas exempter ses propres exigences.

## Exigences communes

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

## Gate de passage et lacunes actuelles

PlanConsistent exige les quatre kinds, les AC, livrables, dépendances et décisions explicites. ImplementationReady ajoute propriétaire nommé, contrats/versions figés pour le lot, fermeture des paquets, scénarios détaillés, budgets et retour. I3Accepted applique la recette locale dédiée. ReleaseReady exige les résultats de la matrice requise sur les artefacts exacts ; une exécution ciblée ne suffit pas.

Aujourd’hui les exigences produit sont proposées, les tests sont prévus et leurs preuves sont NotRun. Le contrôle documentaire et les blocs de livraison générés existent ; ils ne remplacent ni les adaptateurs entre moteurs ni le validateur de preuves produit. Les campagnes du contrôleur sont des preuves de ce tooling uniquement.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**FAC** — contract — Prérequis documentaire et transversal.

Rendre les exigences, AC, quatre kinds, dépendances et preuves contrôlables sans imposer une DSL unique.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Contrat de roadmap, états/gates, schémas de liens et politique d'invalidation des preuves |
| impl | Registres versionnés, fonctions de contrôle documentaire et vues générées ; adaptateurs produit ultérieurs |
| test | Compagnon indépendant du contrôleur : exemples, propriétés, corpus malformé et mutants ciblés |
| obs | Rapport PlanConsistent distinct des écarts ImplementationReady et de toute qualification produit |

Traçabilité : FAC-011, FAC-001, FAC-002, FAC-003, FAC-004, FAC-005, FAC-006, FAC-007, FAC-008, FAC-009, FAC-010. Lots : FAC. Une relation de lot est un prérequis de livraison, pas un import runtime.

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

**Décision de patterns : Ports/Adapters + canonical model and projections.**

Contexte : PowerShell, C# et TypeScript portent des exigences reliées.

Problème : Une checklist ou plusieurs copies éditables dérivent.

Forces : Typage local, traçabilité commune et bootstrap simple.

Participants : Registre identifie ; adaptateurs relient symboles ; contrôleur inspecte ; vues restituent.

Collaboration : Une seule source par information ; les vues sont régénérées depuis le modèle.

Conséquences : Le contrôle de forme est exécutable ; la satisfaction métier exige d'autres preuves.

Alternative : Roslyn comme runtime obligatoire rejeté pour les produits non .NET.

Oracle indépendant : Lien orphelin, cycle ou fausse preuve Passed doit faire échouer le contrôle approprié.

**SOLID / DRY / MODULAR :** DIP sur le modèle d'échange ; ISP entre vérification documentaire et produit ; DRY des AC ; fonctions séparées parsing/contrôle/rendu.

Entrée : Besoin, identité et source des contrats connus.

Sortie : Structure et graphes contrôlés ; propriétaires, contrats et preuves demeurent des gates distinctes.

Risque : Cent pour cent de liens n'implique ni tests exécutés ni besoin métier valide.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
