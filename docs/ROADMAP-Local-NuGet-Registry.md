# Local NuGet Registry — artefacts et configurations par instance

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Publier et restaurer des .nupkg identifiés, sans accès source voisin et sans configuration globale implicite.

Dépendances : G0/G1 et GP pour la structure ; fournisseur FileSystem initial. Le manager de registry n’est pas requis pour générer sa propre structure.

Origine : plan Claude §6 R.1–R.3. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Ports/Adapters de registry ; Strategy de configuration ; résultat d’opération structuré.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Registre nommé et instance consommatrice distincts ; filesystem hiérarchique initial, HTTP optionnel. Config complète explicitement choisie par les wrappers restore ; sources/mappings et CPM propres ; pas d’overlay NuGet inventé. PSResource et npm ont leurs contrats séparés.

### impl

New/Get/Register-LocalNuGetRegistry, Publish-LocalNuGetPackage, Set-EcosystemNuGetSource et Test-EcosystemNuGetSource réutilisables avec façades/docs. Publish reçoit des paquets déjà produits. Installation et réseau toujours explicites. Atomicité de publication, concurrence et interruption à définir avant réalisation.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Deux registries et deux instances, cache vierge, version absente, publication simultanée, package incomplet, hash conflict et permissions refusées. Propriétés immutabilité/idempotence, fuzz noms/config/nupkg malformés, mutants de mapping et hash.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

États Produced/Accepted/Restored séparés avec ID/version/hash/source ; auth par référence sans valeur secrète ; Unknown si vérification incomplète.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$registry = New-LocalNuGetRegistry -Name 'Dev' -Path $feedPath -WhatIf
Test-EcosystemNuGetSource -InstancePath $instancePath -ConfigFile 'NuGet.local.config'
```

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**REG** — product — Feed NuGet local requis après i3 seed et avant i3 accepté.

Publier/restaurer des paquets .NET immuables avec configuration explicite par instance.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Contrats fournisseur, atomicité, ID/version/hash et sources/mappings NuGet |
| impl | Paquet Registry avec provider filesystem, publication et restauration explicites ; PS/npm distincts |
| test | Cache vierge, publication interrompue/concurrente, hash conflict et fuzz packages/config |
| obs | Reçus Produced/Accepted/Restored avec ID/version/hash/source et lacunes |

Traçabilité : REG-001, REG-002, REG-003. Lots : REG. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| REG-001 | ID/version de paquet est immuable et une publication interrompue ne devient pas restaurable. | REG-001-AC1 → REG-001-T1 (fault, NotRun) |
| REG-002 | Une instance restaure ses dépendances depuis les artefacts déclarés sans checkout frère. | REG-002-AC1 → REG-002-T1 (integration, NotRun) |
| REG-003 | Configurer une instance n’altère pas les configurations utilisateur/globales. | REG-003-AC1 → REG-003-T1 (contract, NotRun) |

**Décision de patterns : Ports/Adapters + immutable artifact repository.**

Contexte : Les écosystèmes .NET se consomment sans sources voisines.

Problème : Le registre ne doit ni s'auto-exiger au bootstrap ni altérer la config globale.

Forces : Immutabilité, concurrence et sources strictement choisies.

Participants : Publisher valide ; store possède promotion atomique ; config resolver choisit le feed ; client restaure.

Collaboration : Un paquet déjà construit est accepté puis restauré par un consommateur isolé.

Conséquences : Un feed sur disque suffit au premier parcours .NET ; il n'est pas le mécanisme B0 des modules PS.

Alternative : Registre HTTP/conteneur obligatoire dès G0 rejeté pour son coût d'amorçage.

Oracle indépendant : Un paquet incomplet n'est jamais restaurable ; config utilisateur inchangée et conflit de hash refusé.

**SOLID / DRY / MODULAR :** ISP par fournisseur réel ; DIP vers store/config ; DRY de l'identité d'artefact ; séparation NuGet/PSResource/npm.

Entrée : I3SEED fournit le répertoire de développement et les moyens d'amorçage ; aucune dépendance retour SMREG.

Sortie : Publication draft1/dev1 et restore isolés qualifiés ; aucun support PSResource déduit du seul test NuGet.

Risque : Un cache chaud masque un paquet manquant ou un mauvais mapping.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| REG | Publish-LocalNuGetPackage → Test-LocalNuGetRoundtrip | LocalNuGet | SMREG, ADP, RESULT, RACPKG, IEC, CORE, DOG1 | nuget-feed-publication | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
