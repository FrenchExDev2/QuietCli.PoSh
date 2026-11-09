# Emit, listeners, Vagrant and dynamic workspace catalogues — 8 November 2026

Execution-based continuation of the [authoring-only handoff audit](2026-11-08-emit-listeners-ui-vagrant.md).
The original audit remains historical: this report records the subsequent builds, corrections and local
development validation. It also covers the requested reusable project/suite catalogue and explicit
publishable/non-publishable package view.

## Implemented and corrected

- The first build found `CS0311`: `TableColumn` does not implement Spectre's overflow contract.
  Overflow now belongs to each `Text` cell; columns use `NoWrap`.
- The UI renderer now drains timer callbacks, serializes drawing and performs its final frame before
  disposing the surface. Append-only output preserves a header set after the first timer tick and avoids
  repeatedly printing unchanged lanes. Test recordings are synchronized. Header identity is supplied by
  the runtime and Vagrant handler. Real interactive console qualification remains separate.
- A facade defect consumed colon-suffixed value options from PowerShell hashtable splatting as boolean
  switches. Only actual switches now consume a boolean value. Generated binding properties and real
  `quiet @options` process tests retain callback arrays, dictionaries and exact native arguments.
- `Events` is now included in JSON/YAML delivery through the same bounded projection as other result
  containers. Native fixture tests check Unicode order, listener failure isolation, `Complete` emission,
  both formats and unchanged local events after truncation.
- Listener tests cover ordered fan-out, invalid shapes, generated failure boundaries, independent nested
  calls and explicit forwarding. A listener failure remains an observation error without invalidating
  business analysis.
- Vagrant's nested completion returns its array as one value. Native environment, timeout, transport,
  input/cancellation and success-code options are forwarded; incomplete child execution cannot become
  a successful summary. Stable version parsing rejects prereleases and numeric overflow.
- Vagrant fixtures use the real process engine, exercise both registered handler executions, and retain
  per-machine output/provisioner events. Fuzzing uses a fixed seed, complete machine-name arrays, Unicode,
  escaped commas/newlines and arbitrary byte writes. A separate malformed corpus rejects partial events.
  Tests never install Vagrant or configure a provider.
- The module workstation scripts implement guarded download/install paths. Git reuses locked archive
  recipes and matching cache filenames. Vagrant 2.4.9 MSI/DEB/RPM artifacts are pinned to the
  [official checksum list](https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9_SHA256SUMS).
  Windows x64, Debian/Ubuntu x64 and Fedora x64 are represented; unavailable ARM64 packages and Alpine
  installers remain explicit gaps. Provider readiness requires a working Docker-compatible client.
  Automated tests replace effects; no real host installation/download was performed.
- `Install-DevelopmentPackages` remains private. The shared helper uses the development module's private
  installation implementation rather than adding that extra public export.
- `WorkspaceProjects.ps1` discovers inert manifests and dependency order. The four host/container launchers
  construct their `Suite` parameter dynamically, including binding validation and completion metadata.
  `All` expands to actual companions and is never treated as a module/package. Locking, initialization,
  staging, offline ZIP verification and preview output-path protection reuse this catalogue.
- `Get-QuietWorkspacePackages` distinguishes explicit public eligibility from local source/test archives.
  Core declares public `QuietCli`; Git/Vagrant declare publication disabled. Every `.Tests.PoSh` companion
  is excluded even if its metadata asks for publication. Missing declarations deny publication. The
  existing public preparer/verifier still accepts exactly Core; no publication was performed.
- Central package declarations participate in build provenance and copied mutation inputs. A regression
  independently changes `Directory.Packages.props` and requires stale-build rejection. Companion runners
  consume incidental assertion output and the worker requires exactly one summary per companion.
- Spectre.Console and Spectre.Console.Ansi 0.57.2 retain the upstream MIT license and package/commit
  provenance under `Core/third_party/spectre.console`. Vagrant projects carry the workspace's MIT license.

## Executed results

Windows x64, PowerShell **7.6.9**, CLR **.NET 10.0.14**, integrated `net10.0` engine. The pinned
SDK builds the `net11.0` test executable and all six configured engine publications. Building those
publications does not establish Linux/ARM64 execution.

Reports are under `%TEMP%/QuietCli2/874a99c9b658/tests/`:

| Evidence | Result | Run |
| --- | --- | --- |
| Final unfiltered `All` gate | **144 passed, 0 failed**: Core 64, Git 68, Vagrant 12; no case filter or stopped run | `20261108-213630-cc82c1` |
| Final Vagrant parser campaign | **13 passed, 0 failed**, including **5 Killed**, no survivors/infrastructure failures | `20261108-214812-170efb` |
| Complete C# configuration/delivery catalogue | Baseline **85 passed**; **81/81 Killed**; functional/compiled counters **172 passed, 0 failed** before the final source-drift guard | `20261108-205659-532b78` |
| Final workspace catalogue tests, included in `All` | 32 generated graphs, 5 malformed/invalid UTF-8 samples, **6/6 Killed** | `workspace-projects/summary.json` under the final `All` run |
| Final workstation tests, included in `All` | 50 examples, 1,000 existing properties/1,600 malformed inputs; 200 additional Vagrant-version properties/800 malformed banners; **10 policy + 5 selector mutants Killed** | `development-workstation.json` under the final `All` run |

The C# catalogue's enclosing worker is **Failed**, because the user requested project/package catalogue
changes while that campaign was running and the final whole-workspace identity guard correctly detected
them. This is not presented as one successful full `ConfigurationDelivery` worker run. Its 81 mutation
receipts retain successful builds and failing behavioral assertions. `compiled-input-applicability.json`
independently verifies that the exact engine/test C# inputs, SDK, protocol and central package declarations
are unchanged: both digests are
`0498F11AEC0FD1889A2C81A54A1011939259213F98A3C0C6D159C4526A29B251`.
Those compiled results are reused only for that unchanged scope. The final cleanly completed `All` run
repeats the functional baseline and validates the updated PowerShell orchestration/catalogue.

Final `All` source identity before subsequent report-only edits:
`8CD73F6A9AEBEF5FCBECADC0F17A7E4615562D7C0DA952933DC9FD082625165E`.
The tested net10.0 engine DLL SHA-256 is
`221DB1A582929D1C77C4B3A970F1C9713C42C5E1AD7FD6E9403F26B1A2F33A79`.
The recorded repository HEAD is `aa576e9bd8afc98b3f284d74a52d50b6c9a4783a`, with a dirty working tree;
this report does not qualify that commit as if it contained the working-tree implementation.

## Seeds and mutant corrections

- Vagrant: `20261108`, 200 fragmented valid transcripts plus 800 malformed inputs per baseline run.
- UI: `20261108`, 50 generated interleaved-lane sequences; listener/facade generated cases: `20261112`.
- Project catalogue: `44183`; existing workstation properties: `914227`; additional module/version checks:
  `20261108`. The configuration runner also retains its YAML/tokenization seeds in its JSON report.
- The original newline mutation anchor interpolated an actual newline instead of source backtick text;
  its source anchor is now literal. Removing the short-line guard was equivalent under the remaining
  guard/catch behavior, so it was replaced by a meaningful mutant that returns a malformed event.
- A renderer constructor now also rejects non-positive depth, making deletion of the caller's redundant
  guard equivalent. The catalogue instead tests silent coercion of invalid depth to one. Additional
  mutants target splatted values, event delivery and omission of the final frame.

## Reproduction

```powershell
./scripts/Build-Workspace.ps1
# Fresh normal-profile PowerShell process after the build:
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild
$env:QUIETCLI_VAGRANT_PARSER_MUTATION = '1'
./scripts/Invoke-WorkspaceCi.ps1 -Suite Vagrant -SkipBuild
Remove-Item Env:\QUIETCLI_VAGRANT_PARSER_MUTATION
# Optional fresh full-catalogue worker, with source edits paused for its whole run:
./scripts/Invoke-WorkspaceCi.ps1 -Suite ConfigurationDelivery -SkipBuild -TimeoutSeconds 2400
```

Every executed run used the shared dedicated visible monitor, saved terminal results and automatic
window closure. Reopen any result with `./scripts/Watch-Tests.ps1 -RunDirectory <absolute run path>`.

The required NuGet freshness query was executed through `quiet`, using UTF-8 forcing for the CLI:
`dotnet list ./FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj package --outdated --format json --no-restore`.
It succeeded and reported no outdated package entries for the engine. No package version was downgraded.
Whitespace and affected Markdown links were checked; UTF-8/LF validation covered the source Markdown set.

## Remaining qualification boundaries

- No real Vagrant `up`/`provision`, Docker/Podman provider run, interactive Spectre resize/Ctrl+C validation,
  actual module installation or installer download was executed. `Qualification = Partial` is retained.
- These results do not establish Linux, ARM64, the full native C campaign, the public release matrix or
  a remote GitHub run. Targeted mutations establish sensitivity for their catalogues, not exhaustive coverage.
- An optional new CI wrapper was omitted after automatic review rejected granting `packages: write`.
  Existing workflows remain in place; their `All` execution uses the shared discovered companion selection.
- No commit, push, tag or publication is implied. Existing unrelated work was preserved; the workspace
  checkpoint script stages everything and was not used to absorb those pre-existing changes.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
