<p align="center">
  <img src="./../icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Git.PoSh

Handlers Git utilisant le moteur QuietCli2. Dépend explicitement de `FrenchExDev2.QuietCli.Core.PoSh >= 0.2.0`.

The current development manifests declare `0.2.0-preview`. The numeric Core dependency is now `>= 0.2.0`; prepared Gallery packages pin the exact `0.2.0-preview` companion package. Prerelease status describes the module release, independently of the stable/preview PowerShell host selected at runtime.

L’import enregistre un catalogue inerte. La première invocation observe la version du binaire ; les sondes suivantes utilisent un cache lié à son identité. La plage déclarée est Git stable `>= 2.40.0 < 2.57.0`, variantes `.windows.N` comprises. La compatibilité déclarée n’est pas une qualification de toutes les versions.

## Familles métier implémentées

- `status [-- pathspec...]` : porcelain v2 avec NUL, branche, HEAD, état initial/détaché, divergence des références locales, entrées et compteurs. Les formes courtes et les filtres de portée sont conservés ; `-v`/`-vv` ajoutent les patches métier correspondants. Aucun fetch.
- `commit` avec message explicite ou interaction fournie : une seule mutation, observation locale de HEAD avant/après. L’observation n’est pas un instantané atomique et ne prouve pas les effets secondaires des hooks.
- `push` : sortie porcelain analysée en flux, références, indicateurs et échecs partiels. Les tests utilisent un dépôt bare local.
- `diff` : fichiers, hunks et patches combinés ; conservation des marqueurs de fin de ligne et représentation explicite des bytes non UTF-8. Les formats alternatifs demandés restent des enregistrements métier du format demandé.
- `log` et `show` : identités complètes, parents, auteur, committer, sujet et corps sans plafond caché de commits. Les options de format explicites restent respectées. `show` vérifie le type Git de l’objet avant de traiter une sortie blob.
- `add`, `checkout`, `fetch` et `pull` : une seule exécution métier, observations locales avant/après et changements de références. Les effets des processus externes et hooks ne sont pas déduits de la seule sortie.
- `branch`, `stash` et `worktree` : listes structurées et mutations observées avant/après selon la forme demandée.
- `ls-tree` : entrées NUL typées, modes, types, identités, tailles et chemins, y compris espaces, Unicode et retours à la ligne.

```powershell
# Objectif : observer le dépôt choisi dans le contexte de mesure demandé.
$r = quiet -AsObject -C projet -WorkingDirectory $repository git status

# Objectif : distinguer séparateur PowerShell et séparateur natif.
$r = quiet -AsObject -- git status -- 'un fichier'
```

Les paramètres de QuietCli précèdent `git`. Les options globales de Git suivent `git`. Les entrées métier ne sont jamais envoyées à une sonde ou observation. Les parsers de formats machine exigent des pipes séparés ; une demande PTY incompatible échoue explicitement avant l’exécution métier. Un callback direct peut fournir sa propre analyse d’un terminal fusionné.

## Couverture et limites

`metadata/Git.Inventory.json` reprend les 183 entrées de l’inventaire officiel verrouillé, avec leurs versions. Les sources amont et empreintes sont sous `metadata/locks`. La grammaire pure conserve l’arité des options et les séparateurs ; elle ne suffit pas à établir leur validité sémantique.

`Get-QuietGitCoverage` distingue inventaire, implémentation et qualification. **L’inventaire complet n’est pas qualifié.** Des commandes supplémentaires ont des projections ou une première exécution native ; cela ne vaut pas support de toutes leurs variantes. Les contrats absents échouent explicitement. Les protocoles privés, contenus binaires et intégrations complexes nécessitent encore des handlers propres, sans réintroduire une capture universelle.

Les sorties ne sont pas conservées par défaut. Chaque parser ne retient que les valeurs métier dont il a besoin. Pour `show` sur un blob, la sortie explicitement demandée est écrite en flux dans un artefact métier local, accompagné de sa taille, de son SHA-256 et de sa complétude. Appeler `Remove-QuietGitArtifact -Artifact $r.Data.Artifact` après consommation : seul un artefact possédé par cette session du module peut être supprimé. Ce fichier n’est ni une capture du moteur ni une donnée SQLite.

Sources : documentation officielle [Git](https://git-scm.com/docs/git), [status](https://git-scm.com/docs/git-status), [commit](https://git-scm.com/docs/git-commit), [push](https://git-scm.com/docs/git-push).

## Tests

The companion executes 43 functional scenarios, or 45 with both explicitly selected C# mutation catalogues, including 22 nested compiled cases. Common forms are exercised against disposable local repositories; this is not full Git-version/platform qualification.

## Principal command workflows

The catalogue now registers 29 specialized command families. The new handlers cover:

- `switch`, `restore`, `reset`, `rm`, `mv`, `clean`: one requested native execution and independent porcelain-v2 HEAD/index/worktree observations. `clean --dry-run` retains the explicitly requested plan records. Unavailable initial observations block a worktree mutation before execution; bare variants requiring different observations remain unqualified.
- `merge`, `rebase`, `cherry-pick`, `revert`: one native operation, local before/after state and ref changes. A nonzero exit remains a failure; observed unmerged entries are reported as FailedWithConflicts. There is no automatic resolution, abort, continue or retry. Explicit follow-up commands are independent invocations. Requested rebase patch output is preserved.
- `tag`: structured lightweight/annotated listings, observed ref creation/deletion and explicit signature/format output. Message-less annotation and interactive forms require explicit input.
- `remote`: structured configured names, URLs and fetch/push directions; config mutations expose local before/after configuration without an implicit fetch. Explicit get-url/show output remains requested-format records.
- `config`: NUL-delimited list/get/get-all results retain duplicate keys, multiline/empty/valueless settings and lossless bytes. Missing get results are explicit; writes execute once without echoing values. Advanced origin/scope/format variants keep their requested records.
- `init`, `clone`: execute once and verify Git directory/bare identity for explicit destinations (or the current directory for init). Implicit clone destination discovery and recursive submodule state are not inferred.

`GitConfigRecords`, `GitRemoteRecords` and `GitOperationOutcome` have separate responsibilities. PowerShell RepositoryCommands.ps1 owns orchestration; there is no command named daily and no GitDaily class. File-only mutations require two status observations; ref-moving operations add two ref observations rather than separate HEAD/branch processes. These are native process costs, not per-record engine IPC.

Interactive option names are checked after binding, so flag-looking message values remain values. Qualification and reproducible commands are documented in [the audit](../docs/audits/2026-11-05-git-principal-commands.md). Reflog, grep, blame, bisect, recursive submodule and maintenance workflows are subsequent work; inventory membership does not qualify them.
