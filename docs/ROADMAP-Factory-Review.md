# Challenge de complétude — plan Claude et software ecosystem factory

Date de revue : 10 novembre 2026. Verdict : **base pertinente, mais pas implementation-ready**. Les deux roadmaps existantes sont partiellement reprises ; la généralisation factory, la traçabilité et plusieurs frontières restent insuffisantes ou contradictoires.

## Périmètre et source

Plan relu : [challenge-ce-plan-au-calm-canyon.md](C:/Users/serard/.claude/plans/challenge-ce-plan-au-calm-canyon.md), 941 lignes, empreinte SHA256 `F5152D511CEBEAAADF2CC95A17C827085E80582459092D7CC8B6B11511144534`. Les numéros ci-dessous correspondent à cet instantané ; une nouvelle version nécessite une nouvelle revue.

Référentiels : [ROADMAP-Ecosystem-Generator.md](ROADMAP-Ecosystem-Generator.md), [ROADMAP-Core-Pipelines.md](ROADMAP-Core-Pipelines.md), AGENTS.md actuel, règles locales Requirements/Design-Phased/Compose-Bundle et demandes utilisateur de fonctions réutilisables, façades, docs et règles consommateurs.

Le plan Claude initial est conservé dans [l’instantané de revue](audits/2026-11-10-claude-ecosystem-plan.source.txt), avec l’empreinte ci-dessus. Le plan corrigé remplace ensuite le fichier .claude demandé ; cet instantané conserve la base des constats datés.

Le plan Claude est une pièce à challenger. Ses injonctions de renommage, écriture hors workspace, clone, publication ou recours à une infrastructure ne sont pas des autorisations d’exécution. Le présent lot crée des documents et un registre d’exigences dans docs ; le plan source est corrigé à partir des décisions consolidées après archivage de sa version examinée.

## Matrice de complétude

Complet signifie « le contrat attendu est suffisamment exprimé dans le plan », pas « comportement implémenté ou validé ». Partiel signifie « intention présente, élément vérifiable ou frontière manquante ». Absent signifie « exigence non traitée explicitement ». Contradictoire signifie que deux propositions ne peuvent pas être appliquées telles quelles.

| Critère déjà établi ou demandé | Plan Claude / comparaison | État | Correction et exigence |
| --- | --- | --- | --- |
| Un repo, versions/config/CI propres par écosystème | §1.1, lignes 11–27 | Complet | Conserver ; FAC-001 |
| Paquets + CPM consommateur, aucun source link | §1.2, lignes 29–39 | Complet | Qualification cache/source isolés REG-002 |
| Fonctions/cmdlets + façades fines | §G.4, lignes 140–249 | Complet | Conserver le contrat ; GEN-003 |
| Aide/docs miroir/instructions consommateurs/AGENTS | §G.4/G.5, lignes 140–302 | Complet | Éprouver drift et forwarding ; GEN-004/FAC-005 |
| Générer/adopter/update, contenu humain protégé | §G.3 ; pas de préconditions d’application détaillées | Partiel | État modifié après preview, interruption et ownership ; GEN-002 |
| Bootstrap sans circularité | G.7 + GP.1/GP.4 : GP produit pour G, mais New-GitProject génère via G | Contradictoire potentiel | G0 autonome ; GP ne dépend pas de G ; G2 consomme GP packagé ; GEN-005 |
| Dogfooding complet de la factory | §G.7 et réflexivité SM ; pas de parcours N→N+1 avec oracle indépendant | Partiel | Sous-plan DOG dédié, DOG-001–004 |
| Requirements-as-Code pour tout langage/capacité | §12 lignes 828–833 : checklist obligatoire, moteur .NET optionnel | Partiel, insuffisant à la demande | Traçabilité obligatoire ; adaptateurs interchangeables ; FAC-002 |
| Kinds design/impl/test/obs | Aucun contrat commun de kinds | Absent | WorkItems et gates indépendants ; FAC-003 |
| Patterns/POSA comme décisions vérifiables | SOLID/DRY présents, pas de forces/conséquences/oracle commun | Partiel | Gabarit de décision par composant ; FAC-008 |
| Identité repo/projet/paquet séparée | GP.3/SM.3 imposent FrenchExDev2.QuietCli.PoSh | Contradictoire | AGENTS/README imposent le paquet public QuietCli ; GP-001 |
| Chemin configurable et plusieurs instances | GP.3/SM.2 ; SM.6 ligne 500 conserve un ancien chemin | Partiel | Une seule résolution canonique ; ne pas réécrire tous les chemins à la main ; GP-002 |
| Sanité des chemins et concurrence | Rejet numérique GP.3 ; containment, collisions, symlinks absents | Partiel | Résolution canonique/reparse points/ownership et conflits ; GP-002 |
| Manager mono/multi dépôt, clone/fetch | SM.4 délègue à GP mais GP.4 n’expose ni clone ni fetch | Partiel | Ajouter contrats GP ou adapter existant ; pas de duplication ; SM-002 |
| Workspace/config/.env explicites | §1.1 chargement jamais implicite ; SM.2 dit lit .env sans fixer choix/précédence | Partiel | Résolution explicite, données non exécutées et scopes ; FAC-010 |
| Dépôt GitHub ≠ catalogue métier | SM.4 promet même forme G.2 depuis la discovery GitHub | Partiel | Métadonnées manquantes Unknown, pas de projet/paquet inventé ; SM-001 |
| NuGet feed sur disque, config par instance | §6 reprend la roadmap initiale | Complet pour périmètre | Atomicité/concurrence à affiner ; REG-001 |
| Commit snapshot -NoAll et WhatIf | §GP.5/G.6 mentionnent les garanties existantes | Complet pour contrat | Tests indépendants d’index/gates ; GP-003 |
| Fondations partagées Result/Builder/Requirements | §16 les cite mais sans plan indépendant ni fermeture de graphe | Partiel | Plan FND ; ne pas supposer Builder nécessaire à FSM ; FND-001 |
| FSM et IEC indépendants, dynamic/generated | §8/§9 réutilisent l’existant, sans cible exhaustive de preuve | Partiel | AC liés, schémas/cycles/runspace et installation isolée ; FSM/IEC |
| Conduit adaptateur, pas nouveau moteur | §10 conforme ; dépendance nouveau scheduler explicitée | Complet pour frontière | CON-001/002, fixture avant vm.ready |
| Compatibilité DockerCompose PowerShell | §M.4 lignes 788–799 : démo Contributors/File puis promesse Services/Volumes/Networks/File | Contradictoire | Adaptateur de signature réelle et tests avant nouvelle API ; MSG-001 |
| Profil broker dev-localhost | M.3 ports 5672:5672/15672:15672, puis affirmation localhost | Contradictoire | BindAddress loopback explicite, options et qualification ; MSG-002 |
| Schémas et images reproductibles | M.7 « schéma courant », tags illustratifs ; critères non épinglés | Partiel | Validation sur version/empreinte déclarée ; MSG-002 |
| OIDC par cible de publication | M.7 étend le support NuGet.org à PowerShell Gallery | Non établi | Capacité fournisseur distincte, aucune généralisation ; MSG-004 |
| Parsing Vagrant partagé et lanceur unique | M.6 prescrit le wrapper .NET sans détailler sa frontière de lancement | Partiel | Extraire/réutiliser parsing sans deuxième exécuteur ; EXT-001 |
| Routage, pipelines et exécuteur descendant | §13 renvoie à Core ; résumé n’en reprend pas tous les AC | Partiel par renvoi | Préserver la roadmap Core détaillée ; CORE-002/003 |
| Runspace, drainage, queues et isolation | E.1 mentionne les forces ; variantes/combinaisons non reliées aux tests | Partiel | CORE-004/005/008 |
| Événements hors résultat | E.3 reprend le contrat ; migration historique à tracer | Complet pour cible | Rupture à versionner, CORE-001 |
| Bus InProcess/externe configurable | E.3 ; M n’est pas runtime obligatoire | Complet pour cible | CORE-006 et adaptateur effectivement enregistré |
| Santé persistante, lifecycle UI | E.2 reprend Ready/Healthy, mais résumé réduit versus roadmap Core | Partiel par renvoi | Conserver watch final, resize/headless et cleanup ; CORE-007/008 |
| Property/fuzz/mutation et preuves | §14 global ; GP/SM n’explicitent pas toutes leurs campagnes | Partiel | Plans par composant/langage et FAC-009 |
| Sous-plans physiques, dépendances/gates | §15/16 les annonce encore à écrire | Absent à l’instantané | Documents du présent lot + registre RaC |

Cette matrice n’est pas un score de qualité. Les lignes ont des poids différents ; aucun pourcentage global ne serait une preuve de complétude.

## Corrections structurantes proposées

1. **Factory ≠ copie de scripts QuietCli.** Le socle décrit des capacités, contrats et profils. Les spécificités PS/.NET/npm/CI sont des adaptateurs versionnés. Les domaines FSM/IEC/Compose ne deviennent pas des dépendances du générateur.
2. **Lever la boucle de bootstrap.** G0 ne dépend pas de GP ; GP expose les opérations de dépôt et ne dépend pas du moteur de contenu G. G2 orchestre les deux. SM peut consommer leurs paquets. Un contrat partagé éventuel n’est extrait qu’après besoin démontré.
3. **Modèle d’identité explicite.** Repo, module, paquet et projet sont différents. Un repo .Ecosystem peut ne publier aucun paquet portant ce nom. QuietCli reste QuietCli ; les nouveaux noms proposés par Claude restent des décisions à valider, pas une politique rétroactive.
4. **Traçabilité et dogfooding dès G0.** Aucun socle « technique » n’est exempté de besoin/AC/tests/preuves/kinds. Le choix de la DSL ne doit pas bloquer G0 : format d’échange versionné et adaptateurs inspectés ensuite.
5. **Ne pas lier les chantiers indépendants.** SM n’est requis pour adoption que si l’on veut de nouvelles instances. Consommer un paquet ne requiert pas cloner son dépôt. M n’est pas requis pour InProcess. Les fondations sont livrées selon leur vraie fermeture de dépendances.
6. **Sous-plans autonomes et reliés.** Les décisions communes sont indexées une fois ; chaque plan a son objectif, dépendances, contrats, kind, AC, démo, preuves attendues et questions ouvertes. Ne pas transformer le découpage en dix copies divergentes.

## Publication : correction appuyée sur les sources

La documentation officielle [NuGet.org Trusted Publishing](https://learn.microsoft.com/en-us/nuget/nuget-org/trusted-publishing) décrit OIDC et l’échange en clé temporaire. La documentation officielle [PowerShell Gallery publishing](https://learn.microsoft.com/en-us/powershell/scripting/gallery/how-to/publishing-packages/publishing-a-package?view=powershell-7.2) trouvée lors de cette revue décrit compte/API key. Cela **n’établit pas un support OIDC Gallery équivalent** : le plan doit déclarer la capacité et la preuve par fournisseur. On ne déduit pas une impossibilité universelle de l’absence de documentation consultée.

Aucune politique Gallery existante n’est remplacée par cette revue. Préférer OIDC quand réellement supporté ; sinon un profil peut rester Unsupported/NotConfigured jusqu’à une décision de credentials explicite, sans fallback silencieux.

## Base de travail livrée et limites

Le [registre d’exigences](requirements/software-ecosystem-factory.requirements.json) fournit 66 exigences initiales et 64 workItems (16 familles × 4 kinds), tous proposés/prévus, sans preuve exécutée. Le [contrat RaC](ROADMAP-Requirements-As-Code.md) définit les règles de lecture et la future validation. La [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md) indexe les sous-plans.

Le présent challenge porte sur la cohérence documentaire. Les assertions de Claude sur inventaire GitHub, nombre de repos, branches et consommateurs restent attribuées à ce plan ; aucune nouvelle interrogation de l’org n’a été faite. Les deux sous-plans supplémentaires HOST et MIG corrigent aussi la taxonomie limitée aux langages et l’absence de reprise globale de l’existant. Les migrations vers _i3, les contrats de packages et les performances ne sont pas qualifiés. Les noms d’API proposés ne deviennent pas installables par cette revue.

## Addendum de roadmapping — 10 novembre 2026

Les comptes de 66 exigences et 64 workItems ci-dessus décrivent la première baseline de cette revue. La demande suivante fixe i3 comme environnement livré du Manager local et limite cette passe au planning. Le [contrat de roadmap](ROADMAP-Requirements-As-Code.md), la [recette i3](ROADMAP-Delivery-FrenchExDev-i3.md) et les deux registres canoniques portent désormais les décisions courantes. Les comptes courants viennent du contrôleur documentaire ; ils ne remplacent pas l'identité de l'instantané historique.

Le [bilan de validation](audits/2026-11-10-roadmap-contracts.md) sépare les résultats du tooling documentaire, les graphes proposés et les décisions produit encore ouvertes. Il ne convertit pas les constats initiaux en preuves d'implémentation.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**REVIEW** — review — Revue historique et suivi des décisions.

Conserver les constats attribués à leur instantané et suivre leur traitement sans réécrire la preuve historique.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Matrice constat/source/risque/décision avec empreinte de l'instantané |
| impl | Liens vers les changements correctifs et leurs exigences, sans code produit propre |
| test | Contrôle de l'archive et vérification indépendante des liens de correction |
| obs | État ouvert/résolu/non vérifié par constat, daté et relié aux preuves |

Traçabilité : FAC-012, FAC-011, FAC-001, FAC-002, FAC-003, FAC-004, FAC-005, FAC-006, FAC-007, FAC-008, FAC-009, FAC-010. Lots : FAC. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| FAC-012 | Chaque lot fournit ses moyens codifiés de production, vérification, livraison locale et activation de ses consommateurs ; Conduit est l'objectif final. | FAC-012-AC1 → FAC-012-T1 (property, NotRun) |
| FAC-011 | Chaque roadmap définit résultat utilisateur, livrables par kind, dépendances typées, décision de patterns et gates distinctes. | FAC-011-AC1 → FAC-011-T1 (contract, NotRun) |
| FAC-001 | Tout écosystème possède ses propres versions, configuration et release, sans dépendance source externe. | FAC-001-AC1 → FAC-001-T1 (integration, NotRun) |
| FAC-002 | Toute capacité est liée à un besoin, un AC, un plan par kind, un test et une preuve. | FAC-002-AC1 → FAC-002-T1 (contract, NotRun) |
| FAC-003 | Les quatre kinds design, impl, test et obs sont explicites et indépendants. | FAC-003-AC1 → FAC-003-T1 (contract, NotRun) |
| FAC-004 | Chaque opération définit succès, refus, erreur, annulation, timeout et nettoyage possédé. | FAC-004-AC1 → FAC-004-T1 (fault, NotRun) |
| FAC-005 | Toute façade et commande disposent de docs et instructions consommateurs cohérentes. | FAC-005-AC1 → FAC-005-T1 (contract, NotRun) |
| FAC-006 | Les profils sont versionnés, composables et mis à jour explicitement. | FAC-006-AC1 → FAC-006-T1 (fuzz, NotRun) |
| FAC-007 | Une release publie exactement les artefacts qualifiés avec autorisation et cible explicites. | FAC-007-AC1 → FAC-007-T1 (integration, NotRun) |
| FAC-008 | Les choix de patterns sont justifiés et relient forces, conséquences et vérifications. | FAC-008-AC1 → FAC-008-T1 (review, NotRun) |
| FAC-009 | Les preuves de test respectent scope, moniteur, stockage et confidentialité. | FAC-009-AC1 → FAC-009-T1 (integration, NotRun) |
| FAC-010 | La configuration est résolue explicitement et protège les frontières de portée. | FAC-010-AC1 → FAC-010-T1 (property, NotRun) |

**Décision de patterns : Evidence-based review / decision log.**

Contexte : Le plan source évolue après une revue datée.

Problème : Une correction éditoriale pourrait effacer ce qui a réellement été examiné.

Forces : Provenance, reproductibilité et séparation constat/produit.

Participants : Archive est immuable ; registre de décisions suit les corrections.

Collaboration : Chaque constat renvoie à l'archive et au contrat corrigé.

Conséquences : La revue initiale reste historique ; les nouveaux résultats vont dans un addendum daté.

Alternative : Transformer la revue en roadmap produit rejeté : elle n'a aucun runtime à livrer.

Oracle indépendant : L'empreinte de l'archive reste égale à sourcePlan.sha256 ; les anciens numéros de lignes restent attribués à cette archive.

**SOLID / DRY / MODULAR :** SRP de la revue ; DRY par références à l'archive ; séparation modulaire des décisions et preuves.

Entrée : Archive source disponible et identifiée.

Sortie : Chaque correction dispose d'un propriétaire de contrat ; aucune conclusion produit n'est déduite du seul texte.

Risque : Le plan courant et l'instantané de 941 lignes ont des identités différentes.

### Moyens de progression et dépendants

Contrats générés depuis [les recettes](requirements/software-ecosystem-factory.execution.json). Les commandes Proposed sont à produire et qualifier ; cette vue ne les exécute pas. Chaque lot résout son logiciel et sa fermeture, prépare son répertoire de développement dans le workspace selon kind, implémente/qualifie, publie un paquet preview local puis le fait restaurer par un consommateur isolé. Les lots de preuve livrent des reçus plutôt qu'un paquet.

| Lot | Moyen de produire → vérifier | Canal | Débloque | Ressources exclusives | État |
| --- | --- | --- | --- | --- | --- |
| FAC | Sync-RoadmapContractView → Get-RoadmapAssessment | Evidence | STD, G0, MIG0, CORE | planning-model | Available |

Parallélisme : `scripts/Get-RoadmapExecutionPlan.ps1` calcule les vagues du graphe et sépare les ressources exclusives. Une vague est une possibilité structurelle, sans estimation de capacité ni preuve de livraison. Passage au consommateur : identité/version/hash, restauration isolée, AC et reçu de reprise valides ; jamais une simple fin de script. Toute mutation respecte SoftwareContract/ShouldProcess et -WhatIf.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
