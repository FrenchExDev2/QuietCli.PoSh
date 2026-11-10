# FrenchExDev2 — progression codifiée, sélection de migration et registre localhost

Date : 10 novembre 2026. Portée : planning et outils de validation/exploration ; aucun déploiement i3, création GitHub, migration/cutover de produit ou publication publique.

## Décisions et livrables

L'utilisateur a corrigé la cible : i3 doit être un checkout Git personnel de `stephaneerard`, identité logique « moninstanceàmoi », avec préférences/configuration portables suivies et état machine/secrets/données des registres exclus. Les dépôts d'écosystèmes hébergés sont indépendants et ignorés par l'index hôte. Le slug/visibilité du futur remote restent à décider. Le nom **FrenchExDev2.SoftwareContract** est explicitement validé ; le contenu du standard reste proposé.

Le portefeuille vise **Conduit IEC61499 PowerShell/C# encapsulant QuietCli**, dont Quietly est la prononciation documentée. i3 fournit les moyens : seed indépendant, feeds locaux PSResource/NuGet, puis adaptateurs Manager de lifecycle. Les graphes proposés restent sans cycle ; seed N peut produire N+1 sans s'exiger lui-même. Une dépendance de livraison n'interdit pas de concevoir/tester le consommateur plus tôt.

Baseline finale : **21 roadmaps, 93 exigences, 76 workItems, 32 recettes et 13 vagues structurelles**. Les blocs par fichier sont générés depuis les modèles canoniques. Chaque lot fournit producteur/vérificateur/canal/ressources et consommateurs débloqués. Les recettes Proposed ne sont pas dispatchées ; les moyens de planning livrés s'exécutent réellement pour inspecter, valider et générer. Les canaux LocalBoth exigent les deux feeds dans la fermeture ; des locks distincts permettent le parallélisme sans collision déclarée.

Les logiciels à produire suivent identification/fermeture → workspace InstanceManager seed → conteneur source par kind → implémentation/qualification → preview locale draft1/dev1 → restauration isolée → consommateur. Fonctions exportées/cmdlets portent le métier ; façades, docs et tests compagnons suivent. Chaque argument PS est challengé (type, domaine, validation statique/configurée, défaut, complétion et effets) ; ShouldProcess/WhatIf protège toute mutation. Le standard ne certifie pas mécaniquement SOLID/POSA/ISO.

## Moyens de migration exécutés

La whitelist versionnée est deny-by-default et contient 13 **candidats d'évaluation**, tous non approuvés pour migration. Le validateur inspecte les AST PS, manifestes, solutions/projets et XML de build sans exécuter les sources ni MSBuild. Il retient les empreintes et états des imports/projets/packages/commandes. Les calculs dynamiques, dépendances non déclarées, cycles et graphes évalués manquants bloquent. Un rapport statique ne démontre pas les dépendances runtime/réflexion/natives.

`Test-MigrationGate.ps1` exige des rapports frais, qualification du validateur lui-même (hashes et campagnes property/fuzz/mutation), exports réels des modules, tests produit/restauration isolée/retour. Des hashes cohérents prouvent l'identité des pièces, pas leur suffisance métier ; le responsable conserve cette décision. Aucun candidat n'est déclaré migré dans cette passe.

La première photographie des 13 candidats contient 544 fichiers inspectés et 13 188 références/commandes déclarées, avec 96 diagnostics agrégés. La photographie finale, après ajout des régressions du contrôleur, contient 544 fichiers et 13 213 références, toujours 96 diagnostics. Les commandes dynamiques et décisions d'environnement non prises expliquent ces manques ; ce ne sont pas 13 échecs de tests métier. La gate revalide les empreintes et invalide un rapport si un fichier inspecté évolue. Le rapport final `i2-whitelist.dependencies.json` est conservé avec la campagne finale.

Kubernetes possède un manifeste, un loader psm1 et un fichier de symboles ; ses sous-dossiers vides ne rendent pas tout le module vide. Après copie vérifiée et **import réel**, Get-Module observe version 0.0.1, **0 fonction, 0 cmdlet, 0 alias**. Le chargement réussit et aucun output incident n'est observé. La sonde n'avait pas de contrat d'exports accepté : Qualification=NotAssessed. C'est un candidat à structurer/évaluer, sans comportement Kubernetes migré inventé. Une structure .gitkeep seule est séparément ScaffoldCandidate et nécessite une décision Create.

## Validation des outils

Campagne complète, non filtrée : **338 contrôles réussis, 0 échec** — 61 exemples/contrôles de faute, 235 propriétés, 34 entrées malformées/bornes et 8 mutants détectés, aucun survivant dans ce catalogue ciblé. Seed : 20261110. Hôte : PowerShell 7.6.9 / Windows x64. Les imports témoins sont de vrais processus séparés ; les moniteurs dédiés sont visibles et se ferment après sauvegarde des états terminaux.

Les cas indépendants couvrent notamment ordre des arêtes, exclusivité des ressources, fermeture des canaux de livraison, whitelist et approbation, chemins, XML DTD, imports absents, cycles, .gitkeep, WhatIf, export public/privé, fraîcheur des preuves et obligation de qualifier le contrôleur. Le catalogue mutation porte sur cycles, livrables, preuves indues, inventaire, sélection, approbation, ShouldProcess et locks. Aucune couverture instrumentée ou exhaustivité de fuzz/mutation n'est revendiquée. Les gates produit I3/Conduit/Release restent non passées.

Diagnostic conservé : une campagne intermédiaire s'est arrêtée après 312 succès, parce que l'import/suppression des modules mutants avait masqué la fonction originale Test-MigrationQualification. Le compagnon recharge désormais explicitement la bibliothèque réelle après les mutants ; la campagne complète suivante est réussie. Ce défaut du harness n'est pas un échec produit.

Rapport complet final : `C:/Users/serard/AppData/Local/Temp/QuietCli2/874a99c9b658/tests/roadmaps-20261110-074700-9c1c84/summary.json` ; SHA-256 `294C3EC98575CC56935AE01ECAA7A089E8DE4D82F03285853470C70B5681A8A9`. Les identités des sources, catégories, cas et mutants sont dans ce bundle. Réouverture du moniteur :

```powershell
./scripts/Watch-Tests.ps1 -RunDirectory 'C:/Users/serard/AppData/Local/Temp/QuietCli2/874a99c9b658/tests/roadmaps-20261110-074700-9c1c84'
```

## Faisabilité d'un feed PSResource en conteneur localhost

Le contexte Docker du poste utilise Podman 6.1.4 sur Linux/WSL2. Le serveur réel BaGet a été démarré avec port publié sur loopback et ressources jetables uniques. [La documentation primaire du fournisseur](https://loic-sharma.github.io/BaGet/installation/docker/) définit son endpoint NuGet v3 ; la compatibilité PSResourceGet a ensuite été mesurée, pas supposée.

La ronde **Automatic** échoue : PSResourceGet 1.2.0 ne trouve pas DevDependency preview pour la plage `[0.0.1, )` dérivée du manifeste. La ronde **PinnedClosure**, choisie explicitement ensuite, publie avec précheck de dépendance désactivé, restaure la dépendance à sa version exacte puis le consommateur sans résolution récursive. Aucun fallback silencieux entre les modes. Elle réussit depuis **Windows PowerShell 7.6.9** et **Linux PowerShell 7.6.7**, clients PSResourceGet 1.2.0 : `42`, `draft1`, mêmes SHA-256 des trois modules. Cela démontre le dépôt localhost CLI et la consommation par fermeture épinglée ; la résolution automatique reste non qualifiée. [Compatibilités PSResourceGet](https://learn.microsoft.com/en-us/powershell/gallery/powershellget/supported-repositories?view=powershellget-3.x).

Image serveur exécutée : ID local `sha256:c66780acc1278f7727671e6523a5fc9236b883d430058c6b9a348a2011be8f09`. Ce n'est pas un digest de manifeste de registre : une tentative intermédiaire utilisant cet ID comme digest de pull a été refusée et reste conservée comme erreur d'entrée ; aucune conclusion de compatibilité n'en découle. Le run réussi résout le tag choisi puis exécute l'ID local exact. Les futurs profils produit devront épingler leur référence de registre correcte.

Preuves conservées sous `C:/Users/serard/AppData/Local/Temp/QuietCli2/874a99c9b658/gallery-validation/` : échec Automatic `local-8d19e91f8e444c578aadd7637fb1d17f`, erreur de référence d'image `local-8a40d4dbbd7648b49329b4f23ff2dc08`, succès PinnedClosure `local-c738e9cf42324fee83e43088ca9f9e84`. Le succès comporte les deux summaries clients et tous les reçus de retrait serveur/client/volume/network. Pas de feed utilisateur modifié ou de publication publique dans ce parcours ; les clients ont des chemins utilisateur isolés.

PSREG1 complet exige encore redémarrage persistant, backup/restore, conflits/concurrence, corpus hostile et mutations propres, ainsi que toute autre plateforme promise. Les campagnes Core/Git/Vagrant existantes ne sont pas relancées : leurs comportements produits n'ont pas changé. Ce travail ne qualifie pas les produits inspectés, ne crée pas i3 et n'autorise aucune bascule.

Les preuves détaillées restent temporaires et peuvent disparaître lors d'un nettoyage système ; le présent audit conserve leurs résultats bornés et limites. Les documents historiques et l'archive du plan source restent inchangés ; ce document attribue les nouveaux constats à leur propre exécution. Les changements préexistants AGENTS.md, docs/README-scripts-have-docs.md et Update-Packages.ps1 sont préservés et exclus du checkpoint de ce travail.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
