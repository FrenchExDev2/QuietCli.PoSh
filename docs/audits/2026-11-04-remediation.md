# Correctifs de l’audit sécurité et logiciel

Ce document répond à l’[audit initial](2026-11-04-securite-logiciel.md), conservé comme preuve historique. Les anciennes reproductions restent datées et ne sont pas transformées rétroactivement en contrôles réussis. Aucun commit, push, déploiement, installation sur l’hôte ou nettoyage de base utilisateur n’est exécuté implicitement.

## Résultats enregistrés le 5 novembre 2026

| Plateforme exécutée | Suites PowerShell | Assertions C# internes | Régressions sécurité |
|---|---|---|---|
| Windows x64 | 62/62 : 30 Core + 32 Git | 12/12 | 18 résolues, 0 non résolue |
| Alpine / musl x64 | 62/62 : 30 Core + 32 Git | 12/12 | 19 résolues, 0 non résolue |
| Debian / glibc x64 | 62/62 : 30 Core + 32 Git | 12/12 | 19 résolues, 0 non résolue |

Les sous-assertions C# et sécurité sont incluses dans des scénarios Core : ces colonnes ne s’additionnent pas pour inventer un total de tests indépendants. Le scénario Unix supplémentaire vérifie les permissions réelles 0700/0600. Les [preuves JSON](2026-11-05-remediation-evidence.json) donnent chemins, empreintes, identités et états observés.

Rapports complets : [Windows](../../artifacts/tests/20261104-230842-c39ea2/summary.json), [Alpine](../../artifacts/containers/alpine-20261104-230030-e516b1/guest/summary.json), [Debian](../../artifacts/containers/debian-20261104-230122-a480fb/guest/summary.json). Les noms de run utilisent UTC ; les fins locales sont le 5 novembre. Après découverte d’un défaut de résolution des chemins relatifs du packaging, le scénario existant a été renforcé et la suite Windows complète a été réexécutée avec succès. Les runs Linux précèdent cette dernière correction administrative ; ils utilisent le même moteur compilé et leurs snapshots de sources distincts sont conservés.

La compilation croisée du moteur ARM64 est réussie et ses en-têtes PE sont vérifiés. L’exécution native ARM64 sur GitHub reste non effectuée. La construction de la nouvelle image Debian à partir du snapshot daté a échoué sur des réponses HTTP 503 « No healthy backends » de `snapshot.debian.org`. Les tests Debian réussis utilisent l’image locale précédente, identifiée par son ID dans le rapport ; ils ne valident pas cette nouvelle construction d’image.

Les conteneurs des runs sont arrêtés. Leurs demandes de suppression Podman ont dépassé leur délai et leur nettoyage reste non confirmé, séparément du succès des tests. Aucun redémarrage ou nettoyage global de Podman n’a été effectué. Ces limites d’environnement ne sont pas présentées comme résolues.

## Correctifs et vérification

| Constat | Correctif | Contrôle conservé |
|---|---|---|
| SEC-01 | Ensemble exact des quatre modules, frontières ZIP/manifeste, chemins portables, doublons de casse, types d’entrées, quotas avant et pendant décompression, vérification avant extraction/import ; destination privée et renommage final | Ancien paquet rejeté ; six petits scénarios indépendants dont un positif sans import |
| REL-01 | Lancement demandé distingué du lancement accusé ; effet inconnu et source incomplète après perte de réponse ; aucun rejeu | Injection après création réelle : une seule création, `Unknown`, source incomplète |
| REL-02 | Pagination par curseur et budget en bytes, limite de rapport explicite, distinction rejet/transport | 180 événements consultés exactement une fois en plusieurs pages sous le plafond IPC |
| REL-03 | Dictionnaires et union de références avec comparaison ordinale | Deux références différentes par casse, un changement indépendant attendu |
| REL-04 | Possession du sink dans un `try/finally` externe aux callbacks ; résultat métier explicite ; suppression du fichier incomplet | Démarrage refusé : aucun stream exposé, aucun fichier conservé |
| SEC-02 / SEC-03 | DTO fermés récursifs, erreurs Code/Phase uniquement ; projection sûre des anciennes lignes sans modification automatique | Rejet de Data imbriquée/messages ; diagnostic local conservé ; projection sans écriture et expurgation explicitement confirmée sur base synthétique |
| SEC-04 | Répertoire Unix 0700, fichier 0600 à la création | Contrôle Unix des permissions réelles |
| SEC-05 | Lecture administrative par blocs et limite explicite des records ; arrêt possédé en `finally` | Ligne de 16 Mio sans délimiteur refusée avec mémoire managée bornée |
| SEC-06 | Inventaire versions/empreintes/licences, vérification avant chargement, repli SQLite limité aux chemins système absolus ; actions et images épinglées, paquets Debian via snapshot daté | Ressources vérifiées au démarrage et lors des suites/distributions ; nouvelle construction d’image à distinguer de l’utilisation des images antérieures |
| DES-01 | Retrait des seuls suffixes natifs reconnus ; conservation du nom d’un binaire avec point | Handler d’un exécutable au nom pointé sélectionné |
| REL-05 | Délai de drainage configurable ; interruption distincte d’EOF, source incomplète | Canal C# indépendant ne produisant jamais EOF puis canal fini de trois bytes, sans course sur un processus hérité |
| REL-06 | Délais propres aux lectures/écritures/arrêt IPC, arrêt du moteur détenu, classification de panne | Stream de contrôle qui ne répond jamais : échéance mesurée et connexion marquée rompue |
| CI-01 | Construction avant transport, provisionnement explicite d’image par digest, watchdog des workers et moniteur réarmé | Suites locales et conteneurs ; exécution GitHub conditionnée aux remotes/révisions/images réellement renseignés |
| REL-07 | Identités des cinq dépôts, manifeste de build sources/SDK/protocole/binaires, vérification même avec SkipBuild, rejet des changements pendant build/run, image résolue par ID | Binaire modifié et source périmée rejetés ; identité réelle du moteur jointe aux rapports |
| États finaux mutables | Transitions validées, snapshots détachés en lecture seule, propriétés finales sans setter | Modification interne et remplacement du snapshot refusés, référence du runtime détachée |

## Conception

Le JSON est adapté vers `InvocationRequest` typé à la frontière. Une fabrique de canaux asynchrones est injectée dans l’invocation ; les tests de drainage substituent un canal indépendant. Le redimensionnement est une capacité `ITerminalChannel`, distincte du contrat pipe.

Le modèle de mesures, sa validation et sa projection sont séparés du worker SQLite. La politique de callbacks zéro/une émission et les transitions de finalisation sont centralisées. Les paramètres communs du protocole viennent de `protocol.json`.

Git utilise un catalogue unique de fonctions de handlers et un lecteur commun de groupes de champs NUL, sans déplacer sa grammaire dans Core. L’écriture stdin comptée est partagée entre les producteurs. Les identités de sources/builds et la supervision des workers sont communes aux lanceurs. Le lexer Git et l’orchestrateur PowerShell sont mis en forme ; les règles métier existantes restent couvertes par les assertions du compagnon.

Ces extractions ciblées ne prétendent pas rendre toute classe immuable ni découpler toute instruction SQL derrière une interface. L’orchestrateur garde la responsabilité d’ordonner l’exécution. Le processus moteur .NET 11 reste séparé de PowerShell et aucun objet métier n’est sérialisé pour les gains `-AsObject`.

## Confidentialité de l’historique

Les nouvelles écritures n’enregistrent plus les messages bruts. Les anciennes lignes sont filtrées à la lecture. L’effacement automatique des anciens diagnostics a été refusé par le contrôle automatique d’approbation car il aurait irréversiblement modifié l’historique sans autorisation spécifique. La solution retenue conserve cet historique et fournit `Repair-QuietCliMeasurementPrivacy`, avec `-WhatIf` et confirmation explicite. Cette commande n’a pas été exécutée sur une base utilisateur.

Une rupture du moteur ne relance jamais l’opération interrompue. L’autorisation de redémarrage s’applique au prochain appel racine indépendant, après fermeture de la connexion rompue.

## Limites de preuve

Les rapports par run conservent états, cas, identités des sources/binaires et diagnostics. Une réussite des scénarios ne certifie pas l’absence de toute vulnérabilité, ni les 183 commandes Git et leurs variantes sur les 17 versions. La qualification complète reste explicitement incomplète.

La cible [Windows 11 ARM64](../ci/windows-arm64.md) est ajoutée au workflow avec contrôle d’architecture. Le moteur est publié pour x64 et ARM64, assembly et apphost vérifiés par en-têtes PE puis embarqués dans Core ; aucun run ARM distant n’est déclaré réussi sans preuve de ce runner. Les révisions/remotes non renseignés et les images CI non configurées restent des prérequis de publication ; les scripts ne les inventent pas.

L’inventaire des dépendances fournit une provenance et des licences, pas un audit exhaustif des avis de vulnérabilité. Les hashes n’authentifient pas un auteur de paquet. Le vérificateur n’exécute les modules qu’avec `-TestImport` explicite, après vérification de l’ensemble ; cette option exécute du code avec les droits de l’appelant.
