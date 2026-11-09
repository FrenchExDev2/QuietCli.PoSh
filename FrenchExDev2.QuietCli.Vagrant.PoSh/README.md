<p align="center">
  <img src="./../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Vagrant.PoSh

> **Status: under development (`0.1.0-preview`).** Covers `vagrant up` and `vagrant provision` only. **Qualification is partial** -- read [Coverage and limits](#coverage-and-limits) before relying on this module.

Vagrant business handlers for the [QuietCli](../README.md) engine. `quiet vagrant up`/`quiet vagrant provision` run the native command with `--machine-readable` appended internally (you never see that flag or its raw lines) and turn each line into a structured event, pushed live to `-Listeners` and collected in `$result.Events`. `-UI` renders a small live dashboard, one lane per machine.

## Quick start

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Import-Module ./FrenchExDev2.QuietCli.Vagrant.PoSh/FrenchExDev2.QuietCli.Vagrant.PoSh.psd1 -ErrorAction Stop

# Observe every Vagrant event as it happens, independently of the raw stream:
$events = [Collections.Generic.List[object]]::new()
$r = quiet -AsObject -WorkingDirectory $vagrantfileDirectory -Listeners { param($e, $r) [void]$events.Add($e) } vagrant up

# Or watch a live per-machine dashboard (Vagrantfile path/provider header, one line per machine, always the latest):
quiet -UI -WorkingDirectory $vagrantfileDirectory vagrant up
```

`$r.Events` always carries every parsed `--machine-readable` line for the run (`Timestamp`/`Machine`/`Type`/`Fields`), plus a synthetic `ProvisionerStarted` event (`Machine`/`Provisioner`/`Timestamp`) whenever Vagrant itself emits a `Running provisioner: ...` line -- which it never does under `--no-provision`, so that flag needs no special handling here: forward it in your own `ArgumentList` as you would to plain `vagrant up` and the absence of `ProvisionerStarted` follows automatically.

## Coverage and limits

- Only `up` and `provision` are registered; any other `vagrant` subcommand falls through to `HandlerNotFound` (supply your own `-Output`/`-Complete` for it).
- Supported version range: `stable >=2.3.0 <2.5.0` (probed via `vagrant --version`); outside that range the handler does not match and the call falls through as unsupported.
- `--machine-readable` is documented by HashiCorp as **partially stabilized** ("Work-In-Progress"). The generic event (`Type`/`Machine`/`Fields`/`Timestamp`) is emitted for every line regardless of `Type`, so a listener can filter on types this module does not know about. `ConvertFrom-QuietVagrantMachineReadableLine` never throws on an unrecognized shape -- it returns `$null` and the line is dropped.
- `ProvisionerStarted` detection infers a named provisioner from the `ui`/`info` channel. It accepts unprefixed messages and the exact machine prefix (`==> web: Running provisioner: shell...`) retained inside real machine-readable data. Other channels, foreign machine prefixes and incomplete messages are rejected. A two-machine Windows/Podman run with Vagrant 2.4.9 verifies this observed form; the inference and broader provider/version coverage remain partial. See the [execution audit](../docs/audits/2026-11-09-provider-ui-qualification.md).
- `Get-QuietVagrantProviderLabel` only detects the documented "sans plugin" Podman wiring (`$env:DOCKER_HOST` pointing at a Podman socket); the community `podman` gem path still reports as plain `docker`.
- `-UI`/`-MaxLines` are a Core engine feature (`QuietUiRenderer`), not specific to this module; see [Core's README](../FrenchExDev2.QuietCli.Core.PoSh/README.md) for the Spectre.Console dependency and the single-active-`-UI`-per-process limit.
