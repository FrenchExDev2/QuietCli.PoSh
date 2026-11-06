<p align="center">
  <img src="./../icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Core.PoSh

PowerShell Core 7.6+ facade for the C# .NET 10 / .NET 11 RC engine, with integrated or isolated hosting. Sources live under `engine/`; compatible integrated assemblies and isolated publications are selected from `lib/`. No SDK is required to import or use a built module.

Import reads the integer protocol specification through asynchronous host .NET file I/O and `System.Text.Json`, with the existing version and frame-size bounds. Source paths and alias creation also use host APIs, so import does not autoload the Management or Utility cmdlet modules. Engine initialization remains lazy. The companion's focused `Import` suite measures fresh-process loading; `RealStatus` checks direct callbacks on explicitly selected real repositories without the Git companion.

The same C# sources also build for `net10.0` under `lib/inprocess`. Set `$env:QUIETCLI2_ENGINE_MODE='InProcess'` before starting the engine to host it directly in PowerShell 7.6. `Stop-QuietEngine` closes the current session before a mode change. The .NET 11 assembly is loaded only when the actual PowerShell CLR is .NET 11 or later. `Auto` is the default hosting mode; it selects a compatible integrated build. `Get-QuietEngine` reports `Mode`, actual runtime, process identity and real pipe counters (zero in direct mode). Native reads and input/lifecycle controls use direct objects and byte arrays. Startup and telemetry use closed local metadata operations. Only internal raw queries and rejected-request diagnostics retain transport JSON; persisted SQLite metadata still uses its validated JSON representation. `DirectRequests` and `MetadataJsonRequests` count the selected request paths; their sum is `Requests`. These counters describe dispatch, while the protocol byte counters measure actual pipe traffic. Business Data and callbacks remain caller-local.

`New-QuietByteRecordFramer` provides bounded compiled byte framing without IPC; Git uses it even with the isolated host. Loading is lazy and verifies the integrated build compatible with the actual CLR. Start a new PowerShell process after rebuilding a loaded assembly. Direct hosting shares the host's failure boundary: disposal cancels owned native processes, but cannot forcibly kill or unload code inside PowerShell. Keep `Process` when that isolation is required. See [hosting measurements](../docs/performance-and-hosting.md).

`TextStreamState` handles strict incremental UTF-8 decoding and delimiter framing locally, without IPC. `Get-QuietCliGain` delegates safe telemetry aggregation to the SQLite worker and receives only counters and aggregate group pages. Caller callbacks and business objects stay in PowerShell. See [the second migration pass](../docs/powershell-csharp-boundaries.md).

Les six publications sous `lib/engine/<RID>` ciblent Windows x64/ARM64 et Linux glibc/musl x64/ARM64, avec `PlatformTarget` x64 ou ARM64 et un apphost natif de même architecture. La façade sélectionne le RID réel de PowerShell. Le build vérifie l’assembly PE et l’apphost PE ou ELF sans charger l’assembly moteur dans l’hôte. Le runtime .NET 11 RC correspondant reste requis ; aucune compilation NativeAOT n’est impliquée. Le build portable reste réservé aux références et tests.

Les paquets PSGallery embarquent aussi SQLite et les bridges PTY statiques des quatre RIDs Linux. Le moteur copie le bridge vérifié dans son répertoire privé exécutable ; il ne modifie pas un module installé en lecture seule. Les imports restent inertes.

## Contrat

Opt-in [Recall capture and offline analysis](../docs/recall.md) retains native bytes only with explicit `-Recall -AsObject`. `-RecallMaxBytes` accepts integral bytes, IEC sizes or `All`; `-RecallPolicy` selects `Head`, `Tail` or `HeadAndTail`. `Invoke-QuietRecall` reuses decoding without executing a process. `-SaveRecall` writes a durable journal during execution; `-RecallName`, `Get-QuietSavedRecall` and `quiet -RecallId` support later sessions with new callbacks and delivery projections. Default export is a streaming working directory; `-Zip -Compress 0..9` explicitly selects measured ZIP64 transport. Evidence remains excluded from ordinary deliveries and SQLite. The no-retention statements below describe the default streaming path.

`Invoke-QuietCli`, alias `quiet`, accepte ses options avant le binaire. `-Output` reçoit un événement et le runtime ; `-Complete` finalise `runtime.Data`. Sans ces callbacks, le registre choisit un handler documenté et compatible. Les imports restent inertes.

Les flux natifs sont consommés une seule fois. Le moteur garde uniquement les bytecounts et des buffers bornés. Il ne crée ni capture cumulative, ni spool, ni historique de contenu. Les événements bytes ont un `ByteCount` et des `Bytes` transitoires ; le cadrage texte conserve seulement un fragment inachevé borné. Un dépassement ou UTF-8 incomplet échoue explicitement.

`-AsObject` retourne l’enveloppe et l’objet local sans parcours, sérialisation ou transfert de `Data` au moteur. JSON/YAML produisent et mesurent uniquement leur représentation réelle, bornée par `MaxItems`, une limite structurelle et `MaxOutputBytes`. Le dernier texte livré est disponible dans `Deliveries[0]` avec son identifiant ; les chaînes de livraisons successives ne s’accumulent pas.

```powershell
# Objectif : compter des bytes sans conserver leur contenu.
$r = quiet -AsObject -C analyse -StdoutMode Bytes -Data @{ Bytes = 0L } -Output {
    param($event, $runtime)
    $runtime.Data.Bytes += $event.ByteCount
} executable arguments
```

Ne rien émettre depuis `Output` ; utiliser `[void]` pour les méthodes qui retournent une valeur. `Complete` retourne zéro ou une valeur. Pour un tableau, utiliser `,$array`. Les callbacks restent dans le processus appelant et doivent coopérer avec l’annulation.

## Runtime et transports

Le runtime fournit `Request`, `Data`, `State`, `Execution`, `Children`, les identifiants et `WriteBytes`, `WriteText`, `CompleteInput`, `ReadEvent`, `Resize`, `Cancel`.

Le transport pipe distingue stdout/stderr. PTY fusionne les sorties dans `TerminalBytesRead` ; les compteurs séparés sont inconnus. Windows utilise ConPTY ; Linux utilise un bridge vérifié par SHA-256. La fin d’entrée d’un terminal n’est pas une demi-fermeture de pipe.

Les appels enfants héritent du contexte ; ils retournent un objet par défaut. Leurs échecs sont conservés même lorsqu’ils sont affectés à une variable. `quiet -C nom` ne modifie pas le contexte des appels indépendants suivants.

## Mesures

`Get-QuietCliGain` lit tous les contextes par défaut. `-C nom`, `-Generic`, `-SessionId`, `-From`, `-To` filtrent le rapport. Les sources uniques sont dédupliquées ; les réductions inconnues restent nulles. Les rôles auxiliaires ne gonflent pas le gain métier.

Les tokens natifs restent inconnus. La tokenisation exacte, optionnelle, concerne uniquement une livraison déjà produite : `-Tokenizer o200k_base` ou `cl100k_base`. Le défaut est `off`.

SQLite enregistre uniquement les métadonnées et compteurs. `QUIETCLI2_DATABASE` choisit la base ; `QUIETCLI2_TRACKING=0` désactive les écritures. Les erreurs de stockage restent séparées du résultat métier. Aucun RECORD/replay.

## Tests et dépendances

Le module compagnon est `FrenchExDev2.QuietCli.Core.Tests.PoSh`. Il contient les projets C# de test et les assertions PowerShell. Le module métier ne contient pas les tests. Les ressources natives sont distribuées par RID ; un RID non fourni ne doit pas être présenté comme qualifié.

Le SDK et le runtime sont verrouillés dans `global.json` et le projet C#. Une rupture du moteur ne rejoue aucune opération et peut laisser son effet inconnu.

## Limites, intégrité et confidentialité

`-DrainTimeoutSeconds` borne l’attente d’EOF après sortie du processus (30 s par défaut). Une coupure de drainage rend la source incomplète, même si le processus principal a déjà terminé. `QUIETCLI2_IPC_TIMEOUT_SECONDS` borne chaque échange avec le moteur (30 s par défaut, entre 0,05 et 300 s). Un défaut de transport ferme le moteur détenu et conserve l’effet inconnu d’un démarrage non confirmé. Un nouvel appel racine indépendant peut démarrer un nouveau moteur ; l’appel interrompu n’est jamais répété.

`Execution` et `Completeness` du résultat final sont des snapshots détachés en lecture seule. Les transitions du runtime sont validées. `Data` reste locale et modifiable pour les prochaines livraisons.

Les diagnostics détaillés restent locaux. SQLite n’accepte que des DTO fermés, y compris les propriétés imbriquées ; les erreurs persistées contiennent leurs codes et phases, sans message de callback. Les anciens événements sont projetés vers les seuls champs autorisés à la lecture, sans réécriture implicite. Pour expurger volontairement leurs anciens champs :

```powershell
# Objectif : examiner l’expurgation explicite de la base sélectionnée sans modifier l’historique.
Repair-QuietCliMeasurementPrivacy -WhatIf

# Objectif : expurger les anciens champs sensibles après confirmation interactive explicite.
Repair-QuietCliMeasurementPrivacy
```

Cette opération modifie définitivement les lignes de la base choisie. Elle ne garantit pas l’effacement physique des sauvegardes ou du support. Aucune expurgation n’est exécutée par l’import, le build ou les tests sur une base utilisateur.

`Get-QuietCliGain -MaxEvents 10000` utilise une pagination par curseur et budget IPC ; `Complete=false` signale un rapport arrêté par sa limite. Les erreurs de requête restent distinctes des fautes de transport.

`resources/dependencies.lock.json` attache les ressources embarquées à leurs versions, empreintes et licences sous `third_party`. L’intégrité est vérifiée avant démarrage du moteur et chargement du tokenizer. Une SQLite embarquée présente mais invalide échoue explicitement ; le repli se limite aux chemins système absolus. Un checksum ne prouve ni l’identité d’un auteur ni l’absence de vulnérabilité connue.

Le build produit un manifeste liant sources C#, SDK, protocole et fichiers compilés. Les tests refusent un build périmé ou modifié, y compris avec `-SkipBuild`. `protocol.json` fournit les limites communes à C# et PowerShell.

See [performance measurements and mandatory Core-only CI integration](PERFORMANCES.md) for historical comparisons, controlled repository states, matrix scope, artifacts and reproduction commands.
