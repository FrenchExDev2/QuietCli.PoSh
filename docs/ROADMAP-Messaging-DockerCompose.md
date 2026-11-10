# DockerCompose.Bundle — messagerie de développement

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Réutiliser le Bundle typé avec contributeurs RabbitMQ/NATS et façade PowerShell compatible.

Dépendances : FND Result/Builder réellement nécessaires et REG ; profil GEN pour le dépôt mixte. Pas de dépendance runtime Core à Compose.

Origine : plan Claude §11 M.1–M.5/M.7. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Contributor/Strategy ; Builder existant ; facade et adaptateur de compatibilité du DSL PowerShell.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Un dépôt mixte peut publier plusieurs paquets indépendamment déclarés : .Ecosystem n’est pas un paquet agrégat présumé. Conserver schémas versionnés et acquisition Design manuelle séparée du build. Ne pas valider contre un schéma distant mouvant. Conserver Services/Volumes/Networks/File existants dans l’adaptateur avant une éventuelle nouvelle API.

### impl

Migrer Bundle, attributs et générateurs avec leur provenance ; implémenter contributeurs et fonctions PowerShell déléguées. Ports dev explicitement bindés sur 127.0.0.1 par défaut, credentials de développement explicitement choisis, images épinglées lors d’implémentation. config/up/down sont des opérations distinctes ; nettoyer seulement les ressources possédées.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Compatibilité appels existants, compose config sur version supportée, service prêt et handshake protocolaire séparés, redelivery/ack selon adaptateur. Property/fuzz schema/contributeurs, mutants ports/ownership. campagnes de services explicites et bornées.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Recette/version/digests, IDs projet Compose/conteneurs/volumes possédés, disponibilité broker et diagnostics ; un conteneur Running n’est pas un broker Ready. Sorties bornées et credentials absents des preuves.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$plan = New-MessagingEnvironmentPlan -Provider 'Nats' -Path $outputPath -BindAddress '127.0.0.1'
Show-EcosystemPlan -Plan $plan
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**MSG** — product — Infrastructure optionnelle de développement.

Produire un Bundle Compose typé et un profil messaging local dont la disponibilité est réellement vérifiée.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Contrats Bundle/DSL compatible, schémas/images versionnés et lifecycle config/up/handshake/down |
| impl | Paquets Bundle/générateurs, contributeurs RabbitMQ/NATS et façade PS conservant les paramètres existants |
| test | Compatibilité DSL, compose config, handshake distinct, fuzz schéma/contributeurs et mutants ports/ownership |
| obs | Digests, identités Compose/conteneurs, disponibilité broker et nettoyage possédé |

Traçabilité : MSG-001, MSG-002, MSG-003, MSG-004. Lots : MSG. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| MSG-001 | La migration préserve les paramètres publics consommés du DSL PowerShell. | MSG-001-AC1 → MSG-001-T1 (contract, NotRun) |
| MSG-002 | Le profil dev-localhost ne publie aucun port sur toutes les interfaces par défaut. | MSG-002-AC1 → MSG-002-T1 (contract, NotRun) |
| MSG-003 | Provisionner un broker reste facultatif et extérieur aux runtimes. | MSG-003-AC1 → MSG-003-T1 (integration, NotRun) |
| MSG-004 | Les identités de publication utilisent un fournisseur réellement supporté par chaque cible. | MSG-004-AC1 → MSG-004-T1 (contract, NotRun) |

**Décision de patterns : Builder + Contributor/Strategy + compatibility Facade.**

Contexte : Un modèle typé produit Compose et doit préserver le DSL PowerShell.

Problème : La migration peut perdre des paramètres ou exposer des ports sur toutes les interfaces.

Forces : Compatibilité, schema figé et infrastructure facultative.

Participants : Builder existant construit ; contributeur configure ; façade adapte ; runner possède les ressources.

Collaboration : Générer/valider, démarrer, faire handshake puis arrêter sont des opérations distinctes.

Conséquences : Bind loopback explicite ; aucun broker requis par Core ou Manager local.

Alternative : Un modèle générique Compose/Packer/Vagrant unique et forcé rejeté.

Oracle indépendant : Services/Volumes/Networks/File restent compatibles ; aucun port public par défaut ; Running ne suffit pas à Ready.

**SOLID / DRY / MODULAR :** OCP des contributeurs ; LSP de la façade compatible ; DRY du Builder ; séparation génération/provisionnement/transport.

Entrée : FND/G2 et schémas/images/versions CLI identifiés.

Sortie : Configuration et handshake qualifiés séparément ; support de publication établi par fournisseur.

Risque : Une image démarrée peut être inaccessible ou non prête ; aucun OIDC Gallery présumé.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
