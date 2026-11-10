# FrenchExDev2.SoftwareContract — standard logiciel PowerShell/C#

Date : 10 novembre 2026. Nom validé par l'utilisateur ; contenu proposé, implémentation produit non qualifiée. Famille STD. Le [contrat de roadmapping](ROADMAP-Requirements-As-Code.md) et le [registre RaC](requirements/software-ecosystem-factory.requirements.json) s'appliquent.

## Résultat et périmètre

Définir ce qu'un logiciel doit déclarer et démontrer pour être créé, migré, livré et consommé dans FrenchExDev2. Le standard couvre fonctions/modules/scripts PowerShell et bibliothèques/cmdlets/outils C#. Un écosystème assemble des logiciels cohérents ; une instance est un checkout identifié ; i3 est le workspace personnel qui les héberge. Ces identités ont leurs propres configurations et versions.

Le standard ne dépend pas du Manager pour être lu ou vérifié : le kit seed est utilisable avant les registres. La validation d'une règle requiert un oracle indépendant du générateur qui l'a matérialisée. Les règles s'appliquent par profil, avec écarts explicites ; aucune conformité ISO ou IEC globale n'est déduite du passage d'une gate documentaire.

## Contrat logiciel

Chaque logiciel déclare identité, propriétaire, responsabilité, API publique, langages, plateformes/TFM/RID, dépendances runtime/build/test/génération, sources/packages/versions, configuration, erreurs, compatibilité et lifecycle. Les tests vivent dans leurs compagnons. Les façades `.ps1` délèguent à des fonctions exportées/cmdlets ; parsing, politique, orchestration et infrastructure ont des responsabilités distinctes. SOLID/DRY/MODULAR se jugent sur ces contrats et leurs consommateurs ; les patterns POSA sont documentés avec contexte, forces et conséquences.

Les API async portent annulation, timeout et ownership/disposal. Les diagnostics sont bornés. Aide, docs des fonctions/types/paramètres et docs miroir des façades accompagnent la livraison. Les campagnes exemples/propriétés/fuzz/mutations sont séparées par langage ; leur sélection et les manques sont justifiés. Les conventions de moniteur et d'artefacts du dépôt restent applicables.

## Paramètres PowerShell : challenger chaque argument

Une fiche de paramètre relie : exigence/AC, type et nullabilité, Mandatory/parameter set/pipeline, domaine admissible, validation, défaut et précédence de configuration, complétion, effets, sortie et erreurs.

| Cas | Décision et vérification |
| --- | --- |
| Domaine fermé stable | Enum ou ValidateSet explicite, casse et compatibilité documentées ; tests de toutes les valeurs et des inconnues |
| Domaine extensible configuré | Validation à l'exécution contre un snapshot identifié ; pas de ValidateSet statique qui figerait les plugins/profils |
| Complétion dynamique | Suggestion en lecture seule ; aucune installation, réseau, modification ou autorisation implicite ; revalidation au moment d'appliquer |
| Chemin | Type et existence selon l'opération, canonicalisation, ownership, collisions, liens et containment ; pas de validation par simple préfixe |
| Identifiant/version | Grammaire bornée, comparaison et compatibilité explicites ; sélectionner une version exacte avant effet |
| Bornes/timeout/taille | Unité, plage, défaut, annulation et valeurs limites observables ; pas de conversion silencieuse ambiguë |
| Secret/configuration | Référence de secret ; provenance et précédence explicites ; aucun secret dans les préférences Git ou rapports |

Une validation d'argument et une complétion ne sont pas une autorisation d'exécuter. Les champs configurés sont revérifiés si le plan ou la configuration a changé.

## ShouldProcess

Toute opération modifiante, exportée ou façade, expose `SupportsShouldProcess`, `-WhatIf` et `-Confirm`. Le propriétaire métier valide les préconditions pures puis appelle ShouldProcess avant **chaque effet** : fichiers, index/commit, registre client, conteneur, volume, publication, activation. La façade transmet les paramètres communs sans deuxième confirmation ni écriture préalable.

L'AC WhatIf utilise un état avant/après et des adaptateurs espions, y compris le refus de Confirm, les chemins d'erreur et les sous-opérations. L'absence d'écriture visible ne suffit pas : ni processus métier, réseau, hook, installation ou mutation de configuration. La simple lecture de diagnostic peut rester permise. Un mutateur retirant la garde doit être détecté.

## Lifecycle : les moyens livrent l'étape suivante

1. Identifier le logiciel et sa fermeture réelle avant de choisir son emplacement.
2. Disposer du workspace InstanceManager seed, déjà proche de la cible, puis résoudre le placement selon kind/langages/intérêts.
3. Préparer un **conteneur de développement**, répertoire source possédé, avec plan/preview/apply. Ce terme n'implique pas un conteneur OCI pour chaque logiciel.
4. Coder, qualifier, packager puis publier vers les feeds locaux, restaurer un consommateur isolé et recueillir ses preuves.
5. Autoriser les lots consommateurs avec l'identité exacte livrée ; ils utilisent ce paquet et non une source sœur. N actif prépare N+1 ; la candidate ne s'active pas pendant ses propres tests.

Identités initiales proposées : `0.0.1-draft1`, puis `0.0.1-dev1`. En C#, `PackageVersion` porte la chaîne complète. En PowerShell, `ModuleVersion='0.0.1'` et `PrivateData.PSData.Prerelease='draft1'` ou `'dev1'`. Les labels sont explicites : leur ordre lexicographique ne définit pas une promotion. Des previews de même version numérique PS doivent être installées dans des racines séparées. Les paquets existants, notamment QuietCli, conservent leurs identités et politiques tant qu'une migration distincte n'est pas décidée. [Versionnement PowerShell](https://learn.microsoft.com/en-us/powershell/gallery/concepts/module-prerelease-support?view=powershellget-3.x).

## Sortie et décisions

STD livre schéma/profils, validateur indépendant et générateurs ciblés. Chaque incrément couvre design/impl/test/obs ; nom accepté ne signifie pas contrats/API acceptés. Avant exécution produit : affecter propriétaire, figer version de schéma, commandes et budgets, puis qualifier un logiciel PS et un logiciel C# depuis leurs paquets. Le [plan exécutable de progression](requirements/software-ecosystem-factory.execution.json) définit producteurs/vérificateurs et ressources de STD ; les noms Proposed ne sont pas des commandes disponibles.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**STD** — contract — Nom FrenchExDev2.SoftwareContract validé par l'utilisateur.

Définir le standard logiciel PowerShell/C# vérifiable qui guide création, migration et consommation locale.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Schéma SoftwareContract, profils par kind, contrats de paramètres et dérogations explicites |
| impl | Validateur réutilisable et générateurs de structure avec WhatIf ; paquets preview installables |
| test | Compagnons indépendants : propriétés de contrats, fuzz paramètres/config/paths, mutations des refus et de ShouldProcess |
| obs | Rapport par règle et langage : Passed/Failed/Unknown, preuves, portée, version et dérogations datées |

Traçabilité : STD-001, STD-002, STD-003, STD-004, STD-005. Lots : STD. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| STD-001 | SoftwareContract définit les contrats et profils logiciels PowerShell/C# avec traçabilité RaC et séparation des responsabilités. | STD-001-AC1 → STD-001-T1 (contract, NotRun) |
| STD-002 | Chaque paramètre PowerShell justifie son type, domaine, validation statique ou configurée, défaut, portée, erreurs et complétion. | STD-002-AC1 → STD-002-T1 (fuzz, NotRun) |
| STD-003 | Toute opération modifiante possède SupportsShouldProcess et WhatIf sans écriture, réseau ni processus métier, y compris à travers une façade. | STD-003-AC1 → STD-003-T1 (mutation, NotRun) |
| STD-004 | Le logiciel est créé dans un conteneur de développement possédé résolu par kind et livré par paquet local preview immuable. | STD-004-AC1 → STD-004-T1 (integration, NotRun) |
| STD-005 | Chaque logiciel sépare code, tests compagnons, façades et infrastructures avec async, docs, lifecycle borné et qualification par langage. | STD-005-AC1 → STD-005-T1 (contract, NotRun) |

**Décision de patterns : Specification + Ports/Adapters + policy profiles.**

Contexte : Les logiciels PowerShell/C# ont des structures différentes mais des garanties communes.

Problème : Copier une structure ou imposer ValidateSet partout ne prouve pas le contrat observable.

Forces : Bootstrap minimal, extension par configuration, compatibilité et sécurité des mutations.

Participants : Schéma exprime ; profils spécialisent ; validateurs indépendants vérifient ; générateurs proposent.

Collaboration : Une règle est reliée à une exigence/AC et jugée par un oracle distinct du template.

Conséquences : Le nom accepté ne signifie pas que le standard ou son implémentation est déjà accepté.

Alternative : Une classe utilitaire universelle ou un dossier unique obligatoire pour tous rejetés.

Oracle indépendant : Un argument inconnu, un WhatIf modifiant ou un paquet sans fermeture rend la règle concernée Failed.

**SOLID / DRY / MODULAR :** SRP schéma/politique/validation/génération ; DIP sur contrats ; DRY des règles ; profils ciblés sans framework spéculatif.

Entrée : FAC et nom validé ; conventions existantes examinées.

Sortie : Règles et tests indépendants acceptés, versions figées et première consommation packagée.

Risque : Une inspection AST ne démontre pas l'absence de tous les effets runtime.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| STD | New-SoftwareContractPackage → Test-SoftwareContract | BootstrapArchive | G0, RESULT, RACPKG, IEC, CORE | source-STD | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
