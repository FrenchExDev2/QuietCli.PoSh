# Vagrant companion module and live UI dashboard (`-UI`/`-MaxLines`) — 8 November 2026

Continues implementing the plan at `fait-moi-un-plan-cosmic-scott.md` (QuietCli `-Listeners`/`Emit` event
emission plus the Vagrant companion module). This note covers the two sections completed in this authoring
session — the Vagrant `--machine-readable` parser/engine test aggregation (plan §7) and the `-UI`/`-MaxLines`
live dashboard (plan §8) — and documents only writing/authoring work. **No build or test run has been executed
in this session**: every result below is reported as an explicit, unexecuted qualification gap rather than an
implicit pass, per this repository's own property/fuzz/mutation-testing mandate in `AGENTS.md`.

## Changes

- **Vagrant test aggregator** (`FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh.psd1`/`.psm1`):
  makes `Invoke-QuietVagrantTests` reachable from `-Suite Vagrant`, combining the existing deterministic line
  cases (`VagrantLine.Tests.ps1`) and the seeded fuzz campaign (`VagrantFuzz.Tests.ps1`) with a new, env-var-gated
  mutation case.
- **Vagrant parser mutation campaign** (`FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/VagrantParser.Mutation.ps1`):
  a lighter, build-free mutation pattern for pure PowerShell source — each mutant is dot-sourced inside its own
  child scope (`& { . $mutatedPath; ... }`) so a mutated function definition never leaks into this module's own
  scope or touches the real `FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1` on disk. Five mutants target
  comma-unescaping, `\n` restoration, the malformed-short-line guard, the provisioner-trigger regex anchor, and
  the UI lane key used by `Invoke-QuietVagrantMachineReadableRun`. Gated by `QUIETCLI_VAGRANT_PARSER_MUTATION=1`
  (opt-in, matching the existing Git module's per-catalogue convention), so plain `-Suite Vagrant` runs stay fast.
- **`QuietUiRenderer` test suite** (new file `FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/UiRendererCases.cs`):
  drives the real `QuietUiRenderer` class directly against a `RecordingSurface` test double for `IUiSurface` —
  no PowerShell runspace, no real console/Spectre.Console session. Covers: `Format`'s `[date][...]` shapes for
  every known event kind, including a `ToString`-throwing event; the default lane's `MaxLines`-deep FIFO tail,
  including the `MaxLines=1` default; multi-lane isolation and first-write arrival ordering; a lane that is only
  ever `Write`-n, never `NewLine`-d, still rendering its latest line; the default lane's un-prefixed rendering;
  the redundant `[Machine]` bracket being omitted exactly when it matches the lane's own key; `SetHeader`
  replacement and persistence across later draws; `Dispose` idempotency and Draw-failure containment
  (`logFailure` called, no exception propagated, no further rendering); and a 50-round, seed-20261108 property
  test asserting each lane's final line always reflects only its own latest write regardless of interleaving.
  Wired into `Program.cs`'s `--configuration-delivery-only` dispatch so it runs under the existing shared
  mutation harness without a new script or environment variable.
- **`-MaxLines`/`-UI` cmdlet-contract case** added to `InvocationCmdletCases.cs`, driven through the real
  Runspace-hosted `quiet` pipeline, confirming `MaxLinesRequiresUI` and `MaxLinesMustBePositive` are raised by
  the actual argument/runtime validation path (`ArgumentCommands.cs`, `RuntimeCommands.cs`), not just by the
  pure-C# `UiRendererCases.cs` cases.
- **`ConfigurationDelivery.Mutation.ps1`'s shared `$catalogue`** (already the authoritative mechanism for every
  case reachable from `--configuration-delivery-only`) gained six entries covering this work:
  `maxlines-requires-ui-guard-removed`, `maxlines-must-be-positive-guard-removed`, `ui-tail-fifo-head-not-advanced`,
  `ui-tail-count-not-capped`, `ui-lane-order-not-insertion`, `ui-format-machine-prefix-always-shown`. Each
  anchor's exact source text was re-confirmed as uniquely present in the live `ArgumentCommands.cs`/
  `RuntimeCommands.cs`/`Cmdlets/UiRenderer.cs` files (the harness itself also enforces exactly one match per
  mutant and throws `ConfigurationDeliveryMutationAnchorInvalid` otherwise). The `ui-format-machine-prefix-
  always-shown` mutant was designed last, after noticing no pre-existing case exercised the redundant-bracket
  suppression rule — the dedicated case was added to `UiRendererCases.cs` first so this mutant would actually be
  killed rather than silently surviving.
- **Core module README** (`FrenchExDev2.QuietCli.Core.PoSh/README.md`): new "Live dashboard (`-UI` / `-MaxLines`)"
  section between "Hosting, runtime and transports" and "Configuration", documenting the lane model, the
  `Spectre.Console` Central-Package-Management dependency (declared in `Directory.Packages.props`, no `Version=`
  on the engine's `<PackageReference>` — confirmed present in both files), the caught-and-logged render-failure
  behavior, and the documented limitation that a nested `-UI` call in the same process falls back to a plain
  append-only surface instead of a second live-redrawing session.

## Results and provenance

Not executed. This session has no shell/PowerShell execution tool available, so nothing above has been built,
imported, or run; no pass/fail counts, mutation outcomes, or source/binary hashes can be honestly reported here.
Per `AGENTS.md`, an unexecuted required campaign is an explicit qualification gap, not an implicit pass — this
work is not qualified until the commands below are run and their reports reviewed.

## Reproduction (not yet run — commands for the next execution)

```powershell
./scripts/Build-Workspace.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite Vagrant -SkipBuild
$env:QUIETCLI_VAGRANT_PARSER_MUTATION = '1'
./scripts/Invoke-WorkspaceCi.ps1 -Suite Vagrant -SkipBuild
Remove-Item Env:\QUIETCLI_VAGRANT_PARSER_MUTATION
./scripts/Invoke-WorkspaceCi.ps1 -Suite ConfigurationDelivery -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild
```

- `-Suite ConfigurationDelivery` already always runs with mutation enabled (`Invoke-QuietConfigurationDeliveryTests
  ... -Mutation`), so this single command covers the full shared catalogue, including the six new `MaxLines`/
  `UiRenderer.cs` mutants, with no extra flag.
- `-Suite Vagrant`'s mutation case is opt-in via `QUIETCLI_VAGRANT_PARSER_MUTATION=1`; the plain run above
  exercises only the deterministic line cases and the day-seeded fuzz campaign.
- `UiRendererCases`'s property test uses the fixed seed `20261108` for its 50-round interleaved-lane campaign;
  rerunning it with the same seed should reproduce identical round-by-round key orderings.

## Remaining limits

- Anchor uniqueness for the six new mutants was checked by reading the live source files in this session, not
  by actually running the mutation harness — a stale anchor would surface as `ConfigurationDeliveryMutationAnchorInvalid`
  on first execution, not here.
- No Linux run, no real Spectre.Console terminal/TTY session, and no actual `vagrant` binary invocation have
  occurred; `UiRendererCases.cs` only exercises `QuietUiRenderer` against the `RecordingSurface` test double, and
  the Vagrant mutation cases only exercise the parser/engine against the existing native fixture, not a real
  Vagrant process.
- The Core module README and audit documentation changes are editorial; they were not themselves build- or
  test-verified beyond the source greps cited above.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
