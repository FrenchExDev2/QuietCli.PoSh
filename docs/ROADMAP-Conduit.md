# Conduit — adaptateur IEC/QuietCli

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Livrer **l'écosystème Conduit**, objectif final FrenchExDev2 : rendre IEC61499 utilisable depuis PowerShell et C#, en encapsulant QuietCli (prononcé Quietly) et en consommant les composants bas niveau indépendants, sans recréer leur moteur ou scheduler. La qualification IEC reste limitée aux fonctions/clauses effectivement documentées et vérifiées.

Dépendances : IEC et QuietCli existant pour une fixture ; nouvel ordonnanceur CORE pour la concurrence promise. M facultatif pour qualifier un transport externe.

Origine : plan Claude §10 Plan C. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Adapter ; Observer ; scope d’abonnement explicite.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Bindings source → événement IEC avec mapping de données ; fonctions/cmdlets réutilisables. Fichiers .conduit.ps1 explicitement sélectionnés sont du code, pas des données sûres. Ni faux binaire iec61499 ni import automatique.

### impl

Créer abonnement et scope de connexion avec désabonnement/disposal ; employer les commandes de chaque domaine. Commencer par un producteur fixture supporté ; vm.ready et Schedule restent conditionnés à CORE.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Deux producteurs interchangeables, mapping de payload, erreurs, fermeture, annulation et boucle de traduction. Propriétés conservation de corrélation/isolation ; fuzz bindings/séquences ; mutants des mappings.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Corrélation source/réseau/bloc, états de connexion et nombre d’abonnements propres. Aucun collecteur événementiel illimité implicite.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$connection = Connect-Conduit -Source $fixtureSource -Network $network -Bindings $bindings
try { Invoke-ConduitFixture -Source $fixtureSource } finally { Disconnect-Conduit -Connection $connection }
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

## Recette finale et livraison locale

CON0 livre une fixture depuis IEC et QuietCli existant figé. CON livre la composition concurrente après CORE et i3 accepté. Les contrats neutres Result/FSM/IEC ne dépendent ni du Manager ni de Conduit ; Conduit porte l'adaptation QuietCli. Builder et Requirements sont qualifiés dans la fermeture de livraison lorsque retenus, sans être imposés comme imports runtime universels.

Le workspace personnel i3 crée le conteneur source Conduit via son placement par kind, puis ses moyens packagent/publient vers feeds locaux NuGet/PSResource. La recette froide installe les artefacts exacts sans sources i2 ni workflows distants et exerce le même scénario événement/données depuis PS puis C#. Elle vérifie ordre données→événement, erreurs/refus, annulation/disposal, corrélation, boucles bornées et libération d'abonnements. Les preuves sont séparées par langage et mode dynamique/généré. ConduitAccepted requiert ces résultats réels ; ni i3 installé ni une fixture isolée ne suffisent.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**CON** — product — Objectif final FrenchExDev2.

Livrer l'écosystème Conduit : implémentation IEC61499 PowerShell/C# composée de briques bas niveau et encapsulant QuietCli.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Contrats de bindings, mapping des payloads, ownership des abonnements et limites de boucle |
| impl | Commandes Connect/Disconnect et scope de connexion ; fixture puis intégration concurrente |
| test | Producteurs interchangeables, mapping, annulation, propriétés corrélation et mutants de désabonnement |
| obs | Corrélation source/réseau/bloc et compte borné d'abonnements possédés |

Traçabilité : CON-003, CON-001, CON-002. Lots : CON0, CON. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| CON-003 | La recette finale FrenchExDev2 livre Conduit IEC61499 PowerShell/C# encapsulant QuietCli depuis des paquets locaux indépendants. | CON-003-AC1 → CON-003-T1 (integration, NotRun) |
| CON-001 | Conduit traduit sans rendre IEC et QuietCli interdépendants. | CON-001-AC1 → CON-001-T1 (contract, NotRun) |
| CON-002 | Chaque connexion libère ses abonnements sur toutes les issues. | CON-002-AC1 → CON-002-T1 (fault, NotRun) |

**Décision de patterns : Adapter + Observer + scoped subscription.**

Contexte : Deux domaines indépendants doivent échanger des événements.

Problème : Un bridge peut rendre les domaines interdépendants ou conserver des abonnements après arrêt.

Forces : Mapping explicite, erreurs et ownership du cycle de vie.

Participants : Binding mappe ; connexion possède abonnements ; domaines possèdent leurs moteurs.

Collaboration : Conduit appelle les ports publics et se désabonne sur toutes les issues.

Conséquences : Aucun runtime IEC→QuietCli ou retour ; fichiers .conduit.ps1 sélectionnés restent du code.

Alternative : Faux binaire IEC ou ordonnanceur supplémentaire rejetés.

Oracle indépendant : Déconnexion, échec et annulation ne laissent aucun abonnement ; corrélation conservée.

**SOLID / DRY / MODULAR :** SRP de traduction ; DIP vers ports domaines ; DRY du scheduling chez Core ; scope modulaire de connexion.

Entrée : CON0 consomme IEC et QuietCli figé ; CON exige aussi CORE, i3, Builder et Requirements qualifiés.

Sortie : ConduitAccepted démontre les ports PS/C#, IEC et QuietCli encapsulé depuis les paquets locaux ; aucune certification IEC implicite.

Risque : Une boucle de traduction peut réinjecter indéfiniment un événement.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| CON0 | New-ConduitPreviewPackage → Test-ConduitFixture | LocalBoth | CON | source-Conduit | Proposed |
| CON | Invoke-ConduitAcceptance → Test-ConduitAcceptance | Evidence |  | source-Conduit, conduit-acceptance | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
