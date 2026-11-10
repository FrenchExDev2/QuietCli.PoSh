# FiniteStateMachine — reprise autonome

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Préserver les comportements Dynamic/Typed/Rich et les générateurs en consommation packagée.

Dépendances : FND Result réellement requis et REG ; autres dépendances à confirmer par fermeture de graphe.

Origine : plan Claude §8 Plan A. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

State ; Strategy de concurrence ; Result pour les refus documentés.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Préserver les cibles existantes tant qu’un changement n’est pas justifié ; mapping namespace/package explicite. Le défaut inspecté est ConcurrencyMode.None ; la démo choisit Semaphore. Ne pas étendre un refus de transition Result à une promesse universelle d’absence d’exceptions.

### impl

Migrer dans son dépôt autonome ; ProjectReference seulement interne ; publier runtime/attributs/générateurs nécessaires via REG. Conserver les compagnons de tests et les séparer du métier.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Transitions permises/interdites, annulation, modes de concurrence et code Typed/Rich généré. Générateurs de graphes/événements, fuzz séquences invalides, mutants guards/transitions. Comparaison avec comportements legacy.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Identité du modèle/version et résultat de transition, état terminal et annulation ; traces bornées, pas d’historique illimité automatique.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$report = Test-EcosystemDependencyClosure -EcosystemPath $fsmRoot -IsolatedCachePath $cachePath
$report.Gaps
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**FSM** — product — Domaine indépendant du Manager local.

Préserver Dynamic/Typed/Rich et leurs générateurs dans un écosystème autonome.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Contrats transitions/refus/concurrence et mapping d'identités/cibles |
| impl | Paquets runtime/attributs/générateurs nécessaires et compagnons séparés |
| test | Graphes/événements générés, équivalence legacy, séquences invalides et mutants guards/transitions |
| obs | Résultats de transition, modèle/version, annulation et traces bornées |

Traçabilité : FSM-001, FSM-002. Lots : FSM. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| FSM-001 | La reprise préserve les transitions et les choix de concurrence explicites. | FSM-001-AC1 → FSM-001-T1 (property, NotRun) |
| FSM-002 | Typed et Rich se génèrent depuis les paquets seuls. | FSM-002-AC1 → FSM-002-T1 (integration, NotRun) |

**Décision de patterns : State + Strategy concurrency + Result.**

Contexte : Le même modèle existe en modes dynamique et typés générés.

Problème : La reprise peut changer transitions ou mode de concurrence par défaut.

Forces : Compatibilité, refus explicites et isolation des états.

Participants : Modèle définit transitions ; guard autorise ; stratégie synchronise ; générateur matérialise les modes typés.

Collaboration : Comparer les modes sur les mêmes séquences indépendantes.

Conséquences : ConcurrencyMode.None reste le défaut ; Semaphore doit être demandé explicitement.

Alternative : Un moteur universel de workflow pour le Manager rejeté : besoin non démontré.

Oracle indépendant : Les traces de transitions valides et refusées sont équivalentes entre modes sur les propriétés retenues.

**SOLID / DRY / MODULAR :** OCP des stratégies ; LSP des modes sur leurs invariants communs ; DRY des règles de transition ; pas de dépendance Manager.

Entrée : Fondations réellement requises et paquets disponibles.

Sortie : Runtime et génération depuis paquets qualifiés ; refus Result ne promet pas absence universelle d'exceptions.

Risque : Les garanties de concurrence ne sont pas interchangeables entre modes.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
