# IEC61499 — modèle neutre, runtime et génération

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Faire converger exécution dynamique et génération C# sur un modèle neutre, avec contrats événement/données vérifiables.

Dépendances : FSM packagé, REG et fonctions de génération GEN. Aucune dépendance QuietCli.

Origine : plan Claude §9 B.1–B.4. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

State/ECC ; Ports/Adapters d’algorithmes ; génération à partir d’un modèle neutre partagé.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Parsing/validation sans Roslyn/PowerShell/QuietCli ; algorithme provider ouvert ; runspace possédé par l’adaptateur PS. Définir ordre ECC, association données/événements, boucles, saturation et version de schéma. Aucun niveau de conformité IEC présumé.

### impl

Importer YAML/TOML puis valider le même modèle ; runtime asynchrone ; générateur AdditionalFiles réutilisant ce modèle. Scripts d’algorithmes sont façades vers fonctions réutilisables quand ils portent une opération réemployable ; ne pas recopier la logique entre runtime dynamique et code généré.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

EI(A=2,B=3), Gain=2 donne Sum=10 puis EO. Équivalence dynamique/généré/YAML/TOML sur propriétés retenues ; fuzz graphes et documents malformés ; mutants de ports/ECC/émission ; annulation et limites de cycles.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

IDs réseau/bloc/événement et corrélation, ordre observé, résultat algorithme et erreurs ; aucun couplage à un format d’UI QuietCli.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$definition = Import-IecNetworkDefinition -Path ./Network.yaml
$network = Build-IecNetwork -Definition $definition
Invoke-IecEvent -Network $network -FunctionBlock 'add1' -Event 'EI' -Payload @{ A = 2; B = 3 }
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**IEC** — product — Domaine ultérieur, indépendant de QuietCli runtime.

Exécuter et générer le même modèle IEC neutre avec ordre événement/données vérifiable.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Modèle neutre, ECC, association données/événements, limites de cycles et contrats providers |
| impl | Import YAML/TOML, validation, runtime async et générateur AdditionalFiles partageant le modèle |
| test | Équivalence dynamique/généré, fixture Sum=10 puis EO, graphes malformés et mutants ports/ECC |
| obs | Corrélations réseau/bloc/événement, ordre observé et diagnostics bornés |

Traçabilité : IEC-001, IEC-002, IEC-003. Lots : IEC. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| IEC-001 | Les modes dynamique et généré préservent événement, données et ordre. | IEC-001-AC1 → IEC-001-T1 (property, NotRun) |
| IEC-002 | Les graphes invalides et cycles non bornés sont diagnostiqués sans bloquer le host. | IEC-002-AC1 → IEC-002-T1 (fuzz, NotRun) |
| IEC-003 | Le modèle et le runtime IEC ne dépendent pas de QuietCli. | IEC-003-AC1 → IEC-003-T1 (integration, NotRun) |

**Décision de patterns : State/ECC + Ports/Adapters + shared neutral model.**

Contexte : Runtime dynamique et C# généré lisent des définitions communes.

Problème : Deux interprétations séparées peuvent diverger sur l'ordre et les données.

Forces : Extensibilité des algorithmes, async et cycles bornés.

Participants : Importeur parse ; validateur construit le modèle ; runtime/générateur le consomment ; provider exécute l'algorithme.

Collaboration : Les adaptateurs PS/Roslyn restent aux frontières, hors modèle.

Conséquences : IEC n'importe pas QuietCli ; son éventuelle conformité à la norme exige une qualification distincte.

Alternative : Scripts PS dans le modèle ou émetteurs de règles dupliqués rejetés.

Oracle indépendant : EI(A=2,B=3), Gain=2 donne Sum=10 avant EO dans les deux modes ; cycles invalides terminent par diagnostic.

**SOLID / DRY / MODULAR :** SRP parsing/validation/exécution/émission ; DIP vers modèle neutre ; DRY des règles ; providers à interfaces ciblées.

Entrée : FSM/REG/STD et versions de schémas/providers déclarées ; G2 n'est pas un prérequis sans contrat démontré.

Sortie : Équivalence et bornes démontrées sur le scope déclaré ; aucune certification IEC implicite.

Risque : Une boucle d'événements valide syntaxiquement peut saturer le host.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| IEC | New-IecPreviewPackage → Test-IecPackageConsumer | LocalBoth | CON0 | source-IEC | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
