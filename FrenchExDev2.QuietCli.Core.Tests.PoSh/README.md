<p align="center">
  <img src="./../icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Core.Tests.PoSh

Module de tests indépendant du moteur. Dépend du module Core, jamais l’inverse.

- `fixture/` : producteur/consommateur C# de bytes dont les volumes sont connus indépendamment.
- `engine-tests/` : assertions C# de cadrage, limites, EOF, interdiction de stocker des objets métier et concurrence SQLite.
- Les treize assertions C# incluent la pagination par budget IPC, le drainage indépendant d’un processus réel, la projection/expurgation explicitement confirmée d’une base synthétique et le bridge PTY d’un module installé en lecture seule.
- Le module PowerShell vérifie les compteurs, Unicode fragmenté, NUL, stdin, 64 Mio de sortie, callbacks imbriqués, erreurs, timeout, annulation, PTY, contextes et formats.
- Un getter métier qui lève une exception prouve que `-AsObject` ne parcourt pas l’objet pour calculer les mesures.
- Les six publications Windows/Linux x64 et ARM64 sont contrôlées par leurs en-têtes PE/ELF, paramètres de compilation et manifestes ; ce contrôle statique ne remplace pas l’exécution native dans les jobs ARM.
- Les deux nupkg PSGallery sont préparés puis extraits dans une arborescence d’installation isolée. Un processus sans profil charge Git et sa dépendance Core depuis ces seuls paquets, démarre le moteur publié et vérifie Git dans un dépôt dédié. Ce contrôle local ne prétend pas télécharger une version déjà publiée sur PSGallery.
- Le harnais `audit/` fournit des régressions bloquantes ; la provenance rejette les binaires modifiés et les sources périmées. Le packaging est aussi vérifié avec des chemins relatifs puis importé hors des sources.
- `tools/documentation/` est un outil de maintenance explicite ; il ne s’exécute jamais pendant les tests ou les builds normaux.

Depuis le workspace : `./scripts/Invoke-WorkspaceCi.ps1 -Suite Core`. Le lanceur construit les projets et ouvre la fenêtre de suivi. Les rapports conservés comportent chaque assertion et son résultat. Les tests n’installent aucun outil sur l’hôte et utilisent leur propre base SQLite.

Une suite vide, un crash ou un prérequis manquant n’est jamais converti en succès.
