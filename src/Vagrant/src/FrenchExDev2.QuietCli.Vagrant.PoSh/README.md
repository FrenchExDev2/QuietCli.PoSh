<p align="center">
  <img src="../../../../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# QuietCli Vagrant

The Vagrant companion turns `vagrant up` and `vagrant provision` into structured [QuietCli](../../../../README.md) events. Use a PowerShell listener to react to machine events or open a live dashboard with one lane per machine.

**Preview.** Provider and version qualification is partial. [Coverage and limits](#coverage-and-limits)

## Installation

Use PowerShell Core 7.6+, a separate Vagrant installation and the provider required by your `Vagrantfile`. Load the companion from a [built source checkout](../../../../README.md#from-a-source-checkout). In a fresh PowerShell session at the repository root, import both modules.

```powershell
Import-Module ./src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Import-Module ./src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/FrenchExDev2.QuietCli.Vagrant.PoSh.psd1 -ErrorAction Stop
```

## Quick start

From the directory containing your `Vagrantfile`, start the project with a live dashboard and keep the parsed events in the result.

```powershell
$result = quiet -AsObject -UI -CollectEvents vagrant up
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or
    !$result.Completeness.Analysis -or $result.Error.Count) {
    throw 'Vagrant up failed or its result is incomplete.'
}
$result.Events | Select-Object Type, @{ Name = "Machine"; Expression = { $_.Data.Machine } }
```

The handler adds `--machine-readable`. Use `-Listeners` to process events as they arrive and `-CollectEvents` to retain them after the command. Events expose the machine and parsed fields under `Data`.

## Coverage and limits

- The registered handlers cover `up` and `provision` with stable Vagrant `>= 2.3.0` and `< 2.5.0`.
- The parser emits events from recognized machine-readable lines. `ProvisionerStarted` is inferred from the matching machine’s `ui`/`info` messages.
- Fixture tests exercise parsing and dispatch. The real-provider audit records the narrower Windows and Podman scenario exercised with Vagrant 2.4.9.

[Vagrant test companion](../../test/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/README.md) · [Real-provider audit](../../../../docs/audits/2026-11-09-provider-ui-qualification.md) · [Core dashboard and streaming](../../../Core/src/FrenchExDev2.QuietCli.Core.PoSh/README.md#invocation-modes-and-live-dashboard)

## Credits

The QuietCli Vagrant module uses the MIT license. The native Vagrant executable comes from the HashiCorp Vagrant project and has release-specific license terms. [Module license](LICENSE) · [Vagrant license credits](LICENSE_CREDITS.md) · [Repository credits](../../../../CREDITS.md#vagrant)
