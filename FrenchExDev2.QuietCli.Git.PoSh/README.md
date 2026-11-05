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

The catalogue now registers 51 specialized command families. The new handlers cover:

- `switch`, `restore`, `reset`, `rm`, `mv`, `clean`: one requested native execution and independent porcelain-v2 HEAD/index/worktree observations. `clean --dry-run` retains the explicitly requested plan records. Unavailable initial observations block a worktree mutation before execution; bare variants requiring different observations remain unqualified.
- `merge`, `rebase`, `cherry-pick`, `revert`: one native operation, local before/after state and ref changes. A nonzero exit remains a failure; observed unmerged entries are reported as FailedWithConflicts. There is no automatic resolution, abort, continue or retry. Explicit follow-up commands are independent invocations. Requested rebase patch output is preserved.
- `tag`: structured lightweight/annotated listings, observed ref creation/deletion and explicit signature/format output. Message-less annotation and interactive forms require explicit input.
- `remote`: structured configured names, URLs and fetch/push directions; config mutations expose local before/after configuration without an implicit fetch. Explicit get-url/show output remains requested-format records.
- `config`: NUL-delimited list/get/get-all results retain duplicate keys, multiline/empty/valueless settings and lossless bytes. Missing get results are explicit; writes execute once without echoing values. Advanced origin/scope/format variants keep their requested records.
- `init`, `clone`: execute once and verify Git directory/bare identity for explicit destinations (or the current directory for init). Implicit clone destination discovery and recursive submodule state are not inferred.

`GitConfigRecords`, `GitRemoteRecords` and `GitOperationOutcome` have separate responsibilities. PowerShell RepositoryCommands.ps1 owns orchestration; there is no command named daily and no GitDaily class. File-only mutations require two status observations; ref-moving operations add two ref observations rather than separate HEAD/branch processes. These are native process costs, not per-record engine IPC.

Interactive option names are checked after binding, so flag-looking message values remain values. Qualification and reproducible commands are documented in [the audit](../docs/audits/2026-11-05-git-principal-commands.md). Reflog, grep, blame, bisect, recursive submodule and maintenance workflows are subsequent work; inventory membership does not qualify them.

## Object, reference and tracked-file queries

Twelve additional commands now have dedicated orchestration and caller-local C# parsing: ls-files, for-each-ref, show-ref, ls-remote, merge-base, rev-list, hash-object, write-tree, count-objects, symbolic-ref, check-ref-format and version. The specialized catalogue contains 51 of the 183 inventory entries. Get-QuietGitCoverage reports each PowerShell handler and its C# ParserTypes separately; Qualification remains Pending for the complete version/platform matrix.

ls-files uses NUL framing for paths and index stages. Object queries validate full SHA-1/SHA-256 identities and optional parents; alternative revision output is retained in RequestedFormat mode. show-ref/ls-remote distinguish ordinary, symbolic and peeled refs, quiet predicates and no-match exit codes. for-each-ref uses fixed NUL fields. count-objects keeps numeric counters and alternate records with explicit KiB units; human-readable output remains requested format. Symbolic-ref writes are separate observed mutations. The explicitly requested ls-remote may contact its source; no other query adds a hidden fetch or network observation.

Windows stable/.NET 10 and Preview/.NET 11 each passed 49 scenarios for this group, including 28 nested C# cases and the eight targeted query mutants. The current native fixture version is Git 2.56.0.windows.3. See [the query audit](../docs/audits/2026-11-05-git-queries.md) for limits and evidence.

## Reflog and line attribution

blame and annotate normalize their default display to line-porcelain. GitBlameRecords parses full IDs, source/final line numbers, declared group lengths, exact content and metadata. GitQuotedPath decodes Git C-style/octal byte paths before strict UTF-8 decoding; invalid Unicode remains explicit bytes. Incomplete entries/groups fail at EOF, and uncommitted zero IDs remain visible. Explicit porcelain/incremental/stats/color modes retain the requested native records. No hidden file read or secondary blame execution is performed.

reflog show uses five NUL fields for full object ID, selector, identity and message, mapped by GitReflogRecords. exists is a separate native predicate. Explicit output formats and other reflog operations retain requested records; they do not claim a recovery action or complete effect observation. Version-specific subcommand/option qualification remains pending.

The catalogue now has 51 specialized entries. This group passed 53/53 stable scenarios and 56/56 Preview scenarios (different explicitly selected mutation catalogues), with 33 compiled cases. See [the attribution audit](../docs/audits/2026-11-05-git-attribution.md).

## Search, path rules and raw plumbing diffs

grep distinguishes quiet predicates, requested NUL file lists and exact native content/context/count formats. Only file-list modes use typed GitIndexRecords paths; default content and binary-match records are not misrepresented as a structured match protocol. Pager forms require explicit interaction.

check-attr parses three-field NUL records. check-ignore parses four-field verbose NUL records, preserving leading empty fields for nonmatching paths and negated rules. Logical argv paths are encoded as equivalent NUL stdin only when the caller did not provide stdin/controller data; caller-provided LF stdin is preserved in requested-format mode. check-mailmap parses native canonical contacts. These handlers do not read ignore/attribute/mailmap files themselves.

diff-files, diff-index and diff-tree use GitRawDiffRecords for non-combined raw output: modes, complete IDs, status/score and one/two lossless paths. Only framing and identity display are normalized; native recursion is preserved. Explicit patch output uses the existing C# patch parser, while custom/combined/abbreviated formats retain their native records. Incomplete rename/copy paths fail at EOF. Read-only patch/porcelain -p modes no longer trigger the interactive patch-selector guard.

The catalogue contains 51 specialized entries. This group passed 60/60 scenarios on stable/.NET 10 and Preview/.NET 11, including 39 compiled cases, eight targeted C# mutants and two generated grep-mode PowerShell mutants. See [the path-query audit](../docs/audits/2026-11-05-git-path-queries.md).
