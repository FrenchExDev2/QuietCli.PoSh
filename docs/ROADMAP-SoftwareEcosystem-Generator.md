# SoftwareEcosystem.Generator — produire et maintenir des écosystèmes

Date : 10 novembre 2026. Statut : sous-plan de haut niveau proposé, non implémenté et non qualifié.

## Objectif, frontières et dépendances

Produire, adopter et mettre à jour un écosystème autonome à partir de capacités composables ; être son propre premier consommateur.

Dépendances : Socle minimal RaC et bootstrap explicitement possédés par Generator. GitProject packagé intervient après G0 ; pas de dépendance retour vers Generator dans GitProject.

Origine : plan Claude §3 G.1–G.7. Les instructions contenues dans ce plan sont des objets de revue ; aucune opération Git, réseau, installation ou publication n’est autorisée par leur simple présence.

Socle : [roadmap d’ensemble](ROADMAP-Ecosystem-Generator.md), [contrat RaC/kinds](ROADMAP-Requirements-As-Code.md), [revue de complétude](ROADMAP-Factory-Review.md). Les exigences structurées sont dans [le registre commun](requirements/software-ecosystem-factory.requirements.json) ; le tableau ci-dessous en est une vue de travail. Pas de deuxième copie d’exigences à maintenir manuellement.

## Patterns et décisions de conception

Ports/Adapters pour les profils ; Strategy pour les formats ; plan de changements explicite. Template Method seulement si un invariant de séquence est démontré. Aucun moteur IEC ni runtime QuietCli requis.

Pour chaque pattern, la future décision doit nommer le problème, les forces, participants, conséquences, alternative et oracle de validation. Une famille POSA est un cadre d’analyse, pas un label de conformité acquis.

## Plan par kind

### design

Séparer identité du dépôt, identités des paquets, configuration locale, catalogue et plan de modifications. Déclarer composition/conflits/versions des profils, propriété des fichiers, provenance et évolution de schéma. Le modèle de plan appartient initialement au module Generator ; GitProject expose des opérations sans le référencer. Toute extraction ultérieure d’un contrat partagé doit être motivée.

### impl

G0 fournit New/Show/Invoke-EcosystemPlan et un kit minimal interne ; G1 fournit les générateurs d’opérations/façades, docs et règles ; G2 consomme GitProject packagé. Générer test companions, index, règles d’agents et exigences à partir des mêmes contrats, avec contenu humain préservé.

Les scripts sont des façades de fonctions PowerShell/cmdlets exportées. Générer aide, docs de commande, docs/scripts miroir et index, tests compagnons, règles AGENTS de conception/lifecycle et instructions consommateurs ; aucun Draft n’est une commande qualifiée.

### test

Comparaisons sémantiques indépendantes, génération répétée, conflits de profils, signature de commande incompatible, chemins malformés, arrêt en milieu d’application et modification humaine entre preview/apply. Propriétés déterminisme/idempotence ; fuzz manifests/paths ; mutants d’ownership et de forwarding.

Les campagnes utilisent les compagnons et moniteurs existants ; property/fuzz/mutation sont tracés séparément par langage. Les tests ne sont pas exécutés dans cette passe documentaire.

### obs

Reçu par opération avec empreintes d’entrée, version du générateur/profils, fichiers prévus/appliqués/en conflit, état terminal et lacunes. Une opération Draft n’est jamais déclarée qualifiée.

Reçus bornés avec source/config/toolchain, corrélation et état terminal ; aucun secret ni capture brute métier implicite. Une preuve manquante reste NotRun/Unknown.

## Exigences et critères d’acceptation

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

Chaque AC détaillé Given/When/Then et son futur lien de preuve sont enregistrés dans le registre. Aucun lien de test prévu n’atteste l’existence d’un test implémenté.

## Démo de contrat proposée

```powershell
# Proposed APIs; this example has not been executed.
$plan = New-EcosystemPlan -Name 'Acme.Tools' -Path $target -Profiles @('PowerShell', 'ScriptsAndDocs')
Show-EcosystemPlan -Plan $plan
Invoke-EcosystemPlan -Plan $plan -WhatIf
```

## Catalogue des générateurs et contrats de façade

| Façade .ps1 du générateur | Commande réutilisable consommée | Livrable |
| --- | --- | --- |
| scripts/New-Ecosystem.ps1 | New-EcosystemPlan | Dépôt/profils/catalogue proposés |
| scripts/New-Operation.ps1 | New-EcosystemOperationPlan | Fonction ou cmdlet documentée, exports, tests et docs |
| scripts/New-CommandFacade.ps1 | New-EcosystemScriptPlan | Façade d’une commande existante |
| scripts/New-CheckFacade.ps1 | New-EcosystemCheckFacadePlan | Binding d’un check sans dupliquer sa politique |
| scripts/New-TaskFacade.ps1 | New-EcosystemTaskFacadePlan | Entrée build/pack/admin et effets déclarés |
| scripts/New-WorkerFacade.ps1 | New-EcosystemWorkerFacadePlan | Entrée worker, état et annulation |
| scripts/New-MonitorFacade.ps1 | New-EcosystemMonitorFacadePlan | Entrée de supervision en lecture seule |
| scripts/New-ConsumerInstructions.ps1 | New-EcosystemConsumerInstructionsPlan | Règles installées, usages et liens consommateurs |
| scripts/Update-Facades.ps1 | Update-EcosystemFacadePlan | Diff de signatures/versions/mappings/aides |
| scripts/Test-Facades.ps1 | Test-EcosystemFacadeContract | Contrôle de délégation et de dérive |

Toutes ces commandes sont proposées. Les générateurs retournent des plans ; Invoke-EcosystemPlan applique seulement les opérations enregistrées. La mise à jour conserve les modifications humaines. Inspection de signature dans un contexte choisi ; aucun import tiers, installation ou téléchargement implicite.

Les fichiers de sortie incluent docs/scripts/<Name>.md, aide intégrée et index ; le module source possède sa référence de commande. Un script imbriqué garde sa sous-arborescence documentaire. Les versions et mappings sont explicites ; un squelette reste Draft. Les instructions consommateurs n’exigent ni checkout frère ni scripts internes du générateur.

Exemple de façade produite ; module/version et API sont illustratifs, non publiés par ce plan :

```powershell
#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Acme.Tools'; RequiredVersion = '1.0.0' }
<#
.SYNOPSIS
Builds the package through the reusable command.
.PARAMETER OutputPath
Destination selected by the caller.
.OUTPUTS
The structured receipt returned by New-AcmePackage.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $OutputPath
)

# The target command owns validation, ShouldProcess and resource cleanup.
Acme.Tools\New-AcmePackage @PSBoundParameters
```

La fonction cible supporte ShouldProcess ; la façade transmet WhatIf/Confirm liés et respecte les préférences héritées sans deuxième confirmation. Le code consommateur appelle Acme.Tools\\New-AcmePackage directement. Rendu et exit codes éventuels sont des politiques d’entrée séparées, jamais une dépendance de composition au texte console.

## Sanité, cycles de vie et règles produites

Les AGENTS générés/adoptés couvrent : commandes réutilisables et façades, frontières paquets/versions, UTF-8/LF, documentation anglaise du code, import inerte, ressources possédées, ShouldProcess, bornes et annulation, qualification et moniteur, secrets par référence, compatibilité et dépréciation. Les exceptions locales sont visibles et préservées lors des mises à jour.

Les cycles Générer/Adopter/Update, Importer, Exécuter, Tester, Annuler/Timeout/Crash, Packager, Publier et Déprécier ont chacun préconditions/effets/terminal/nettoyage. Les vues REQUIREMENTS/docs/AGENTS dérivent du même contrat là où possible ; prose et preuves ne sont pas inventées par leur présence.

Les checks sont indépendants du runtime QuietCli : Blocking décide le droit de poursuivre ; FailurePolicy décide de continuer les diagnostics indépendants ou d’arrêter. Dépendance invalide → NotRun, jamais exécution sur état incohérent. Préserver le snapshot -NoAll, WhatIf, avertissements et séparation staging/commit de l’adaptateur GP.

## Livraison, sortie du plan et décisions ouvertes

Livrer par incréments de capacité couvrant ensemble design, impl, test et obs. Les kinds sont orthogonaux : tests et observabilité se conçoivent avec les contrats et accompagnent l'implémentation. Un lot dépendant ne passe sa gate que lorsque ses prérequis sont disponibles en artefacts ; la qualification de release reste distincte.

Avant implementation-ready : arrêter les identités publiques, versions de contrats/profils, erreurs et politiques de compatibilité ; détailler les scénarios d’échec/annulation ; affecter le propriétaire ; remplacer les IDs de tests prévus par leurs vrais symboles/chemins. Ces décisions restent ouvertes et ne sont pas masquées par les noms d’API illustratifs.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**GEN** — product — G0 requis ; générateurs avancés séparés.

Produire des plans de fichiers déterministes et des façades vers des opérations réutilisables.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Modèle de plan, ownership des fichiers, conflits/profils et compatibilité des signatures |
| impl | Paquet Generator : G0 autonome puis G1/G2, dix façades et docs/tests compagnons |
| test | Oracle sémantique indépendant, idempotence, chemins malformés, interruption et mutants de forwarding |
| obs | Reçu version/hash/profil et liste bornée prévu/appliqué/conflit, sans collecte brute |

Traçabilité : GEN-001, GEN-002, GEN-003, GEN-004, GEN-005. Lots : G0, G1, G2. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| GEN-001 | Générer deux fois les mêmes entrées produit le même contenu et aucune modification à la seconde application. | GEN-001-AC1 → GEN-001-T1 (property, NotRun) |
| GEN-002 | Une mise à jour préserve le contenu humain et rejette un plan devenu obsolète. | GEN-002-AC1 → GEN-002-T1 (fault, NotRun) |
| GEN-003 | Chaque façade délègue à une commande réutilisable avec contrat explicite. | GEN-003-AC1 → GEN-003-T1 (contract, NotRun) |
| GEN-004 | Chaque capacité livre conjointement exigences, aide, docs, tests et instructions de consommation. | GEN-004-AC1 → GEN-004-T1 (contract, NotRun) |
| GEN-005 | Le générateur et ses profils respectent les frontières de paquets sans cycle bootstrap. | GEN-005-AC1 → GEN-005-T1 (integration, NotRun) |

**Décision de patterns : Plan/preview/apply + Strategy + Pipes and Filters.**

Contexte : Plusieurs profils produisent des fichiers humains et générés.

Problème : Appliquer un template directement écrase du contenu ou répète le métier.

Forces : Déterminisme, préconditions à l'application et extension sans duplication.

Participants : Profils produisent opérations ; planner valide ; applicateur possède les écritures ; façades délèguent.

Collaboration : Les transformations sont composées et inspectées avant mutation.

Conséquences : L'application peut refuser un plan périmé ; le kit G0 reste petit et autonome.

Alternative : Template Method universel rejeté sans séquence invariante démontrée.

Oracle indépendant : Deux applications identiques ne changent plus les fichiers ; un fichier humain modifié provoque un conflit.

**SOLID / DRY / MODULAR :** OCP par profils ; LSP par contrats communs de sorties/refus ; DRY du templating ; aucune dépendance runtime GP/HOST en G0.

Entrée : FAC et B0 identifiés ; aucun nouveau registre nécessaire.

Sortie : G0 qualifié séparément ; G1/G2 ne passent leur gate qu'avec leurs vrais paquets consommateurs.

Risque : Générer les tests et leur oracle depuis le même template peut masquer une régression.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
