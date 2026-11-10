# Dogfooding — la factory comme produit et premier consommateur

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Faire exercer à la factory ses propres capacités sur son cycle complet, avec des preuves indépendantes de ce qu’elle génère.

Dépendances : RaC et G0 dès le départ ; GP/REG et adaptateurs ensuite, sans tout imposer à G0.

Origine : plan Claude demande du 10 novembre 2026 et §3 G.7. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Bootstrap par étapes ; mêmes interfaces producteur/consommateur ; tests contractuels indépendants. Aucun raccourci privé pour soi-même.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Version N de la factory génère sa structure candidate N+1 à partir d’une description versionnée ; pas de génération récursive à chaque build. Le kit minimal initial est possédé et documenté ; après extraction, chaque capacité possède une seule implémentation. Préserver oracle/fixtures externes au templating.

### impl

Construire/packager N ; installer N depuis artefacts isolés ; générer une instance candidate ; vérifier et appliquer explicitement ; construire/packager N+1 ; exécuter les mêmes scénarios pour Generator, GP, REG et deux témoins produit. Ajouter/mettre à jour/déprécier une opération avec façades/docs/exigences.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Régénération sémantique et idempotence, upgrades N→N+1, profil inconnu, conflits humains, interruption, reprise sans double effet, rollback des seules écritures locales réversibles ; package absent, caches vides et source sœur inaccessible. Muter le générateur et vérifier qu’un oracle indépendant détecte la régression.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Matrice capability × consumer × version × platform × kind avec source, environnement et artefacts. Aucun badge Dogfooded fondé sur un build unique ou sur ses propres assertions générées.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$plan = New-EcosystemPlan -Name $factoryIdentity -Path $candidatePath -Profiles $pinnedProfiles
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**DOG** — qualification — Témoin dès G0, qualification étendue après i3.

Faire produire une candidate N+1 par N avec les mêmes contrats publics et un oracle indépendant.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Protocole N/candidate N+1, fermeture des artefacts et indépendance de l'oracle |
| impl | Fixtures consommatrices et commandes de préparation candidate, sans activation implicite |
| test | Témoin G0 puis upgrades, conflits, pannes, caches vides et mutants du générateur |
| obs | Matrice capacité/consommateur/version/plateforme/kind et reçus de qualification |

Traçabilité : DOG-001, DOG-002, DOG-003, DOG-004. Lots : DOG0, DOG1. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| DOG-001 | La factory consomme ses mêmes interfaces et artefacts publics pour se régénérer. | DOG-001-AC1 → DOG-001-T1 (integration, NotRun) |
| DOG-002 | Le dogfooding est qualifié par un oracle indépendant du générateur. | DOG-002-AC1 → DOG-002-T1 (mutation, NotRun) |
| DOG-003 | Une mise à jour défaillante est bornée et ne supprime pas les données humaines. | DOG-003-AC1 → DOG-003-T1 (fault, NotRun) |
| DOG-004 | La couverture de factory distingue chaque consommateur et chaque kind. | DOG-004-AC1 → DOG-004-T1 (contract, NotRun) |

**Décision de patterns : Staged bootstrap + independent acceptance oracle.**

Contexte : La factory produit et utilise ses propres outils.

Problème : Une boucle d'auto-validation peut certifier la même erreur recopiée.

Forces : Auto-hébergement, indépendance et récupération locale.

Participants : N est figé ; candidate est isolée ; oracle externe juge ; opérateur décide activation.

Collaboration : Construire N, installer son artefact, générer N+1 puis vérifier sans génération récursive.

Conséquences : Feedback à la révision suivante seulement ; pas de cycle bloquant dans une même révision.

Alternative : Build appelant le générateur encore en construction ou tests auto-approuvés rejetés.

Oracle indépendant : Un défaut injecté dans le template est détecté par une assertion non issue de ce template.

**SOLID / DRY / MODULAR :** DIP vers contrats publics ; DRY de l'implémentation ; séparation producteur/oracle ; pas de voie privée pour soi-même.

Entrée : G0 pour DOG0 ; i3/G2/REG/ADP pour DOG1.

Sortie : Preuves par consommateur et kind ; succès d'un build unique insuffisant.

Risque : L'oracle peut dépendre involontairement des mêmes données générées.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| DOG0 | New-GeneratorWitness → Test-GeneratorWitness | Evidence | HOST0, GP0, I3SEED | fixture-DOG0 | Proposed |
| DOG1 | Invoke-FactoryGenerationWitness → Test-FactoryGenerationWitness | Evidence |  | factory-candidate | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
