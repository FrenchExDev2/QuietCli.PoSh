# CI Windows 11 ARM64

Le workflow PR exécute désormais deux jobs Windows indépendants : `windows-latest` / `win-x64` et `windows-11-arm` / `win-arm64`. Les deux construisent avec le SDK .NET épinglé puis exécutent les mêmes suites Core et Git, sans ignorer les scénarios en ARM64. Les artefacts sont séparés par RID.

La cible `windows-11-arm` est une machine virtuelle hébergée par GitHub, pas une image OCI locale. Voir la [liste officielle des runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) et le [contenu publié de l’image Windows 11 ARM64](https://github.com/actions/runner-images/blob/main/images/windows/Windows11-Arm64-Readme.md). Ce label évolue ; le rapport conserve la version réellement utilisée. Il ne constitue pas un verrouillage reproductible du disque système. L’éligibilité du dépôt et les conditions de facturation du runner doivent être vérifiées avant son activation distante.

`Build-Workspace.ps1` publie le moteur C# deux fois : `lib/engine/win-x64` avec `PlatformTarget=x64`, puis `lib/engine/win-arm64` avec `PlatformTarget=ARM64`. Chaque distribution contient l’assembly et son apphost Windows natif. La publication est framework-dependent : le runtime .NET 11 RC de l’architecture correspondante reste requis. Il s’agit de C# exécuté par le JIT ARM64, pas d’une publication NativeAOT.

Les en-têtes PE de l’assembly et de l’apphost sont vérifiés indépendamment : `0x8664` pour x64 et `0xAA64` pour ARM64. Leurs empreintes et paramètres de compilation figurent dans les manifestes de build. Le packaging exige les deux distributions et les embarque dans le module Core.

`Invoke-WorkspaceCi.ps1 -ExpectedRuntimeIdentifier win-arm64` exige cette architecture pour PowerShell et pour le processus moteur séparé, ainsi qu’une publication `win-arm64`. La façade sélectionne le répertoire du RID courant et démarre son apphost. Une exécution x64 émulée échoue. Les rapports enregistrent RID, architectures OS/processus, description OS, nom de machine, PID du moteur, empreinte de son assembly et identité de build. SQLite est livrée sous `resources/runtime/runtimes/win-arm64/native`. Windows PTY utilise ConPTY.

Sur un hôte Windows ARM64 préparé :

```powershell
# Objectif : construire et tester localement sur ARM64, avec une fenêtre de suivi visible.
./scripts/Invoke-WorkspaceCi.ps1 -ExpectedRuntimeIdentifier win-arm64
```

Une ISO seule ne permet pas d’exécuter la CI : il faut un invité installé avec PowerShell 7.6+, .NET 11 RC et Git, un disque de travail isolé et un transport de rapports. Ne pas renommer une base x64 en ARM64. Aucun disque utilisateur ni base existante n’est modifié par ce workflow.

La référence récupérée sur GitHub est la documentation du runner `windows-11-arm`, pas un disque local téléchargé. Ce job utilise donc directement l’image GitHub. Le workflow est configuré ; aucune réussite ARM n’est revendiquée avant un rapport provenant de ce runner.
