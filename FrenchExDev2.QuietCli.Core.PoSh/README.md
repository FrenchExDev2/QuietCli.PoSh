<p align="center">
  <img src="./../icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Core.PoSh

Façade PowerShell Core 7.6+ pour le moteur séparé C# .NET 11 RC. Le projet est sous `engine/`, la distribution compilée sous `lib/engine/`. Aucun SDK n’est requis lors d’un import ou d’une utilisation après construction.

Les six publications sous `lib/engine/<RID>` ciblent Windows x64/ARM64 et Linux glibc/musl x64/ARM64, avec `PlatformTarget` x64 ou ARM64 et un apphost natif de même architecture. La façade sélectionne le RID réel de PowerShell. Le build vérifie l’assembly PE et l’apphost PE ou ELF sans charger l’assembly moteur dans l’hôte. Le runtime .NET 11 RC correspondant reste requis ; aucune compilation NativeAOT n’est impliquée. Le build portable reste réservé aux références et tests.

Les paquets PSGallery embarquent aussi SQLite et les bridges PTY statiques des quatre RIDs Linux. Le moteur copie le bridge vérifié dans son répertoire privé exécutable ; il ne modifie pas un module installé en lecture seule. Les imports restent inertes.

## Contrat

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
