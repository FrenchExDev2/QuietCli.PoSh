<p align="center">
  <img src="../../../../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# QuietCli Vagrant

The Vagrant companion turns `vagrant up` and `vagrant provision` into structured [QuietCli](../../../../README.md) events. Use a PowerShell listener to react to machine events or open a live dashboard with one lane per machine.

**Preview.** Provider and version qualification is partial. [Coverage and limits](#coverage-and-limits)

## Installation

Use PowerShell Core 7.6+, a separate Vagrant installation and the provider required by your `Vagrantfile`. The companion requires Core with the companion command contract. Load both modules from the same [built source checkout](../../../../README.md#from-a-source-checkout) in a fresh PowerShell session at the repository root.

```powershell
Import-Module ./src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Import-Module ./src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/FrenchExDev2.QuietCli.Vagrant.PoSh.psd1 -ErrorAction Stop
```

## Quick start

From the directory containing your `Vagrantfile`, start the project with a live dashboard and keep the parsed events in the result.
On first boot, Vagrant can run the provisioners defined in that file. To start without provisioning, replace the invocation below with `$result = quiet -AsObject -UI -CollectEvents vagrant up --no-provision` and keep the same result checks.

```powershell
$result = quiet -AsObject -UI -CollectEvents vagrant up
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or
    !$result.Completeness.Analysis -or $result.Error.Count) {
    throw 'Vagrant up failed or its result is incomplete.'
}
$result.Events | Select-Object Type, @{ Name = "Machine"; Expression = { $_.Data.Machine } }
```

The handler adds `--machine-readable`. The dashboard uses one lane per named machine. Use `-MaxLines` with `-UI` to control the history shown per lane.
The dashboard's provider label is a hint. It shows `docker via podman` when the PowerShell process's `DOCKER_HOST` contains `podman`, and `docker` otherwise. Use Vagrant's configuration and provider output to confirm which provider ran.

## Event contract

Each event has a `Type` and a `Data` payload. `-Listeners` receives events during execution. `-CollectEvents` retains the same events in `$result.Events` in emission order. The dashboard works independently of both options.

| Event | Payload |
| --- | --- |
| Native Vagrant type, for example `ui` | `Timestamp` as a `DateTimeOffset`, `Machine` as the target name or null, `Type` as the native type and `Fields` as the decoded native values in order. A `ui` message can have `Fields[0] = 'info'` and its text in `Fields[1]`. |
| `ProvisionerStarted` | `Kind`, `Machine`, `Provisioner` and `Timestamp`. This inferred event follows the native `ui` event when its info message matches `Running provisioner: <name>...`, optionally prefixed with the same machine name. |

The inferred event indicates a matching start message. Confirm provisioner outcomes through the execution result and the provider's relevant events. The parser skips malformed stdout records. It does not infer a start from the command arguments.

The separate `$result.Data` summary contains `Command` (`up` or `provision`), `Lines` (the count of parsed native records) and `Machines` (the distinct named machines observed). A synthetic `ProvisionerStarted` event contributes to the event collection only.

```powershell
$starts = [Collections.Generic.List[object]]::new()
$listener = {
    param($event, $runtime)
    if ($event.Type -ceq 'ProvisionerStarted') { $starts.Add($event.Data) }
}.GetNewClosure()

$result = quiet -AsObject -UI -MaxLines 4 -Listeners $listener -CollectEvents vagrant provision web
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or
    !$result.Completeness.Analysis -or $result.Error.Count) {
    throw 'Vagrant provision or its analysis failed'
}
$starts | Select-Object Machine, Provisioner, Timestamp
$result.Data | Select-Object Command, Lines, Machines
```

The example assumes `web` is defined and already running in the current Vagrant project. See the [handler UI example](../../../../docs/README-create-git-handler.md#show-live-updates-using-the-vagrant-pattern) for the emission and lane-writing callbacks.

## Coverage and limits

- The registered handlers cover `up` and `provision` with stable Vagrant `>= 2.3.0` and `< 2.5.0`.
- The parser emits events from recognized machine-readable lines. `ProvisionerStarted` is inferred from the matching machine’s `ui`/`info` messages.
- Fixture tests exercise parsing and dispatch. The real-provider audit records the narrower Windows and Podman scenario exercised with Vagrant 2.4.9.

[Vagrant test companion](../../test/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/README.md) · [Real-provider audit](../../../../docs/audits/2026-11-09-provider-ui-qualification.md) · [Core dashboard and streaming](../../../Core/src/FrenchExDev2.QuietCli.Core.PoSh/README.md#invocation-modes-and-live-dashboard)

## Credits

The QuietCli Vagrant module uses the MIT license. The native Vagrant executable comes from the HashiCorp Vagrant project and has release-specific license terms. [Module license](LICENSE) · [Vagrant license credits](LICENSE_CREDITS.md) · [Repository credits](../../../../CREDITS.md#vagrant)
