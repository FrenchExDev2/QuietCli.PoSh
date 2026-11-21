# Installing QuietCli from PSGallery

QuietCli is the product. Install its Core module as `FrenchExDev2.QuietCli.Core.PoSh`. Add `FrenchExDev2.QuietCli.Git.PoSh` to use the Git handlers.

## Runtime requirements and supported platforms

Use PowerShell Core 7.6+ and install the native executables you plan to run. The distributed module runs without the .NET SDK. In the default `Auto` mode, a CLR 10 host uses the integrated .NET 10 engine and a CLR 11+ host uses the compatible .NET 11 engine. Explicit `Process` mode requires the pinned .NET 11 RC runtime `11.0.0-rc.3.26522.148` for the PowerShell process architecture. See [engine hosting](../readmes/README-hosting.md) for mode selection.

| Platform | x64 | ARM64 |
| --- | --- | --- |
| Windows | `win-x64` | `win-arm64` |
| Linux glibc | `linux-x64` | `linux-arm64` |
| Alpine / Linux musl | `linux-musl-x64` | `linux-musl-arm64` |

Core selects the runtime identifier of the PowerShell process.

## Installation

In PowerShell, find the latest published stable Core package, install it for your account, then load it.

```powershell
Find-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Repository PSGallery
Install-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Repository PSGallery -Scope CurrentUser
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
```

Continue with the [quick start](../README.md#quick-start) or [configure QuietCli](../readmes/README-configuration.md).

## Prerelease installation

Use `-Prerelease` to include available previews in the search and installation.

```powershell
Find-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Repository PSGallery -Prerelease
Install-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Repository PSGallery -Scope CurrentUser -Prerelease
```

Use `-Version` to select a specific published package. For a preview, pass the complete package version including its suffix. The package prerelease choice is independent of the PowerShell host channel. See [Install-PSResource](https://learn.microsoft.com/powershell/module/microsoft.powershell.psresourceget/install-psresource).

## Companion packages

The Git companion declares a compatible Core dependency. Install the native Git executable separately.

```powershell
Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Repository PSGallery -Scope CurrentUser
Import-Module FrenchExDev2.QuietCli.Git.PoSh -ErrorAction Stop
```

Use `-Prerelease` to include Git previews. See the [Git companion guide](../src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/README.md) for supported commands. The [Vagrant source companion](../src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/README.md) is available from the repository.

Maintainers can follow the [release and publication guide](README-preview-releases.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
