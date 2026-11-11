# Installing QuietCli from PSGallery

## GitHub publication

An applicable `develop` push executes `All` qualification and profiling without publishing a module.
An explicit `FrenchExDev2.QuietCli.Core.PoSh/v<version>` tag push requests a Core release after full qualification of the tagged
revision. The tag version must exactly match the source manifest, including its prerelease suffix.
Windows x64 rebuilds all six embedded RIDs in Release ReadyToRun for CLR 10 and 11,
verifies the Windows build, and prepares one public `FrenchExDev2.QuietCli.Core.PoSh` nupkg with `-RequireReadyToRun`.
There is no separate Gallery package per RID. Native Linux matrix tests and Docker fallback qualify
the source revision; the final package is rebuilt on Windows, not assembled from matrix artifacts.

The publish job downloads the prepared nupkg, verifies its recorded hash, version and qualified
checkpoint, then uses `Publish-PSResource -NupkgPath` with the `psgallery` environment secret.
Publication uses the tagged checkpoint even if develop has advanced. Both stable and prerelease
publication require a tag push; workflow dispatch only prepares artifacts. The manual ReadyToRun A/B benchmark
is informational and never blocks a release. See the diagrams and platform details in
[the CI execution model](ci/execution-model.md).

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

The development prerelease identity [0.2.0-preview] is an example, not evidence that it is already public. To select a specific release instead of the latest, the optional `-Version` parameter accepts its complete package version, including any prerelease suffix. Installed module directories use the numeric base version; the package identity retains the prerelease suffix.

PowerShell Gallery prerelease labels use the supported alphanumeric/hyphen form. Dotted SemVer 2 labels and build metadata are rejected explicitly. See Microsoft's [prerelease module guidance](https://learn.microsoft.com/powershell/gallery/concepts/module-prerelease-support).

## Publication requirements

Gallery preparation copies Core into a separate `FrenchExDev2.QuietCli.Core.PoSh` staging directory, preserving its `.psd1` and `.psm1` names and bytes. The shared [module package reader](scripts/Get-ModulePackageName.md) derives the name from the script module and checks its literal sibling manifest. Package preparation, release tags and publication validation consume that identity; no short-name alias is introduced. Versions and GUIDs remain unchanged, and generated calls and companion dependencies use `FrenchExDev2.QuietCli.Core.PoSh` after installation.

For generated artifact-only preview versions, independent module tags and release preparation, see
[preview releases](README-preview-releases.md). Source versions and GUIDs stay unchanged during CI packaging.

A QuietCli release requires qualification of the delivered revision across its supported runtime and platform matrix, including the required property, fuzzing and mutation campaigns for the selected scope. GitHub CI excludes native TTY/PTY campaigns; its reports do not qualify that transport. A targeted development run or a successful run for an older revision does not qualify a new release.

Both stable and prerelease publication are requested by explicit module tag pushes after qualification. Each artifact contains exactly one selected business package; unexpected extra nupkgs are rejected. Get-QuietReleasePlan discovers the owning business manifest and requires its version and publication flag. Core/Git releases use their existing package names; Vagrant requests fail while Publishable=false. New modules join publication through their own metadata and CI qualification declarations rather than a hardcoded release selector.

## Companion packages

| Package | CI publication | Dependency/scope |
| --- | --- | --- |
| FrenchExDev2.QuietCli.Core.PoSh | Enabled | Core engine and supported embedded RIDs |
| FrenchExDev2.QuietCli.Git.PoSh | Enabled | Requires compatible Core; Git command/version qualification remains partial |
| FrenchExDev2.QuietCli.Vagrant.PoSh | Disabled | Source companion; real-provider qualification remains partial |

Install the published Git companion with `Install-PSResource -Name FrenchExDev2.QuietCli.Git.PoSh -Repository PSGallery`; add `-Prerelease` when selecting previews. Its RequiredModules dependency remains FrenchExDev2.QuietCli.Core.PoSh. Publish a compatible Core dependency first; independent simultaneous tag workflows do not guarantee publication order. Package preparation/isolated import checks do not establish which dependency versions are currently available on the public Gallery.

For checked version commits, numbered previews and selected tag pushes, see [the release operator](scripts/New-QuietPreviewTag.md). No module is published merely by merging develop.

Keep API keys out of code, CLI arguments, reports and chat. Follow [Microsoft's publishing guidelines](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines) and the [Publish-PSResource documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource) when preparing an explicitly authorized release.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
