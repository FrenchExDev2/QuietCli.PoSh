# Install-DevelopmentWorkstation.ps1

## Purpose

Prepare or inspect a QuietCli developer workstation using engine-independent provisioning.
The installer selects the native Windows/Linux host, resolves reviewed artifacts and returns one
report with `Ready`, `NeedsInstallation`, `RestartRequired` or `Failed`. It never runs workflows.
See the [workstation guide](../../README-development-workstation.md) and
[wrkflw helper backlog](README-wrkflw-plan.md).

## Usage

```powershell
# Offline, read-only inventory and preview.
./scripts/Install-DevelopmentWorkstation.ps1 -CheckOnly
./scripts/Install-DevelopmentWorkstation.ps1 -Insiders -WhatIf

# Prepare the workstation, then explicitly activate it in the current session.
$report = ./scripts/Install-DevelopmentWorkstation.ps1
. $report.ActivationScript

# Native wrkflw 0.8.0 archives are absent on Windows ARM64 and Alpine ARM64.
./scripts/Install-DevelopmentWorkstation.ps1 -SkipWorkflows
```

- `-WorkspaceRoot`: monorepo containing `global.json` and reviewed locks.
- `-InstallRoot`: absolute private tool root; defaults to LocalAppData on Windows or
  `~/.local/share/QuietCli2/development` on Linux.
- `-Insiders`: select VS Code Insiders instead of Stable; retain other installations.
- `-PodmanMachineName`: explicitly select a Windows Podman machine when selection is ambiguous.
- `-SkipEditor`, `-SkipContainers`, `-SkipNativeTools`, `-SkipProfilers`: exclude those components.
- `-SkipWorkflows`: exclude wrkflw, independently of native compilers and containers.
- `-CheckOnly`: read-only local probes; no downloads, directory writes or environment changes.
- `-ExtensionManifest`: saved VS Code extension inventory, default `build/vscode-extensions.json`.
- `-WhatIf` / `-Confirm`: gate provisioning through ShouldProcess. `-WhatIf` still probes tool versions,
  but does not install tools, write activation files, run workflow steps or access the network.

`Components` includes `Workflows` with observed version/path and `Missing`, `Ready`, `Excluded` or
`Unsupported`. A missing native wrkflw artifact remains a gap; use the explicit exclusion to continue
without it. The installer does not silently compile Rust, install Cargo or substitute another RID.

## Dependencies

The script imports `scripts/lib/DevelopmentWorkstation.psm1` and `EditorExtensions.psm1`.
The former owns locked SDK/Git/Zig/wrkflw resolution and uses `Ci.Process.ps1` for native commands;
it does not require a built QuietCli engine. Native archives come from reviewed lock URLs and digests.
The wrkflw pin and four artifacts live in `build/development-workstation.lock.json`.

## Side effects

Approved provisioning installs selected user tools/system prerequisites, may prepare Podman/WSL,
and writes an explicit activation script. No profile is changed; no automatic restart occurs.
The wrkflw component installs a verified official archive under `<InstallRoot>/wrkflw`; activation
adds its directory to PATH once. An exact existing version is reused. Workflow execution, remote
triggering, hooks and credentials are outside installation.

## Findings

- **Control boundary:** `scripts/Install-DevelopmentWorkstation.ps1:63` supplies the caller's
  ShouldProcess callback; `scripts/lib/DevelopmentWorkstation.psm1:686` returns from read-only modes
  before provisioning effects. Inventory probes still run; read-only is not an absence of processes.
- **Platform gap:** `scripts/lib/DevelopmentWorkstation.psm1:693` rejects an unsupported wrkflw RID
  before any other provisioning effects. Windows ARM64/Alpine ARM64 need `-SkipWorkflows`.
- **Validation boundary:** the thin entry point delegates string/path validation to
  `New-DevelopmentPlan` (`scripts/lib/DevelopmentWorkstation.psm1:359`); the native wrkflw lock is
  validated by `Get-DevelopmentWrkflwSpecification` (`:110`).
- **Coverage:** `FrenchExDev2.QuietCli.Core.Tests.PoSh/DevelopmentWorkstation.Tests.ps1:1` asserts
  generated version/host policies, malformed lock/banner inputs, checksum cache integrity,
  activation, control modes, idempotence and targeted mutations. This is not platform-wide
  real installation or actual workflow qualification.

## Verdict

The entry point preserves independent bootstrap, explicit side effects and a structured report.
wrkflw is a separately excludable workstation component. Its usage helpers remain planned, and a
successful installation/version check does not establish GitHub runner compatibility.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [DevelopmentWorkstation.psm1](lib/DevelopmentWorkstation.md), [EditorExtensions.psm1](lib/EditorExtensions.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Installs and checks a complete QuietCli development workstation for the detected host.

Boundary: **Executable**. Preview API: **DelegatedShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
