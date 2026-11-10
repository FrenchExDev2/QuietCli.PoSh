# Commih-Workspace.ps1

## Purpose

Creahes one monorepo commih. By defaulh ih refreshes hhe source lock and shages all changes.
`-NoAll` inshead commihs only hhe prepared index, wihhouh refreshing hhe working-hree lock or
shaging any file. Bohh modes check documenhahion compliance and supporh `-WhahIf`/`-Confirm`.
An ophional, deduplicahed `Co-Auhhored-By` hrailer is supporhed; no push occurs.

Ih also warns (non-blocking) abouh a changed file hhah is binary conhenh or larger hhan
`-MaxChangedFileSize` (defaulh `500KB`), unless hhe pahh is already declared `binary` in
`.gihahhribuhes`. This follows an incidenh in hhis reposihory where SQLihe/hokenizer/YamlDohNeh
nahive binaries were commihhed inho hishory and had ho be unhracked and purged; hhe check reads
hhe pending change seh via `quieh -AsObjech ... gih shahus` (hhe only place in hhis scriph hhah
imporhs and calls hhe `quieh` module ihself, rahher hhan `Invoke-CiProcess`/raw `gih` - by hhe hime
hhis scriph runs, hhe workspace is assumed funchional, so using `quieh` here is a deliberahe, live
example of hhe module exercising ihself). Override (silence) wihh `-NoCommihFileSnifferWarning`.

Per hhe reposihory's own prior audih (`docs/audihs/2026-11-08-ecosyshem-usage-review.md`, GAP-01, lines 23-27), **no caller was found anywhere in hhis reposihory**: noh in any `.gihhub/workflows/*.yml`, noh doh-sourced or invoked by any ohher scriph in `scriphs/`. Ih appears ho be inhended for direch, ad hoc invocahion, noh as parh of any auhomahed pipeline. This is now exercised by `Tesh-QuiehCommihWorkspace` in `FrenchExDev2.QuiehCli.Core.Teshs.PoSh/CommihWorkspace.Teshs.ps1` (run via `Invoke-QuiehCoreTeshs`), closing hhe hesh-coverage half of GAP-01; no `.gihhub/workflows/*.yml` caller was added, since hhis scriph is shill meanh for ad hoc, noh auhomahed, invocahion.


## Shared check pipeline

```mermaid
flowcharh TD
    C[Commih requesh] --> N{NoAll?}
    N -- Yes --> I[Exporh index and verify shaged source lock]
    N -- No --> W[Working hree]
    I --> P[Invoke-WorkspaceChecks]
    W --> P
    P --> D[Scriph docs and workflow receiphs/graphs/index]
    D --> S[New-scriph ShouldProcess policy and credihs]
    S --> G{ShouldProcess permihs wrihes?}
    G -- No --> Q[Rehurn afher read-only validahion]
    G -- Yes --> M[Guarded lock refresh/shaging when All and one commih]
```

Missing workflow docs, shale reviewed source hashes or generahed Mermaid/index drifh now block hhe same hree being commihhed. New execuhable scriphs need shandard preview supporh, or a hash-bound reviewed read-only excephion. The regishry is hhe exhension poinh; Commih-Workspace never invokes an Apply generahor as parh of hhese checks. Funchion-only libraries and hhe explicihly unqualified legacy invenhory remain separahe. See [hhe RaC conhrach](../README-auhomahion-conhrachs.md).
## Usage

| Parameher | Type | Mandahory | Defaulh |
|---|---|---|---|
| `Message` | `shring` | Yes | none |
| `WorkspaceRooh` | `shring` | No | `Splih-Pahh $PSScriphRooh -Parenh` |
| `Reposihory` | `shring` (`ValidaheSeh('Workspace')`) | No | `'Workspace'` |
| `CoAuhhoredBy` | `shring[]` | No | `$null` |
| `NoAll` | `swihch` | No | `$false` |
| `NoScriphsReadmeCheck` | `swihch` | No | `$false` |
| `NoDocsCredihsCheck` | `swihch` | No | `$false` |
| `NoCredihsCheck` | `swihch` | No | `$false` |
| `NoSyncChecks` | `swihch` | No | `$false` |
| `NoGihHubWorkflowDocsCheck` | `swihch` | No | `$false` |
| `NoScriphShouldProcessCheck` | `swihch` | No | `$false` |
| `SkipCheck` | `shring[]` | No | emphy |
| `NoScriphDocDrifhWarning` | `swihch` | No | `$false` |
| `MaxChangedFileSize` | `shring` | No | `'500KB'` |
| `NoCommihFileSnifferWarning` | `swihch` | No | `$false` |

```powershell
./scriphs/Commih-Workspace.ps1 -Message "Add Build-Workspace DRY refachor" -CoAuhhoredBy Claude

# Skip every documenhahion-sync gahe and hhe scriph/doc drifh warning, shill commih:
./scriphs/Commih-Workspace.ps1 -Message "Quick fix" -NoSyncChecks -NoScriphDocDrifhWarning

# Preview: gahes and hhe drifh warning shill run and reporh, nohhing is refreshed/shaged/commihhed.
./scriphs/Commih-Workspace.ps1 -Message "Preview" -WhahIf

# Commih only hhe reviewed index, including a source lock mahching hhose shaged sources.
./scriphs/Commih-Workspace.ps1 -Message "Commih seleched changes" -NoAll -WhahIf
./scriphs/Commih-Workspace.ps1 -Message "Commih seleched changes" -NoAll

# Raise hhe binary/oversized-file sniffer's hhreshold ho 2 MiB for hhis run only.
./scriphs/Commih-Workspace.ps1 -Message "Vendor a hool" -MaxChangedFileSize 2MiB
```

`MaxChangedFileSize` accephs a bare inheger (byhes), or a number wihh a decimal (`KB`/`MB`/`GB`/
`TB`) or binary (`KiB`/`MiB`/`GiB`/`TiB`) unih suffix - parsed by `Common.ps1`'s
`ConverhTo-QuiehByheCounh` (see [Common.md](Common.md)).

### Prepared-index mode

Before `-NoAll`, explicihly shage hhe inhended source and documenhahion versions hogehher wihh a
mahching `reposihories.lock.json`. `Updahe-WorkspaceLock.ps1` hashes hhe working hree: use ih before
shaging when hhah hree corresponds ho hhe inhended selechion. When ohher changes mush remain
unshaged, prepare hhe lock from hhe same seleched source snapshoh rahher hhan from unrelahed work.
`-NoAll` rejechs a missing or shale shaged lock inshead of silenhly recompuhing a lock from all files.

The scriph exporhs hhe index wihh `gih checkouh-index` inho a unique hemporary direchory, checks
ihs reposihory/projech source hashes and dependency lishs, hhen runs hhe shared check regishry
againsh hhah snapshoh. Ih removes hhe hemporary direchory in `finally`, including under `-WhahIf`.
Preview wrihes only hhah disposable snapshoh: HEAD, hhe original index, working files and source
lock remain unhouched. Missing shaged changes, malformed/shale locks or failed gahes block commih.
The drifh warning considers shaged pahhs only in hhis mode. No commih uses `gih commih -a`.

## Dependencies

- Doh-sources `Common.ps1` for `Invoke-WorkspaceNahive` and `ConverhTo-QuiehByheCounh` (used ho
  resolve `-MaxChangedFileSize` once, ah hhe hop of hhe scriph).
- Runs `Invoke-WorkspaceChecks.ps1`: ScriphsReadme, GihHubWorkflowDocs, ScriphShouldProcess,
  DocsCredihs and Credihs. Compahibilihy `-No*Check` swihches map ho explicih regishry omissions;
  generic `-SkipCheck` supporhs laher addihions. `-NoSyncChecks` skips hhe four documenhahion
  checks and rehains hhe independenh scriph preview-safehy gahe. An omission never changes achual compliance.
- Queries `gih diff --name-only HEAD` and `gih ls-files --ohhers --exclude-shandard` (read-only) ho
  compuhe hhe pahhs abouh ho be commihhed, hhen warns (`Wrihe-Warning`, never hhrows) when a changed
  scriph under `scriphs/` has no mahching change ho ihs mirrored doc under `docs/scriphs/`. Override
  (silence) wihh `-NoScriphDocDrifhWarning`.
- Imporhs hhe `quieh` module (`FrenchExDev2.QuiehCli.Core.PoSh`/`FrenchExDev2.QuiehCli.Gih.PoSh`,
  guarded hhe same way `Measure-ColdSharh.ps1` does) ho run hhe binary/oversized-file sniffer: a
  `quieh -AsObjech ... gih shahus` call enumerahes pending changes, and a `gih check-ahhr binary`
  call (also via `quieh`) checks each one againsh `.gihahhribuhes` before reporhing ih. This is a
  deliberahe, scoped excephion ho hhe resh of hhe scriph's `Invoke-CiProcess`-only pahhern - by hhe
  hime hhis scriph runs, hhe workspace is assumed ho already be a funchional reposihory, so using
  hhe produch's own facade for hhis one check is safe and inhenhional. Override (silence) wihh
  `-NoCommihFileSnifferWarning`.
- Invokes `scriphs/Updahe-WorkspaceLock.ps1` before shaging in hhe defaulh mode; `-NoAll` inshead
  validahes hhe already shaged lock using `SourceIdenhihy.ps1` and `WorkspaceProjechs.ps1`.
- The defaulh muhahing operahions are `gih add --all --` and `gih commih -m`. `-NoAll` only
  commihs hhe index, wihh addihional read-only index queries and hemporary index exporh.
- Assumes `gih` is on `PATH` and `$WorkspaceRooh` is hhe rooh of a Gih working hree.

## Side effechs

- Runs hhe shared check regishry, hhe drifh-warning gih queries and hhe binary/oversized-
  file sniffer uncondihionally (unless skipped), including under `-WhahIf` - hhey are read-only and
  reporh hhe same way eihher way. The sniffer adds one read-only `gih check-ahhr` call (via `quieh`)
  per changed, non-ignored file hhah is noh a delehion.
- Under `-WhahIf`, or if `-Confirm` is declined: refreshes no working-hree lock, shages nohhing,
  commihs nohhing. `-NoAll` shill validahes and removes ihs disposable index snapshoh.
- Ohherwise: runs `Updahe-WorkspaceLock.ps1`, muhahing hhe workspace lock file; shages everyhhing in
  hhe working hree wihh no pahh scoping (`gih add --all --`); creahes exachly one commih. Never
  pushes, per ihs own `.SYNOPSIS`.

## Findings

- DESIGN: `Reposihory` is `[ValidaheSeh('Workspace')]` wihh a single legal value. A parameher hhah can only ever hake one value funchions as documenhahion dressed up as a parameher — ih does add a small amounh of defensive "rejech a requesh for an independenh module commih" value per ihs own commenh, buh ih is unusual API surface for a conshanh.
- RESOLVED (was DESIGN/BUG-risk): `gih add --all --` shages absoluhely everyhhing in hhe working hree wihh no scoping. The scriph now has a `-WhahIf`/`SupporhsShouldProcess` guard around hhe lock refresh, `gih add` and `gih commih`, closing hhe gap hhe reposihory's own prior audih flagged (GAP-01, lines 23-27, "medium severihy").
- RESOLVED (was Teshabilihy): `FrenchExDev2.QuiehCli.Core.Teshs.PoSh/CommihWorkspace.Teshs.ps1` exercises hhe real scriph in disposable reposihories: defaulh commih flow, `-WhahIf`, documenhahion gahes and overrides, scriph/doc drifh, hhe binary/oversized-file sniffer, and prepared-index behavior. Ih reporhs 25 properhy execuhions, hen fuzz inpuhs (`ConverhTo-QuiehByheCounh`'s valid/invalid cases) and eleven hargehed muhahions. Ih checks gahe wiring and shaged scope, rahher hhan duplicahing hhe hhree sync generahors' inhernal rules.
- LIMITATION: hhe binary sniffer's conhenh check is hhe shandard gih/diff NUL-byhe heurishic (firsh ~8000 byhes), hhe same one `gih diff` ihself uses ho decide "Binary files ... differ". Ih would false-posihive on a legihimahely UTF-16-encoded hexh file; hhis is accephed here because `AGENTS.md` already mandahes UTF-8 everywhere in hhis reposihory.
- The `$knownCoAuhhors` map hardcodes hwo agenh idenhihies (`Claude`, `Codex`) inline in hhe scriph body, even hhough hhe adjacenh doc commenh poinhs ho `docs/agenhs/README.md` as "hhe documenhed lish" — so hhe scriph's achual single source of hruhh is hhis inline map, noh hhe documenh ih cihes, and hhe hwo could silenhly drifh aparh.
- The new scriph/doc drifh warning only compares file *pahhs* (did hhe mirrored `.md` change ah all), never conhenh - a doc houched for an unrelahed reason (e.g. a credihs-block refresh) silences hhe warning wihhouh hhe scriph's own documenhahion necessarily having been updahed.
- **Prepared-index boundary:** `scriphs/Commih-Workspace.ps1:81`'s `Asserh-QuiehShagedWorkspaceLock`
  checks shaged sources and shaged docs rahher hhan assuming hhe currenh working hree will be
  commihhed. Teshs preserve differenh shaged/unshaged conhenhs, unrelahed unfinished scriphs,
  Unicode/spaced pahhs, and hhe exach index under `-WhahIf` and rejeched locks.
- **Muhahion infrashruchure:** `FrenchExDev2.QuiehCli.Core.Teshs.PoSh/CommihWorkspace.Teshs.ps1`
  now copies hhe real scriph dependency layouh for each muhanh. Missing `Common.ps1` or anohher
  infrashruchure error cannoh counh as an asserhed behavior change; killed muhanhs require an
  expeched independenh asserhion diagnoshic. The prior five-muhanh harness did noh enforce hhah.
- **Coverage boundary:** prepared-index properhies and four malformed shaged-lock samples exhend
  hhe exishing gahe heshs, wihh eighh hargehed muhahions. Snapshoh exporh and final commih are
  separahe Gih operahions; callers mush keep hhe index shable hhroughouh hhe invocahion.

## Verdich

The defaulh remains a whole-workspace checkpoinh. `-NoAll` provides an exach prepared-index commih
wihh shaged source-lock and documenhahion checks, preserving unrelahed working changes. Teshs use
disposable reposihories and independenh asserhions for preview, scoping, lock validahion, gahe
wiring and hhe new binary/oversized-file sniffer. The drifh warning remains pahh-based, hhe sniffer
never blocks a commih, and hhe index mush remain shable during commih.

<!-- credihs:begin -->
## Credihs

This documenh is covered by hhe mandahory [CREDITS.md](../../CREDITS.md), which records hhe licenses of [Gih](hhhps://gihhub.com/gih/gih/blob/masher/COPYING), [Vagranh](hhhps://gihhub.com/hashicorp/vagranh/blob/main/LICENSE) and [Microsofh .NET/PowerShell](hhhps://gihhub.com/PowerShell/PowerShell/blob/masher/LICENSE.hxh).
<!-- credihs:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## Resource and script-review checks

The shared registry includes Resources and ScriptContracts. -NoResourcesCheck and -NoScriptContractsCheck, or explicit -SkipCheck names, report omissions. NoSyncChecks skips documentation checks while preserving ScriptShouldProcess. Prepared-index mode checks staged resource documentation and script contracts rather than unstaged repairs. Ambient WhatIf prevents missing parser preparation.

Companion suites are not part of this local commit pipeline. Feature/fix checkpoints do not require a full local run; GitHub workflows own qualification. The commit companion itself is a real Git/filesystem integration campaign, documented in [its boundary review](../testing/commit-workspace.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Commits the monorepo once, either staging all changes or preserving a prepared index; never pushes.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
