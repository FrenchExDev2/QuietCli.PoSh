# Adoption — QuietCli et GitHubEcosystem

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Valider les abstractions communes sur deux domaines réels sans effacer leurs contrats propres.

Dépendances : GEN/GP/REG ; SM seulement si de nouvelles instances sont nécessaires à l’adoption. Pas de clone imposé pour installer un paquet.

Origine : plan Claude §7 et critères des deux roadmaps existantes. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Adaptateur de compatibilité ; migration progressive ; réemploi versionné avec provenance.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Cartographier scripts réutilisables, contrats publics, licences, règles, workflows et écarts. QuietCli conserve son paquet QuietCli et sa matrice de qualification ; GitHub peut rester NotConfigured pour publication. Source de référence i2 préservée ; i3 est la cible demandée de livraison du Manager local. L'adoption complète des témoins reste une extension distincte de ce premier environnement ; cette passe planifie leur reprise.

### impl

Extraire fonctions/cmdlets puis réduire les scripts existants en façades. Remplacer la consommation source QuietCli de GitHub par un module packagé compatible, ajouter ses docs miroir et instructions consommateurs. Préserver -NoAll, ShouldProcess, plafonds et rapports.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Contrats avant/après, appel direct et script, WhatIf, import inerte, installation depuis paquets sans source sœur et matrice des consommateurs affectés. Fuzz/mutation ciblés sur les adaptations de politique.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Rapport par capacité : origine, version extraite, propriétaire, compatibilité, gaps et qualification. Aucun état Conforme à partir de la seule présence des fichiers.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$plan = New-EcosystemPlan -Mode Adopt -Path $existingCheckout -Profiles @('PowerShell', 'ScriptsAndDocs')
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**ADP** — product — Validation de réutilisation après le minimum i3.

Valider les abstractions communes sur QuietCli et GitHubEcosystem avec leurs vrais contrats.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Cartographie avant/après et contrats publics/identités à conserver |
| impl | Fonctions extraites et façades réduites, consommation depuis paquets et docs adaptées |
| test | Comparaisons contractuelles sur les deux témoins, caches isolés et mutations des adaptations |
| obs | Matrice capacité/consommateur/version, écarts et qualification réellement exécutée |

Traçabilité : ADP-001, ADP-002. Lots : ADP. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| ADP-001 | L’adoption conserve les contrats publics et identités installées. | ADP-001-AC1 → ADP-001-T1 (integration, NotRun) |
| ADP-002 | Les capacités communes restent utilisables hors du checkout QuietCli. | ADP-002-AC1 → ADP-002-T1 (integration, NotRun) |

**Décision de patterns : Compatibility Adapter + incremental adoption.**

Contexte : Deux domaines partagent du tooling mais pas toutes leurs politiques.

Problème : Une extraction peut généraliser une règle spécifique ou casser les consommateurs.

Forces : Compatibilité des scripts, packaging et autonomie des releases.

Participants : Socle fournit fonctions ; adaptateurs portent les politiques ; compagnons existants jugent le comportement.

Collaboration : Comparer les contrats avant/après depuis les artefacts installés.

Conséquences : QuietCli reste le paquet public QuietCli ; publication GitHub peut rester NotConfigured.

Alternative : Fusion des deux produits ou fork permanent du métier commun rejeté.

Oracle indépendant : Appel direct et façade préservent les mêmes sorties, WhatIf et snapshot -NoAll.

**SOLID / DRY / MODULAR :** LSP sur les façades ; ISP des politiques ; DRY après preuve d'un invariant commun ; modules et releases séparés.

Entrée : G2 et REG disponibles ; identités publiques conservées.

Sortie : Deux témoins qualifiés sans checkout frère ; leurs matrices propres restent applicables.

Risque : Un témoin unique ne démontre pas une abstraction réutilisable.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
