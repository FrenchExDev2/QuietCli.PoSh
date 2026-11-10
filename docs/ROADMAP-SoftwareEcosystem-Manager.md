# SoftwareEcosystem.Manager — catalogues, clones et instances

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Découvrir et gérer plusieurs instances d’écosystèmes sans modifier silencieusement le travail local.

Dépendances de **SM0 local** : GP packagé pour les opérations mono-dépôt et HOST packagé pour workspace/instances/placements. SM0 orchestre leurs fonctions sans Generator runtime obligatoire ; les plans Generator deviennent un adaptateur optionnel ultérieur. **SM1** ajoute catalogue distant et synchronisation via un adaptateur hosting. HOST ne dépend pas de Manager.

Le premier résultat est la gestion locale depuis [FrenchExDev_i3](ROADMAP-Delivery-FrenchExDev-i3.md) : enregistrement, liste, inspection, preview/apply et reçu par opération, sans réseau. La découverte distante ne bloque pas ce lot. Le checkout de développement du Manager est une instance enregistrée ; son paquet installé reste distinct de ses sources. SM-004 porte ce contrat local ; SM-001..003 conservent discovery, préservation et isolation.

Origine : plan Claude §5 SM.1–SM.7. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Ports/Adapters hosting/configuration ; Strategy de sélection ; composition d’opérations mono-dépôt.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Séparer catalogue d’organisation, manifeste d’un écosystème, workspace et registre local d’instances. GitHub ne garantit pas à lui seul la présence d’un catalogue de projets. Fixer précédence paramètres > configuration choisie > défauts ; .env chargé explicitement comme données. Pagination, droits partiels, repos renommés/archivés et absence réseau ont des états propres.

### impl

Get-SoftwareEcosystemCatalog, New-SoftwareEcosystemClonePlan, Sync-SoftwareEcosystemClone et reporting délèguent à GP ; fetch lecture distante et pull mutation locale sont séparés. Un clone n’est pas requis pour consommer un paquet publié.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Doubles paginés, dépôts jetables locaux, clones interrompus, destination déjà occupée, wrong remote, répertoire dirty, divergence, autorisations partielles et deux opérations concurrentes sur une instance. Property filtering/idempotence, fuzz config/path, mutants d’isolation.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Rapport par workspace/repo/instance et opérations individuelles. Un remote inaccessible est Unknown, jamais absent confirmé ; une branche feature intentionnelle est distinguée d’une dérive de politique.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$catalog = Get-SoftwareEcosystemCatalog -Workspace $workspace -Profile 'PoSh'
$plan = New-SoftwareEcosystemClonePlan -Workspace $workspace -Catalog $catalog
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**SM** — product — SM0 local requis ; SM1 distant optionnel.

Permettre depuis i3 de gérer plusieurs instances locales sans dépendre d'un service distant.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Cas d'usage offline, identité dépôt/instance/déploiement, isolation et concurrence par instance |
| impl | Paquet Manager local composant HOST/GP ; discovery distante en adaptateur optionnel ; façades/docs |
| test | Deux instances, absence réseau, clone local interrompu, dirty/collision/concurrence et propriétés d'isolation |
| obs | Catalogue consultable, diagnostic par instance et reçu d'opération ; distant inaccessible = Unknown |

Traçabilité : SM-004, SM-001, SM-002, SM-003. Lots : SM0, SM1. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| SM-004 | Le Manager minimal gère le catalogue et les opérations locales sans découverte distante ni Generator runtime obligatoire. | SM-004-AC1 → SM-004-T1 (integration, NotRun) |
| SM-001 | La découverte filtre et pagine sans fabriquer les métadonnées manquantes. | SM-001-AC1 → SM-001-T1 (integration, NotRun) |
| SM-002 | La synchronisation ne détruit aucun travail local et distingue fetch/pull. | SM-002-AC1 → SM-002-T1 (fault, NotRun) |
| SM-003 | Deux workspaces et deux instances sont isolés. | SM-003-AC1 → SM-003-T1 (property, NotRun) |

**Décision de patterns : Application service + Ports/Adapters + Strategy.**

Contexte : Un poste gère des dépôts et plusieurs clones de chacun.

Problème : Confondre catalogue distant, registre local et emplacement conduit à des mutations inattendues.

Forces : Mode hors réseau, préservation du travail et évolution du Manager lui-même.

Participants : Manager orchestre ; HOST résout/enregistre ; GP manipule le dépôt ; provider distant découvre.

Collaboration : SM0 compose les contrats HOST/GP ; SM1 ajoute un port distant sans modifier le catalogue local silencieusement.

Conséquences : SM0 ne dépend pas du générateur runtime ; auto-mise à jour en candidate séparée.

Alternative : Un orchestrateur global possédant placement, Git, publication et moteur natif rejeté.

Oracle indépendant : Deux instances gardent leurs chemins/états indépendants, y compris sans réseau et pendant une opération concurrente.

**SOLID / DRY / MODULAR :** SRP d'orchestration ; ISP offline/hosting distant ; DIP vers HOST/GP ; DRY de la politique Git et des placements.

Entrée : HOST0 et GP0 disponibles en artefacts compatibles, sans source sœur.

Sortie : SM0 utilisable depuis une session fraîche ; discovery GitHub n'est pas une gate de SM0.

Risque : Une auto-mise à jour en place peut casser l'outil nécessaire à sa propre récupération.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
