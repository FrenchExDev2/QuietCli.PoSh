# Roadmap Core : pipelines, lanceur injectable et composition par événements

Date : 9 novembre 2026. Statut : proposition à challenger, sans implémentation associée.

Périmètre : `FrenchExDev2.QuietCli.Core.PoSh`, ses compagnons de tests et un exemple Vagrant. Les noms d’API et les exemples de code ci-dessous sont proposés ; ils ne constituent pas des commandes actuellement disponibles ou des exemples déjà exécutables. Les variables injectées dans les exemples représentent les composants que l’implémentation devra fournir.

## 1. Architecture visée

Faire du Core un moteur de composition utilisable depuis PowerShell et C#, avec trois mécanismes distincts :

- **Routage** : choisir un pipeline selon la commande et le contexte.
- **Pipeline d’invocation** : composer préparation, exécution, analyse et aspects transversaux.
- **Composition événementielle** : déclencher et suivre d’autres appels pendant ou après une source.

Le lanceur est fourni à la racine de la composition et transmis aux appels descendants. Le lanceur natif actuel reste le défaut.

```text
Appelant PowerShell / C#
        │
        ▼
Composition : lanceur + bus + limites + abonnements
        │
        ▼
Routage → pipeline d’invocation → handler métier
                   │                    │
                   └────── lanceur ◄────┘
                              │
                        flux natifs
                              │
                     analyse / événements
                         │           │
                         ▼           ▼
                  résultat final    bus → listeners → nouveaux appels
```

**Les événements restent séparés des résultats** : aucune propriété `Events` dans les contrats `-AsObject`, `-AsJson` ou `-AsYaml`. Leur publication ne constitue pas une sortie PowerShell.

### Ce que montre RTK

RTK distingue la réécriture des commandes par les hooks, le routage vers des filtres métier et les transformations de leurs sorties. Ses filtres spécialisés peuvent employer des parseurs structurés et des machines à états. [Architecture RTK](https://github.com/rtk-ai/rtk/blob/develop/docs/contributing/TECHNICAL.md)

Son moteur de pipelines ajoute des règles conditionnelles et des chaînes de méthodes validées. Les filtres de commandes restent distincts des méthodes composables. [Pipelines RTK](https://github.com/rtk-ai/rtk/blob/develop/docs/guide/pipelines/writing-pipelines.md), [Méthodes RTK](https://github.com/rtk-ai/rtk/blob/develop/docs/guide/pipelines/methods.md)

Pour QuietCli, retenir cette séparation. Le modèle proposé relève du **middleware explicite et des décorateurs** : les points d’interception sont déclarés, inspectables et testables. Aucun weaving IL ou système d’attributs n’est nécessaire.

## 2. Jalons du Core et interfaces

### Jalon 1 — Séparer événements et résultat

Le Core possède déjà `Emit()` et `-Listeners`, mais accumule actuellement les événements dans le runtime et le résultat.

- Conserver `Emit()` et les listeners ScriptBlock existants.
- Supprimer la collecte automatique et les projections `Events`.
- Offrir un collecteur explicite, borné, attachable comme listener.
- Réserver `Data` à la projection métier choisie par l’appelant.
- Mettre à jour les exemples et tests qui lisent actuellement `$runtime.Events`.

Cette modification est une rupture explicite du contrat événementiel actuel ; ne pas conserver un champ vide donnant l’impression que la collecte continue.

### Jalon 2 — Extraire le lanceur et les pipelines

Séparer la résolution, l’orchestration, l’analyse et l’accès au processus actuellement regroupés dans le runtime.

Contrats C# proposés :

```csharp
public delegate ValueTask<QuietResult> QuietNext(
    QuietInvocationContext context,
    CancellationToken cancellationToken);

public interface IQuietMiddleware
{
    ValueTask<QuietResult> InvokeAsync(
        QuietInvocationContext context,
        QuietNext next,
        CancellationToken cancellationToken);
}

public interface IQuietExecutor
{
    ValueTask<IQuietExecution> StartAsync(
        QuietExecutionRequest request,
        CancellationToken cancellationToken);
}

public interface IQuietExecution : IAsyncDisposable
{
    IAsyncEnumerable<QuietNativeEvent> ReadAllAsync(
        CancellationToken cancellationToken);

    ValueTask WriteAsync(
        ReadOnlyMemory<byte> bytes,
        CancellationToken cancellationToken);

    ValueTask CompleteInputAsync(CancellationToken cancellationToken);
    ValueTask CancelAsync(CancellationToken cancellationToken);
}
```

`IQuietExecution` expose également l’identité, le résultat terminal et ses capacités ; le redimensionnement reste une capacité optionnelle. Ce fragment illustre les contrats structurants, pas leur déclaration complète.

- Adapter l’exécution actuelle à ces contrats, sans ajouter de couche IPC.
- Fournir un adaptateur ScriptBlock PowerShell créant une session conforme à `IQuietExecution`.
- Résoudre les capacités avant de lancer : une demande PTY non supportée échoue explicitement.
- Conserver les ScriptBlocks d’analyse sur le runspace appelant.
- Garder validation, annulation, intégrité et complétude comme garanties du Core.
- Interdire à un middleware d’appeler deux fois `next` ; une répétition d’opération doit être une étape explicite.

Exemple PowerShell :

```powershell
$pipeline = New-QuietPipeline -Id 'tools.default' -Middleware @(
    $prepareEnvironment
    $measureExecution
    $normalizeResult
)

Register-QuietPipeline $pipeline

$result = quiet -AsObject -Pipeline 'tools.default' `
    -Executor $executor `
    -Output $outputParser -Complete $projection `
    -FilePath $command.FilePath -ArgumentList $command.Arguments
```

`-Executor` accepte un objet C# ou l’adaptateur PowerShell. Son héritage suit la composition ; une surcharge par appel reste possible.

### Jalon 3 — Ajouter le routage explicable

Commandes proposées :

```powershell
Register-QuietPipeline $pipeline
Get-QuietPipeline
Unregister-QuietPipeline -Id 'tools.default'

$call = New-QuietCall -FilePath $tool -ArgumentList $arguments
Resolve-QuietPipeline -Call $call -Explain
Test-QuietPipeline -Pipeline $pipeline
```

- Sélection explicite par `-Pipeline`, sinon règles par exécutable, préfixe d’arguments, contexte et transport.
- Priorité numérique explicite ; plusieurs correspondances de même priorité produisent une erreur.
- Sans route, employer le pipeline standard actuel.
- Préserver la sélection et la qualification des handlers métier.
- `Resolve ... -Explain` et `Test` restent sans lancement ni probe natif.

## 3. Composition événementielle et bus configurable

### Abonnements et ordonnanceur

Introduire `New-QuietListener`, `New-QuietCall` et `Invoke-QuietComposition`.

Chaque listener possède :

- Un filtre d’événement et une portée : appel, descendants ou composition.
- Un rôle `Observer` ou `Required`.
- Un déclenchement `Immediate`, `AfterSourceSuccess` ou `AfterSourceComplete`.
- Une politique `OnError` : `Continue`, `FailComposition` ou `CancelComposition`.
- Une cardinalité `EachEvent` ou `OncePerKey`.

Défauts : `Observer → Continue`, `Required → FailComposition`. Le rôle fournit un défaut ; `OnError` permet de le remplacer.

Les callbacks de réaction programment les appels via `$runtime.Schedule(...)`. Ils ne lancent pas une opération bloquante dans `Emit()`.

L’ordonnanceur :

- Draine simultanément les processus actifs.
- Exécute les callbacks PowerShell sur le runspace appelant.
- Limite par défaut la composition à quatre exécutions natives simultanées.
- Utilise une file bornée à 256 déclenchements, configurable.
- Signale une saturation ; aucun déclenchement nécessaire n’est perdu silencieusement.
- Attend les étapes nécessaires avant de terminer.
- Arrête les tâches de surveillance à la fermeture de la composition.

Remplacer la pile globale des appels comme source unique de parenté par un contexte explicite de composition. Les identités parent/enfant doivent rester correctes lorsque plusieurs processus sont actifs.

### Même abonnement, bus différent

```powershell
# No external service is required.
$bus = New-QuietEventBus -Provider InProcess

# Use another configuration with the same listeners and calls.
$bus = New-QuietEventBus -Provider Nats -Options @{
    Connection = $connection
    Stream     = 'QUIET_EVENTS'
    Consumer   = 'vm-health'
}
```

Le Core contient le contrat `IQuietEventBus` et le fournisseur `InProcess`. Les fournisseurs externes appartiennent à des compagnons avec leurs propres dépendances et tests.

NATS JetStream est un exemple de premier adaptateur externe de référence, sans obligation de déploiement ni dépendance imposée au Core. RabbitMQ et Redis Streams pourront implémenter le même contrat ; leur nom ne sera accepté que si l’adaptateur correspondant est enregistré. JetStream fournit persistance et acquittements, avec possibilité de redélivraison. [Documentation NATS](https://docs.nats.io/concepts/jetstream)

Contrat événementiel commun :

```csharp
public sealed record QuietEvent(
    string Id,
    string Name,
    string SourceId,
    string CorrelationId,
    string? CausationId,
    long Sequence,
    DateTimeOffset OccurredAt,
    object? Payload);
```

- Bus local : livraison éphémère dans la composition.
- Bus externe : payload explicitement exportable, schéma versionné et taille bornée ; aucun runtime, ScriptBlock ou résultat complet envoyé.
- Worker intersession démarré explicitement ; les messages référencent des actions installées localement, jamais du code reçu à exécuter.
- Corrélation et identifiants conservés pour détecter doublons et boucles.
- Pour les actions externes, conserver des reçus durables séparés de la télémétrie. Une action commencée dont l’effet reste inconnu exige une résolution explicite avant réexécution.
- Ne promettre aucune exécution métier « exactement une fois ».

### Configuration déclarative

Utiliser un fichier de composition dédié, importé explicitement, pour préserver le schéma strict du `config.yaml` actuel.

```yaml
schemaVersion: 1

eventBus:
  provider: InProcess

composition:
  maxConcurrency: 4
  maxPendingTriggers: 256

listeners:
  vm-health:
    event: vm.ready
    action: vm.check-health
    timing: Immediate
    role: Required
    onError: FailComposition
    cardinality: OncePerKey
    key: machineId
```

Configuration externe alternative :

```yaml
eventBus:
  provider: Nats
  options:
    connectionProfile: homelab
    stream: QUIET_EVENTS
    consumer: vm-health
```

Le YAML référence des actions enregistrées. Il ne contient ni ScriptBlock, ni expression à évaluer, ni secret. Les paramètres explicites priment sur le fichier, puis sur les défauts.

## 4. Démonstration Vagrant : Ready → contrôle → Healthy

Conserver le rendu de `vagrant up`, puis ajouter un état de santé indépendant de la dernière ligne affichée :

```text
web  | Booting…              | ○ Unknown
web  | Ready                | ◌ Checking
web  | Provisioning…        | ✓ Healthy
web  | Provisioning…        | ✗ Unhealthy
```

`Ready` déclenche le contrôle. Seul le contrôle réussi établit `Healthy`. La définition du signal Ready appartient au compagnon Vagrant et doit être étayée par son format documenté et ses fixtures.

Exemple de composition proposé :

```powershell
# Changing this value changes whether health gates composition success.
$healthRole = 'Required' # Or 'Observer'.

$healthListener = New-QuietListener `
    -Id 'vm-health' `
    -EventName 'vm.ready' `
    -Role $healthRole `
    -Timing Immediate `
    -Cardinality OncePerKey `
    -Key { param($event) $event.Payload.MachineId } `
    -Action {
        param($event, $runtime)

        $check = New-QuietCall `
            -FilePath $healthProbe.FilePath `
            -ArgumentList ($healthProbe.GetArguments($event.Payload)) `
            -Output $healthProbe.Output `
            -Complete $healthProbe.Complete

        [void]$runtime.Schedule(
            $check,
            @{
                Key                  = $event.Payload.MachineId
                Mode                 = 'Watch'
                IntervalSeconds      = 2
                FirstHealthyTimeout  = 60
                ProbeTimeoutSeconds  = 5
                Lifetime             = 'Composition'
            }
        )
    }

$result = Invoke-QuietComposition `
    -EventBus $bus `
    -Executor $executor `
    -Listeners @($healthListener) `
    -UI `
    -AsObject `
    -Body {
        param($runtime)

        $up = New-QuietCall -FilePath 'vagrant' -ArgumentList @('up')
        [void]$runtime.Schedule($up)
    }
```

`$healthProbe` est une définition injectée : exécutable, construction des arguments et callbacks d’analyse. L’exemple livré fournira une sonde HTTP et une sonde fixture déterministe.

- `Watch` programme des contrôles périodiques explicites, sans chevauchement pour une même machine.
- `Observer` actualise l’UI et les diagnostics.
- `Required` exige une première santé positive avant le délai, puis un contrôle final positif.
- Les surveillances ne comptent pas comme des tâches empêchant leur propre arrêt.
- Une défaillance de la source ne déclenche aucune compensation automatique.

Ajouter à l’UI une API générique de statut par lane :

```powershell
$runtime.Ui.SetStatus($machineId, 'health', 'Healthy')
```

La composition traduit les événements de santé vers cette API. Le renderer ignore la sémantique VM.

**Voie recommandée** : abonnement déclaré dans la composition, réutilisable et testable. **Autre voie supportée** : listener attaché directement à un `quiet`, utilisant le même ordonnanceur via le runtime. Un listener qui appelle un `quiet` bloquant dans `Emit()` reste une forme synchrone, sans garantie de progression concurrente.

## 5. Validation et ordre de livraison

Livrer dans cet ordre :

1. Séparation événements/résultats et migration des usages existants.
2. Contrats du lanceur, adaptation de l’exécution actuelle et middleware.
3. Registre, routage, validation et explication des pipelines.
4. Ordonnanceur, listeners configurables et bus `InProcess`.
5. Exemple Vagrant, santé configurable et statuts UI persistants.
6. Adaptateur externe, worker explicite et qualification intersession.

Étendre les compagnons de tests existants avec exemples, propriétés générées, fuzzing et mutants ciblés en C# et PowerShell.

Critères d’acceptation principaux :

- Aucun événement collecté automatiquement ou livré dans les trois formats.
- Même analyse métier avec le lanceur standard ou un lanceur injecté.
- Un contrôle démarre avant la fin de la source, sans bloquer son drainage.
- Les modes après réussite et après terminaison produisent des comportements distincts vérifiés.
- Doublons, saturation, annulation et erreurs respectent les politiques configurées.
- Deux compositions simultanées ne mélangent ni résultats, ni abonnements, ni parenté.
- Une redélivraison externe ne répète pas automatiquement une action d’effet inconnu.
- Une ligne Vagrant ultérieure n’efface pas le statut Healthy.
- Une surveillance s’arrête proprement ; aucun appel ou abonnement ne subsiste.
- L’UI reste lisible après redimensionnement et sans terminal interactif.

Exécuter les suites ciblées avec le moniteur visible existant. La qualification de livraison couvre les consommateurs affectés et la matrice requise ; aucun gain de performance n’est présumé.

Documenter les contrats et exemples en anglais, avec scripts réutilisables et documentation associée. Cette roadmap repose sur une inspection du code et des sources documentaires ; aucune campagne de tests ou mesure comparative n’a été exécutée pour ce plan.

## 6. Articulation avec le générateur d’écosystèmes

Le [plan directeur corrigé de la factory](ROADMAP-Ecosystem-Generator.md) fixe les dépendances globales : RaC et dogfooding dès G0, HOST/GP sans cycle, profils et registres packagés, inventaire/migration de l’existant puis adoption et domaines selon leurs prérequis. Manager et l’infrastructure de broker sont facultatifs pour les usages qui n’en ont pas besoin. L’ordre de la section 5 reste l’ordre interne du chantier Core.

Chaque écosystème possède son dépôt Git/GitHub, ses versions, ses workflows, ses clés/configurations et ses outils de développement. Les projets .NET d’écosystèmes différents se consomment par `.nupkg` et CPM propre via les registres configurés ; aucun import de source voisin ou `ProjectReference` inter-écosystème. Les dépendances de modules PowerShell et npm ont leurs contrats de packaging distincts.

Les mécanismes génériques de scripts/docs/index, `AGENTS.md`, moniteurs et cycles de qualification appartiennent au socle versionné ; le Core conserve l’exécution native, ses handlers, les événements et la composition. Conduit adapte IEC et QuietCli sans rendre l’un dépendant de l’autre. Les commandes et interfaces de cette roadmap restent proposées ; une simple méthode retournant une `Task` ne garantit pas le drainage concurrent ou le respect des runspaces PowerShell.

## 7. Rattachement à la factory, exigences et kinds

Date de rattachement : 10 novembre 2026. Le [plan directeur corrigé](ROADMAP-Ecosystem-Generator.md) fixe le séquencement global et le [contrat RaC](ROADMAP-Requirements-As-Code.md) la traçabilité. Core conserve tous les contrats détaillés des sections précédentes. L’adoption du tooling factory et les changements métier Core sont des lots distincts.

| Kind | Lot et résultat vérifiable |
| --- | --- |
| design | Contrats exécuteur/middleware, routes, scheduler/runspace, événements et lifecycle ; invariants et alternatives documentés |
| impl | Adaptateurs de l’exécution actuelle, commandes PS/C#, faҫades/scripts et docs ; migration Events explicitement versionnée |
| test | Fixtures de drainage simultané, combinaisons listeners, isolation, redelivery et santé ; propriétés/fuzz/mutations C#/PS |
| obs | Corrélation, bornes de files/tâches, motifs de routage, statuts UI et terminaux ; aucun événement métier ajouté aux résultats |

Observabilité et tests sont conçus dès design ; la table n’impose pas de les développer seulement après le code. Toutes les preuves sont encore NotRun pour cette roadmap. Le [registre](requirements/software-ecosystem-factory.requirements.json) détaille Given/When/Then et liens de kinds :

Les libellés et vérifications sont générés dans le contrat de livraison ci-dessous depuis le registre RaC canonique.

La qualification couvre aussi les garanties actuelles affectées : Outcome/Execution/Completeness, sélection des handlers, flux bornés, import/host compatibles et distribution depuis les paquets. Les choix de retrait/compatibilité des consommateurs Events sont à trancher avant le lot concerné.

[WorkspaceHost](ROADMAP-SoftwareEcosystem-WorkspaceHost.md) gère placement et tooling hôte ; [Migration](ROADMAP-Migration-FrenchExDev2.md) décide comment reprendre l’existant. Aucun déplacement ou changement d’identité publique QuietCli n’est nécessaire au chantier Core. [Vagrant](ROADMAP-Bundle-Extensions.md) peut partager son parsing tout en conservant cette unique voie d’exécution injectable.

<!-- roadmap-contract:begin -->
## Contrat de livraison et revue d'ingénierie

Vue générée depuis [le modèle des roadmaps](requirements/software-ecosystem-factory.roadmaps.json). Modifier le modèle, puis exécuter `scripts/Invoke-RoadmapContract.ps1 -Apply` ; les AC restent dans [le registre RaC](requirements/software-ecosystem-factory.requirements.json).

**CORE** — product — Évolution QuietCli indépendante du chemin minimal i3.

Composer routage, exécution et événements sans bloquer drainage ni runspace appelant.

| Kind | Livrable planifié et vérifiable |
| --- | --- |
| design | Contrats executor/middleware/routes/scheduler/bus et rupture Events versionnée |
| impl | Six jalons Core existants, adaptateurs et collecteur explicite ; bus externe en compagnon |
| test | Compagnons C#/PS et natifs affectés, drainage concurrent, isolation, fuzz séquences et mutants lifecycle |
| obs | Corrélation, files bornées, raisons du routage, santé persistante et fermeture des watchers |

Traçabilité : CORE-001, CORE-002, CORE-003, CORE-004, CORE-005, CORE-006, CORE-007, CORE-008. Lots : CORE. Une relation de lot est un prérequis de livraison, pas un import runtime.

| ID | Exigence | Vérification prévue |
| --- | --- | --- |
| CORE-001 | Aucun événement n’est collecté ou livré automatiquement dans les résultats finaux. | CORE-001-AC1 → CORE-001-T1 (contract, NotRun) |
| CORE-002 | Chaque appel descendant utilise le lanceur injecté sauf surcharge explicite. | CORE-002-AC1 → CORE-002-T1 (property, NotRun) |
| CORE-003 | Routage et middleware sont explicables sans exécution métier. | CORE-003-AC1 → CORE-003-T1 (contract, NotRun) |
| CORE-004 | Les réactions progressent sans bloquer le drainage et respectent le runspace PowerShell. | CORE-004-AC1 → CORE-004-T1 (integration, NotRun) |
| CORE-005 | Politiques de timing, rôle, cardinalité et erreur ont des comportements distincts. | CORE-005-AC1 → CORE-005-T1 (property, NotRun) |
| CORE-006 | InProcess et un adaptateur externe partagent les contrats sans imposer de broker. | CORE-006-AC1 → CORE-006-T1 (fault, NotRun) |
| CORE-007 | Ready et Healthy sont prouvés séparément et le statut UI survit aux lignes suivantes. | CORE-007-AC1 → CORE-007-T1 (integration, NotRun) |
| CORE-008 | L’arrêt clôt les tâches, watchers et abonnements sans attendre leur propre surveillance. | CORE-008-AC1 → CORE-008-T1 (fault, NotRun) |

**Décision de patterns : Pipes and Filters + middleware + explicit scheduler.**

Contexte : Des listeners doivent lancer des réactions pendant une source native.

Problème : Un appel bloquant dans Emit peut empêcher le drainage.

Forces : Runspace PS, flux bornés, effet externe inconnu et séparation événements/résultats.

Participants : Routeur sélectionne ; middleware compose ; executor lance ; scheduler draine ; bus distribue ; UI observe.

Collaboration : Les callbacks restent sur le runspace appelant ; les déclenchements passent par une file bornée.

Conséquences : InProcess n'exige aucun broker ; Reactor/Active Object restent analyses conditionnelles, pas threads imposés.

Alternative : Weaving implicite, deuxième lanceur ou IPC systématique rejetés.

Oracle indépendant : Une réaction démarre avant fin de source sans bloquer ses flux ; arrêt sans tâche/abonnement survivant.

**SOLID / DRY / MODULAR :** SRP routage/orchestration/analyse/processus ; DIP executor/bus ; ISP des capacités ; DRY de l'exécution ; rupture Events explicite.

Entrée : FAC et décision de compatibilité des consommateurs actuels Events.

Sortie : Six jalons qualifiés dans leur ordre interne ; matrices actuelles et consommateurs affectés préservés.

Risque : Un nom async ne démontre ni concurrence effective ni sécurité du runspace.

Responsable : Unassigned. État des livrables produit : Planned. PlanConsistent contrôle la structure proposée ; ImplementationReady exige les décisions/versions/responsables ; I3Accepted et ReleaseReady exigent leurs preuves propres. Les quatre kinds restent orthogonaux, avec design, tests et observabilité travaillés ensemble.
<!-- roadmap-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
