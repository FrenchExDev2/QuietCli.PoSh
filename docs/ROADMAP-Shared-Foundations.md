# Fondations partagées — Result, Builder et adaptateurs RaC

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Planifier une seule reprise de chaque fondation requise au lieu de la cacher dans les consommateurs.

Dépendances : REG pour le parcours .NET ; GEN/GP pour chaque dépôt cible. Vérifier le graphe réel avant d’ordonner Result, Builder et Requirements.

Origine : plan Claude §8, §11 M.1/M.6, §12 et §16. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Dependency inversion ; source generator en deux étapes ; séparation extracteur Roslyn/émetteur neutre.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Inventorier les Package/ProjectReference et contrats de Result, Builder, Builder.SourceGenerator.Lib, Requirements et leurs générateurs/tests. Le plan Claude suppose Builder publié pour FSM sans démontrer le lien : ne l’imposer qu’aux consommateurs qui en ont besoin. Rechercher les capacités Requirements-As-Code.PoSh/Requirements.ts avant de choisir les adaptateurs ; leur existence citée par Claude n’est pas ici une qualification.

### impl

Définir pour chaque fondation identité, propriétaire, cibles, dépendances packagées, compatibilité, build/pack et source de distribution. Le bootstrap JSON des exigences ne requiert pas immédiatement la migration de toute la DSL .NET. Ne pas écrire un nouvel émetteur Builder pour Bundle.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Restauration avec caches et checkouts isolés, tests existants de comportement/génération/analyzer, dépendances analyzers emballées et réellement chargées. Property/fuzz/mutation ciblés, non remplacés par compilation seule.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Table de disponibilité par ID/version/TFM/source, statut produit/accepté/installé/qualifié. Les anciens chemins restent la référence jusqu’à une reprise validée.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$report = Test-EcosystemDependencyClosure -EcosystemPath $root -IsolatedCachePath $cachePath
$report.Gaps
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**FND** — product — Fondations des domaines .NET sélectionnés.

Livrer une seule reprise packagée de chaque fondation réellement nécessaire.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Fermeture de Package/ProjectReference, cibles et séparation extracteur/émetteur |
| impl | Paquets Result/Builder/Requirements nécessaires, y compris dépendances de générateurs/analyzers |
| test | Consommation depuis paquets seuls, code généré et tests existants, propriétés/fuzz/mutations ciblés |
| obs | Disponibilité ID/version/TFM/source et diagnostics des dépendances manquantes |

Traçabilité : FND-001, FND-002. Lots : FND. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| FND-001 | Chaque fondation requise dispose d’un paquet autonome avant la bascule de son consommateur. | FND-001-AC1 → FND-001-T1 (integration, NotRun) |
| FND-002 | La génération réutilise les émetteurs existants et leur packaging est qualifié. | FND-002-AC1 → FND-002-T1 (integration, NotRun) |

**Décision de patterns : Layers + dependency inversion + two-stage generator.**

Contexte : Les domaines réutilisent des fondations existantes et des générateurs.

Problème : Des copies locales ou dépendances supposées créent des cycles et doubles émetteurs.

Forces : Compatibilité binaire, packaging des analyzers et fermeture réelle.

Participants : Extracteur lit les symboles ; modèle neutre décrit ; émetteur partagé génère ; consommateur fixe ses versions.

Collaboration : L'inventaire décide quels producteurs précèdent chaque consommateur.

Conséquences : Builder n'est requis par FSM que si un lien réel le démontre.

Alternative : Réécrire Builder pour chaque Bundle ou migrer toute la DSL avant G0 rejeté.

Oracle indépendant : Génération et chargement des analyzers réussissent sans bin/source sœur dans un cache vierge.

**SOLID / DRY / MODULAR :** DIP vers modèle neutre ; DRY des émetteurs ; SRP extraction/émission ; un paquet par responsabilité/versionnement justifié.

Entrée : REG/G2 et inventaire de dépendances réelles.

Sortie : Paquets requis disponibles avant bascule du consommateur ; graphes build/runtime vérifiés séparément.

Risque : Un .nupkg présent peut omettre les dépendances nécessaires à un analyzer.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
