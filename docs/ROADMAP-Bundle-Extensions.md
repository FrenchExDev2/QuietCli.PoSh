# Extensions — Packer.Bundle et adaptateur Vagrant

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Préparer deux reprises distinctes à partir des capacités communes validées, sans imposer un pattern par analogie.

Dépendances : FND/REG ; CORE avant toute migration de la voie d’exécution Vagrant.

Origine : plan Claude §11 M.6. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Packer : modèle/génération/Builder ; Vagrant : parsing métier et adaptateur d’exécution. La séparation de dépôts dépend des responsabilités/versionnements, pas du nombre de consommateurs seul.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Packer reste un format distinct avec ses schémas/évolution et tests. Vagrant distingue typage des arguments, parsing et lancement : consommer ses parseurs ne doit pas contourner le lanceur injecté QuietCli. Vérifier le contrat machine-readable et versions supportées avant d’annoncer Ready.

### impl

Produire des plans propres Packer et Vagrant avant migration réelle ; réutiliser profils et émetteurs, pas les modèles Compose. Adapter le companion Vagrant à une bibliothèque métier sans introduire un deuxième lancement de processus.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Corpus réels versionnés et fixtures indépendantes pour Vagrant, parsing partiel/erreurs/Unicode ; property/fuzz/mutation des parseurs. Packer : compatibilité des schémas et code généré depuis paquets.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Versions de binaire/format, couverture des variantes, transport et identité du seul exécuteur. Parsing partiel demeure incomplet.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$route = Resolve-QuietPipeline -Call $vagrantCall -Explain
$route
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**EXT** — product — Deux extensions à découper selon leur besoin réel.

Livrer des contrats propres Packer et Vagrant en réemployant seulement les mécanismes communs.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Deux fiches de livraison : schéma/génération Packer et typage/parsing/exécution Vagrant |
| impl | Paquets et adaptateurs distincts ; parseur Vagrant partagé, exécuteur QuietCli unique injecté |
| test | Corpus versionné Vagrant, parsing partiel/Unicode, fuzz/mutations ; génération Packer depuis paquets |
| obs | Binaire/format/version, couverture des variantes et identité du seul exécuteur |

Traçabilité : EXT-001, EXT-002. Lots : EXT. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| EXT-001 | Le partage des parseurs Vagrant conserve une seule voie d’exécution injectable. | EXT-001-AC1 → EXT-001-T1 (integration, NotRun) |
| EXT-002 | Packer réutilise le mécanisme de génération sans adopter le modèle Compose. | EXT-002-AC1 → EXT-002-T1 (integration, NotRun) |

**Décision de patterns : Adapter + separated model and execution.**

Contexte : Deux outils partagent certains mécanismes mais pas leurs formats.

Problème : Le réemploi par analogie peut forcer un mauvais modèle ou doubler le lancement natif.

Forces : Évolution indépendante et préservation du lanceur injecté.

Participants : Modèle Packer possède son schéma ; parseur Vagrant interprète ; QuietCli lance une seule fois.

Collaboration : Les bibliothèques métier consomment la sortie existante sans relancer la CLI.

Conséquences : Déclarations de versions/platformes supportées propres à chaque outil.

Alternative : Wrapper .NET relançant Vagrant pour parser son résultat rejeté.

Oracle indépendant : Une invocation métier correspond à un seul lancement observé ; parsing partiel reste incomplet.

**SOLID / DRY / MODULAR :** SRP modèle/parsing/lancement ; ISP par format ; DRY des émetteurs justifiés ; séparation des modèles Compose/Packer.

Entrée : FND et CORE requis par la reprise concernée ; découper les lots si une dépendance ne concerne qu'un outil.

Sortie : Chaque extension a son artefact et ses preuves ; pas de qualification déduite de Compose.

Risque : Le graphe agrégé EXT est conservateur ; il devra être raffiné en Packer/Vagrant avant exécution.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
