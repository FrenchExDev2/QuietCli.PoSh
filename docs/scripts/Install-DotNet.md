# Install-DotNet.ps1

## Purpose

Install a verified portable SDK and its included runtimes; optionally pull images,
update exact SDK pins and activate this process. [Complete guide](../../README-dotnet-and-global-dot-json.md).

## Usage and parameters

```powershell
./scripts/Install-DotNet.ps1 -Channel 11.0 -UpdateGlobalJson -ActivateSession -WhatIf
$setup = ./scripts/Install-DotNet.ps1 -Channel 11.0 -UpdateGlobalJson -ActivateSession -Confirm
```

Parameters: Channel, Version, Preleases (aliases Prerelease/Prereleases), InstallRoot,
UpdateGlobalJson, GlobalJsonPath, PullImages, ContainerRuntime, Platform, ImageVariant,
ActivateSession, AllowDowngrade, DownloadTimeoutSeconds and QuietCliRoot. Defaults are
stable channel 11.0, this checkout's .dotnet directory and root global.json; optional
effects are off. See the [library contract](lib/DotNetProvisioning.md).

## Dependencies and effects

Imports scripts/lib/DotNetProvisioning.psm1. The approved operation can download/extract
a checksum-verified SDK, launch bounded native discovery/pulls, write receipts/backed-up
pins and optionally change process-only environment variables. WhatIf returns before
those effects. Container resolution follows RAC-ENV-001 and starts no daemon.

## Findings

- The wrapper guard at scripts/Install-DotNet.ps1:49 protects orchestration; the library
  independently guards direct function use. Nested confirmation is suppressed only after approval.
- scripts/lib/DotNetProvisioning.psm1:325 checks actual archive SHA-512 before extraction.
  Offline fixtures exercise this boundary; real SDK installation and native pulls remain unqualified.
- Pin writes are atomic per file, not across multiple files or completed image pulls.
  A later failure can leave an installed SDK or an earlier updated pin; backups remain available.

## Verdict

Suitable for reviewed opt-in portable installation. It does not install OS prerequisites,
IIS Hosting Bundle, workloads or a machine-wide registration.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [DotNetProvisioning.psm1](lib/DotNetProvisioning.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Installs the SDK with its runtimes, optionally pulls images and updates SDK pins.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
