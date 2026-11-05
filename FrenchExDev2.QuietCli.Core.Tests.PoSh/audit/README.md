# Régressions de l’audit sécurité et logiciel

Depuis le workspace QuietCli2 :

```powershell
# Objectif : vérifier les correctifs avec des données synthétiques et une fenêtre de suivi visible.
./FrenchExDev2.QuietCli.Core.Tests.PoSh/audit/Invoke-Audit.ps1
```

Le lanceur Windows construit les fixtures puis ouvre le moniteur partagé. Les fixtures, la base SQLite et les preuves restent sous `artifacts/audit/<run>`. La suite Core appelle aussi ce worker sous son propre moniteur et conserve ses preuves sous `artifacts/security-regressions/<run>`. Aucun secret réel, dépôt de l’utilisateur, remote, service système ou source produit n’est modifié. La simulation de perte d’accusé de lancement remplace une fonction uniquement dans le processus de test et restaure sa définition.

`summary.json` donne `Resolved`, `Unresolved` et chaque invariant attendu. Un seul invariant non satisfait fait désormais échouer le worker. Les anciens rapports de l’audit initial restent historiques : leurs compteurs de constats confirmés ne sont pas des contrôles réussis.

Les petits paquets synthétiques contrôlent l’absence d’import implicite, les frontières des modules, les doublons de casse, les traversées de chemins et les quotas. Tout fichier témoin créé constitue un échec. Le contrôle positif vérifie des données sans exécuter les modules. Le bootstrap isolé doit rejeter une ligne de 16 Mio sans l’accumuler. Les permissions privées des artefacts sont contrôlées sur Unix.

Les assertions C# du compagnon vérifient séparément la fin de flux, le drainage annulé, la pagination SQLite et la projection des anciennes métadonnées. Elles utilisent des canaux factices indépendants du transport réel. L’expurgation ne touche qu’une base synthétique dédiée : aucun nettoyage automatique de l’historique utilisateur n’est lancé.
