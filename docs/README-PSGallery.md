# Installing QuietCli from PSGallery

## GitHub publication

Pushes to `develop` use [change-based qualification](ci/README.md#end-to-end-routing). Release tags
such as `FrenchExDev2.QuietCli.Core.PoSh/v<version>` and `FrenchExDev2.QuietCli.Git.PoSh/v<version>`
request publication with `All` qualification for the exact tagged revision. The version must match
the owning manifest, including its prerelease suffix. Manual dispatch prepares artifacts only.
See the [release guide](README-preview-releases.md#module-release-tags-and-independent-versions)
and the [CI execution model](ci/execution-model.md#gallery-publication).

QuietCli is the product name. Core and Git retain their existing PowerShell Gallery identities, FrenchExDev2.QuietCli.Core.PoSh and FrenchExDev2.QuietCli.Git.PoSh. Both are enabled as independently versioned CI publication targets. Git's package contains its parser outputs and a declared dependency on Core; it never embeds the Core package. Vagrant remains disabled and test modules are never public release targets.

## Installation

```powershell
# Objective: Install the latest stable QuietCli release from PowerShell Gallery.
Install-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Repository PSGallery -Scope CurrentUser

# Objective: Load QuietCli.
Import-Module FrenchExDev2.QuietCli.Core.PoSh
```

Without `-Version`, installation selects the latest stable release available on PSGallery. The optional `-Version` parameter can select a specific release when needed.

Preparing a local nupkg does not make its version available on the gallery. Installation can select only versions actually published under the `FrenchExDev2.QuietCli.Core.PoSh` package name.

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

To select a specific published release, pass its complete package version to `-Version`, including any prerelease suffix. Installed module directories use the numeric base version and the package identity retains the suffix.

PowerShell Gallery prerelease labels use the supported alphanumeric/hyphen form. Dotted SemVer 2 labels and build metadata are rejected explicitly. See Microsoft's [prerelease module guidance](https://learn.microsoft.com/powershell/gallery/concepts/module-prerelease-support).

## Publication requirements

The Windows x64 packaging job rebuilds the six embedded Core RIDs in Release ReadyToRun for CLR 10 and 11 and prepares a single Core nupkg. Git packages carry their own parser outputs and the declared Core dependency. A standalone release prepares one package. An annotated release batch prepares one package per selected module and publishes in dependency order.

The [release guide](README-preview-releases.md) covers artifact-only previews, release qualification, package verification and publication receipts. GitHub CI records its native TTY/PTY exclusion in the qualification scope.

## Companion packages

| Package | CI publication | Dependency/scope |
| --- | --- | --- |
| FrenchExDev2.QuietCli.Core.PoSh | Enabled | Core engine and supported embedded RIDs |
| FrenchExDev2.QuietCli.Git.PoSh | Enabled | Requires compatible Core; Git command/version qualification remains partial |
| FrenchExDev2.QuietCli.Vagrant.PoSh | Disabled | Source companion; real-provider qualification remains partial |

Install the published Git companion with `Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Repository PSGallery`; add `-Prerelease` when selecting previews. Its RequiredModules dependency remains FrenchExDev2.QuietCli.Core.PoSh. Operator-created batches qualify once and publish Core before Git. Separately created manual tags remain independent; publish a compatible Core dependency first. Public indexing delays can reject Git even after Core upload. Package preparation/isolated import checks do not establish which versions are currently available on the Gallery.

Use [Invoke-QuietRelease](scripts/Invoke-QuietRelease.md) for the release workflow. The [manual single-module operator](scripts/New-QuietPreviewTag.md) handles checked tags when required.

Keep API keys out of code, CLI arguments, reports and chat. Follow [Microsoft's publishing guidelines](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines) and the [Publish-PSResource documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource) when preparing an explicitly authorized release.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
