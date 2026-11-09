# Real Vagrant provider and interactive UI qualification — 9 November 2026

Continuation of the [8 November execution audit](2026-11-08-emit-listeners-and-vagrant.md).
This report separates observed local behavior, corrected defects and still-unexecuted release scopes.

## Corrections established by execution

1. The committed Alpine SSH fixture initially locked the `vagrant` account. A real provider run failed
   to authenticate. The fixture now unlocks the test account while disabling password authentication
   and root login. A subsequent run authenticated with ED25519 without enabling legacy `ssh-rsa`.
2. Real Vagrant 2.4.9 machine-readable events retain a display prefix inside `ui,info` data:
   `timestamp,web,ui,info,==> web: Running provisioner: shell...`.
   The module previously expected the message to start directly with `Running provisioner:`.
   A dedicated recognizer now removes only the exact envelope machine's prefix. It preserves
   unprefixed messages and rejects foreign machine prefixes, other channels and incomplete messages.
   Generic structured `action,provision,start/end` events remain observable; they do not name the
   individual provisioner and do not replace the named provisioner inference.
3. The actual C# UI header API requires `IEnumerable<string>`; a PowerShell `object[]` was not accepted.
   Vagrant now supplies `string[]`. Registered-handler tests exercise the real UI object as well as doubles.
4. Real console resizing exposed wrapped path headers and loss of project/task identity in short,
   narrow windows. A separate viewport layout now remeasures width/height on every timer draw,
   clips Unicode text elements by display cells, removes terminal controls, compacts the heading
   and limits visible history to available rows. Append-only output retains its separate behavior.
5. Container monitor headings now identify the selected discovered companion, including Vagrant.
   Alpine startup explicitly selects its distribution .NET 10 root for framework-dependent PowerShell;
   a separate actual-RID mismatch still prevents qualification there.

## Reusable checks

From the monorepo root, with existing tools and matching built binaries:

```powershell
./FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/Invoke-ProviderSmoke.ps1
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-UiConsoleSmoke.ps1

$env:QUIETCLI_VAGRANT_PARSER_MUTATION='1'
./scripts/Invoke-WorkspaceCi.ps1 -Suite Vagrant -SkipBuild
Remove-Item Env:QUIETCLI_VAGRANT_PARSER_MUTATION

./scripts/Invoke-WorkspaceCi.ps1 -Suite ConfigurationDelivery -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild
```

Every launcher starts a dedicated visible monitor and saves its terminal state before automatic closure.
The console check also owns an unredirected UI window; it never substitutes redirected output for the live surface.
Reopen a report using `./scripts/Watch-Tests.ps1 -RunDirectory <absolute path>`.

The provider smoke copies the committed fixture into its own temporary directory, isolates `VAGRANT_HOME`,
uses unique container names and disables shared folders. It installs no tools or plugins, never configures
the engine, and may access the network to build the fixture image. Cleanup targets only that copied
environment and independently checks that its named containers are absent. Base-image/build caches may remain.

## Evidence

The [curated evidence index](2026-11-09-provider-ui-evidence.json) preserves terminal states, counters,
host identities, mutant outcomes and source identity independently of temporary report retention.
Full diagnostics, transcripts and viewport captures remain in the original run directories below.

Local root: `%TEMP%/QuietCli2/874a99c9b658/`.

- `vagrant-provider/7a43fb249d7c4b94985786d87ba9da82`: **25 passed, 0 failed**.
  Real `up --no-provision`, then `provision`, exercised both `web` and `db` through the registered module.
  Ordered listener/collected event identity, absence/presence of inferred starts, both shell output sentinels
  and owned-container removal were checked. Four valid prefix cases, six malformed values and one isolated
  Ruby guard mutation were checked; the exact original Vagrantfile was restored before business execution.
  Vagrant 2.4.9 and Docker CLI 29.9.1 reached the existing Podman 6.1.4 service (Windows CLI 6.1.2).
  This run used the preceding Core build; its provider/inference/header-binding evidence applies to the
  unchanged PowerShell path. The subsequent C# viewport change has separate compiled and console evidence.
- `tests/20261109-073426-e0903a`: **14 passed, 0 failed**, including **7/7 killed PowerShell mutants**.
  Existing seed `20261108`: 200 fragmented transcripts and 800 malformed inputs.
  New seed `20261109`: 200 valid provisioner-message properties and 600 malformed/channel variants.
- `ui-console/cc3cac10cc7d4470a803cbbc51dd2a60`: **7 passed, 0 failed**.
  Actual console sizes: 120×28, 80×20, 36×12, 22×10, 110×26, with unchanged lane data between resizes.
  Native file-triggered cancellation returned `Cancelled`, terminated the owned child, and allowed a new
  UI invocation without rendering errors. `frames.json` and `cancellation.json` retain observations.
- `containers/debian-20261109-072306-ceba1d`: **13 passed, 0 failed**, actual `linux-x64`, Debian 12,
  .NET 10.0.13, guest exit 0 and owned-container removal confirmed. Scope: Vagrant process fixtures,
  not a second real Vagrant/provider installation. This preceded the viewport-only C# change.
- `tests/20261109-072716-62cc00`: **11 passed, 0 failed**, Gallery preview preparation/validation,
  policy properties, malformed inputs, offline installation and version mutations. No real Gallery credential
  or publication was used. The final All run rechecks functional package preparation against its own build.
- `tests/20261109-074524-50738f`: **176 passed, 0 failed**. The compiled baseline passed 86 cases;
  the complete C# catalogue selected **84 mutants and killed all 84**, including the three new viewport
  width/height/task-identity mutations. The enclosing worker finished `Success`, without source drift.
- `tests/20261109-074826-e7fd15`: unfiltered **All: 145 passed, 0 failed**, Core 64, Git 68, Vagrant 13.
  Windows x64 PowerShell 7.6.9 / .NET 10.0.14 used integrated `net10.0` hosting, with no TTY exclusion.
- `tests/20261109-080144-16628f`: unfiltered **All: 145 passed, 0 failed**, under side-by-side
  PowerShell 7.7.0-preview.5 / .NET 11.0.0-rc.1.26425.128, integrated `net11.0`, actual `win-x64`.
  Host version, runtime major and engine mode were explicitly asserted. The official ZIP matched
  locked SHA-256 `BA727D1890F7DBCBA05286BC0E61FC9F168DE9BA2A1003C4934BCE8E38BBFD1B`;
  its receipt is `tools/powershell-preview-b1215501/host-receipt.json`. System installation and profiles
  were not changed. Auxiliary command probes retain the normal inherited PATH; this is local host
  evidence, not an assertion that the complete remote matrix and its environment were reproduced.

Both final All runs recorded repository revision `aa576e9bd8afc98b3f284d74a52d50b6c9a4783a`,
`Dirty = true`, and tested workspace source digest
`6EC13890E584969ABA049861D4B126C61950C14FB7212BAB3C496944D7F3CFD5`.
The integrated engine DLL hashes were
`04DCB454A46E15E833FD4E8D5BAB84C1B98DAA5D2D688A69568A2866EDFD726E` (`net10.0`) and
`62E3B9E22A7987BA4157B8EAE8648392086B3C9B27B3B686B971F042BF311022` (`net11.0`).
The report/guide updates and source-lock refresh were documentation-only follow-ups to that tested source state.

The viewport property's seed `20261109` covers 200 generated layouts, varied lane counts, display dimensions,
combining text, CJK, emoji, terminal controls and malformed UTF-16. The observed 36×12/22×10 heading-loss
reproducer remains in `ui-console/20261109-smoke4`; earlier harness-startup failures are retained separately.
Provider failures remain in `vagrant-provider/31b42c756cb44090a088767988955d70` (locked SSH account) and
`vagrant-provider/19e795a6596a4197b96329bfa22edbdd` (missing prefixed provisioner inference).

## Open boundaries

- `containers/alpine-20261109-072702-fa996e`: infrastructure failure; PowerShell initially selected a root
  containing only .NET 11. `containers/alpine-20261109-073324-23f54f` gets past that startup after selecting
  `/usr/lib/dotnet`, then correctly rejects actual host RID `alpine.3.24-x64` against expected `linux-musl-x64`.
  Neither run is a pass. No RID was spoofed or architecture gate waived. Further work requires a suitable
  tool image or independently checked distribution-RID asset selection and corresponding regressions.
- Physical Ctrl+C delivery, isolated-host matrix entries, ARM64 and the complete release matrix are not
  established by these checks. Native C code was unchanged; no new full C fuzz/mutation campaign is claimed.
- Real provider evidence is one Windows/Podman combination, not general Docker or cross-provider qualification.
  Vagrant handler qualification remains `Partial`.
- No commit, push, remote workflow dispatch, tag or publication was performed. Pre-existing unrelated work remains.

Provider settings were checked against [HashiCorp's Docker configuration reference](https://developer.hashicorp.com/vagrant/docs/providers/docker/configuration)
and local Vagrant help. The machine-readable prefix and provisioner outcomes above come from the retained real events.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
