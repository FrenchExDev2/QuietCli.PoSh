# Registres PSResource locaux — répertoire puis localhost en conteneur

Date : 10 novembre 2026. Famille PSREG. Produit proposé ; les preuves exploratoires éventuelles ne remplacent pas sa qualification. Références : [SoftwareContract](ROADMAP-SoftwareContract.md), [NuGet](ROADMAP-Local-NuGet-Registry.md), [Manager](ROADMAP-SoftwareEcosystem-Manager.md), [i3](ROADMAP-Delivery-FrenchExDev-i3.md).

## Résultat et frontières

InstanceManager gère les chemins et cycles de vie des registres nécessaires aux logiciels produits sur le poste. Une « PSGallery locale » désigne ici un **dépôt privé compatible avec les clients PowerShell**, pas une instance du service public PSGallery. NuGet, PSResourceGet et PowerShellGet ont des compatibilités et limitations à vérifier séparément. Un serveur NuGet opérationnel ne prouve pas un round-trip PowerShell. [Compatibilités officielles PSResourceGet](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/supported-repositories?view=powershellget-3.x).

## PSREG0 : premier moyen local

Après I3SEED, créer un feed filesystem possédé, distinct du feed NuGet .NET. Publier un module témoin et une dépendance en `0.0.1-draft1`, puis des artefacts `0.0.1-dev1`. Retrouver et sauver chaque identité exacte avec `-Prerelease`, dans des racines séparées ; importer et vérifier un résultat fonctionnel. Isoler les registrations client et le cache, sélectionner explicitement le repository et préserver la configuration utilisateur initiale.

Les scripts livrés sont des façades de fonctions pack/publish/find/save/verify. Les sorties portent ID/version/hash/source/reçu. Publication interrompue et concurrence ne rendent pas visible un paquet partiel. Un conflit ID/version/hash est un refus, jamais un overwrite implicite. [API Publish-PSResource](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource?view=powershellget-3.x).

## PSREG1 : preuve localhost crossplatform

Choisir le provider après comparaison de ses protocoles, images/architectures, lifecycle et coûts. BaGet, Nexus ou un autre provider restent candidats ; la présence d'un ancien module Nexus n'est pas une preuve de support actuel. Le test doit utiliser un serveur réel dans une image identifiée, pas un faux endpoint construit pour faire passer l'assertion.

Le parcours CLI qualifie : inspecter runtime et digest ; démarrer avec port publié sur loopback et volume possédé ; attendre une vraie santé du feed ; publier module et dépendance preview ; rechercher, télécharger et importer depuis **PowerShell Windows puis PowerShell Linux** ; vérifier version/hash et fonction métier ; redémarrer et retrouver les paquets ; arrêter proprement avec diagnostics sauvegardés. Le client Linux n'utilise pas localhost pour désigner l'hôte depuis son propre conteneur : réseau/adresse sont explicitement résolus. Les plateformes absentes restent NotRun. macOS et ARM ne deviennent promis que par une matrice explicite.

Une image introuvable, un pull/DNS refusé, une API partiellement compatible ou un client indisponible produit un écart. Aucun `HTTP 200`, test mocké ou succès NuGet .NET ne devient un succès PSREG1. Les fixtures vivent hors des sources ; les volumes de données utilisateur ne sont pas supprimés par un test.

## Lifecycle et cycles maîtrisés

`I3SEED → PSREG0 → PSREG1 → SMREG → I3` est l'ordre producteur vers consommateur. En parallèle, I3SEED produit le feed NuGet REG. Les adaptateurs Manager de start/status/stop/backup/restore s'appuient sur les providers déjà qualifiés ; les providers ne dépendent pas de ces adaptateurs pour démarrer. Tous les effets passent par ShouldProcess et WhatIf reste sans effet. Le seed et une copie exportée des paquets permettent la récupération si le serveur de paquets est indisponible.

Le fichier d'état désiré et les références de credentials sont Gitables ; données du serveur, caches, logs et secrets ne le sont pas. Le contrôle du lifecycle porte sur les seules ressources possédées, identifiées et verrouillées. SMREG est une nouvelle version de capacité du Manager ; il ne devient pas une dépendance de build de son seed.

## Qualification par kind

### Faisabilité observée le 10 novembre 2026

Une sonde codifiée `scripts/Test-LocalGalleryContainer.ps1` a démarré un vrai BaGet sur le contexte Docker→Podman du poste, avec port loopback et ressources jetables possédées. Le parcours **PinnedClosure** a publié les témoins `0.0.1-dev1` et `0.0.1-draft1`, puis les a trouvés, sauvés et importés depuis Windows PowerShell 7.6.9 et Linux PowerShell 7.6.7, tous deux avec PSResourceGet 1.2.0. Résultats observés : valeur `42`, label `draft1` et mêmes empreintes des trois modules entre clients. Le parcours de dépôt local en conteneur est donc faisable sur ces deux clients x64.

La première tentative **Automatic** a échoué au contrôle de dépendance preview : la plage numérique `[0.0.1, )` produite depuis le manifeste n'a pas retrouvé le paquet `DevDependency` preview. PinnedClosure **ne masque pas** cet échec : ce mode explicitement choisi désactive le précheck de publication et la résolution récursive du consommateur après avoir restauré la dépendance exacte. Il démontre une livraison par fermeture figée, pas la résolution transitive automatique. Le standard doit décider de ce mapping/versionnement avant qualification produit ; la recette conserve cette distinction. Voir [API de publication](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource?view=powershellget-3.x) et [dépôts compatibles](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/supported-repositories?view=powershellget-3.x).

Cette preuve exploratoire ne fait passer ni PSREG1 complet ni I3Accepted : redémarrage persistant, backup/restore, conflits/concurrence, corpus malformé, mutations et autres plateformes/architectures promises restent à qualifier. Image locale exécutée : `sha256:c66780acc1278f7727671e6523a5fc9236b883d430058c6b9a348a2011be8f09` (ID de configuration local, pas un digest de manifeste à substituer dans une référence de pull). La sonde nettoie les ressources jetables et conserve ses résultats ; [l'audit](audits/2026-11-10-frenchexdev2-progression.md) en donne les chemins et limites.

Design arrête protocoles/configuration/ownership, impl livre fonctions et façades, test exerce les rondes réelles plus propriétés/fuzz/mutations, obs conserve versions/digests/AC et écarts par client. Avant ImplementationReady : provider/version/image immuable, architectures promises, port, budget temps/mémoire et stratégie de retour sont décidés. Les [recettes de progression](requirements/software-ecosystem-factory.execution.json) portent les interfaces proposées, leurs sorties et consommateurs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**PSREG** — product — Répertoire d'abord, localhost conteneur qualifié avant i3 accepté.

Fournir un dépôt PSResource local et valider son hébergement en conteneur par de vrais clients PowerShell Windows/Linux.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Protocoles compatibles PSResourceGet, séparation NuGet/PS, profils filesystem/HTTP et lifecycle |
| impl | Fonctions pack/publish/find/save/import et start/health/stop/backup/restore avec façades et WhatIf |
| test | Ronde réelle draft1/dev1 à cache froid, dépendance preview, redémarrage persistant, clients Windows/Linux et injection de conflits |
| obs | Digest image, versions client/serveur, endpoints, empreintes de paquets et résultats par plateforme sans secret |

Traçabilité : PSREG-001, PSREG-002, PSREG-003. Lots : PSREG0, PSREG1. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| PSREG-001 | Un feed PSResource sur répertoire assure pack/publish/find/save/import des previews avec dépendances explicites. | PSREG-001-AC1 → PSREG-001-T1 (integration, NotRun) |
| PSREG-002 | Le feed PSResource localhost conteneur est qualifié par de vrais clients PowerShell Windows et Linux en CLI. | PSREG-002-AC1 → PSREG-002-T1 (integration, NotRun) |
| PSREG-003 | InstanceManager gère les répertoires/containers de registres et leurs cycles de vie avec ShouldProcess et reprise indépendante. | PSREG-003-AC1 → PSREG-003-T1 (fault, NotRun) |

**Décision de patterns : Ports/Adapters + immutable repository + staged bootstrap.**

Contexte : Le Manager doit gérer les registres qui livrent sa prochaine version.

Problème : Un serveur démarré n'atteste pas un protocole compatible ni une installation reproductible.

Forces : Crossplatform, volume persistant, isolement client et dépendances prerelease.

Participants : Seed installe ; provider héberge ; client publie/restaure ; Manager N gère candidate N+1.

Collaboration : PSREG0 précède PSREG1 ; SMREG consomme leurs interfaces sans dépendance retour.

Conséquences : Un serveur NuGet compatible reste à qualifier pour PSResource ; le service public PSGallery n'est pas cloné.

Alternative : Déduire compatibilité PowerShell d'un simple curl HTTP 200 rejeté.

Oracle indépendant : Module avec dépendance preview publié, retrouvé, sauvé et importé depuis clients isolés ; résultat fonctionnel vérifié.

**SOLID / DRY / MODULAR :** ISP par protocole ; SRP hébergement/publication/installation ; DRY identité ID/version/hash ; orchestration Manager distincte.

Entrée : I3SEED et toolchain observée ; provider/digest/ports et budgets décidés.

Sortie : Ronde et lifecycle qualifiés sur plateformes promises ; absence d'une plateforme reste un écart.

Risque : Un client peut changer son registre utilisateur ou masquer un manque via un cache chaud.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| PSREG0 | Publish-LocalPSResource → Test-LocalPSResourceRoundtrip | LocalPSResource | PSREG1, G2, RACPKG, IEC, CORE, CON0 | psfeed-publication | Proposed |
| PSREG1 | Start-LocalGallery → Test-LocalGalleryRoundtrip | LocalPSResource | SMREG | localhost-gallery-port, gallery-volume | Proposed |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
