# Installing QuietCli from PSGallery

QuietCli is distributed as `FrenchExDev2.QuietCli.Core.PoSh`. Test companion modules are not published.

## Installation

```powershell
# Objective: Install the latest stable QuietCli release from PowerShell Gallery.
Install-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Repository PSGallery -Scope CurrentUser

# Objective: Load QuietCli.
Import-Module FrenchExDev2.QuietCli.Core.PoSh
```

Without `-Version`, installation selects the latest stable release available on PSGallery. The optional `-Version` parameter can select a specific release when needed.

Preparing a local nupkg does not make its version available on the gallery. The historical stable package [0.1.0] was published, and its public download was validated on November 5, 2026.

## Runtime requirements and supported platforms

PowerShell Core 7.6+ is required. Install the executable you intend to invoke separately. The SDK is not required to use QuietCli, and installing the module does not download or install any system runtime.

The facade defaults to `Auto` hosting: a CLR 10 PowerShell host uses the integrated net10.0 build; CLR 11+ uses the compatible net11.0 build. Explicit `Process` hosting requires the pinned **.NET 11 RC runtime `11.0.0-rc.3.26522.148`** for the current architecture. Never load the .NET 11 assembly into CLR 10.

The QuietCli package bundles the following C# publications, each with an assembly, apphost and build manifest:

| Operating system / libc | x86-64 | ARM64 |
|---|---|---|
| Windows | `win-x64` | `win-arm64` |
| Linux glibc | `linux-x64` | `linux-arm64` |
| Linux musl / Alpine | `linux-musl-x64` | `linux-musl-arm64` |

The facade selects the actual RID of the PowerShell process. Assemblies use the corresponding `PlatformTarget`; PE/ELF apphosts and SQLite dependencies also match their architecture. Linux PTY bridges are static, built from the supplied C source with a pinned Zig compiler. Zig/musl licenses are retained. Linux 32-bit x86 and ARM32 are not included.

Linux starts the DLL for the selected RID with `dotnet` so that it also works when nupkg installation does not preserve the apphost's executable permissions. The PTY bridge is verified and then copied to a private temporary directory owned by the engine, with 0700 permissions; the installed module remains unchanged, including in a read-only system installation. This file is distributed executable code, never a capture of native output.

## Prerelease installation

To include prereleases when selecting the latest available QuietCli release, add `-Prerelease`. This is independent of the PowerShell stable/preview host. A build or test never publishes a package.

```powershell
# Objective: Install the latest available QuietCli release, including prereleases.
Install-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Prerelease -Repository PSGallery -Scope CurrentUser
```

The development prerelease identity [0.2.0-preview] is an example, not evidence that it is already public. To select a specific release instead of the latest, the optional `-Version` parameter accepts its complete package version, including any prerelease suffix. Installed module directories use the numeric base version; the package identity retains the prerelease suffix.

PowerShell Gallery prerelease labels use the supported alphanumeric/hyphen form. Dotted SemVer 2 labels and build metadata are rejected explicitly. See Microsoft's [prerelease module guidance](https://learn.microsoft.com/powershell/gallery/concepts/module-prerelease-support).

## Publication requirements

A QuietCli release requires qualification of the delivered revision across its supported runtime and platform matrix, including the required property, fuzzing and mutation campaigns. A targeted development run or a successful run for an older revision does not qualify a new release.

Publication must be explicitly requested and must target `FrenchExDev2.QuietCli.Core.PoSh`. Build, test and package preparation do not authorize publication. Repository-wide packaging and publication commands are intentionally omitted from this QuietCli-only installation guide because they also operate on other workspace packages.

Keep API keys out of code, CLI arguments, reports and chat. Follow [Microsoft's publishing guidelines](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines) and the [Publish-PSResource documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource) when preparing an explicitly authorized release.
