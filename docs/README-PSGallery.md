# Installing QuietCli from PSGallery

## GitHub publication

An applicable `develop` push executes `All` qualification and profiling without publishing a module.
An explicit `QuietCli/v<version>` tag push requests a Core release after full qualification of the tagged
revision. The tag version must exactly match the source manifest, including its prerelease suffix.
Windows x64 rebuilds all six embedded RIDs in Release ReadyToRun for CLR 10 and 11,
verifies the Windows build, and prepares one public `QuietCli` nupkg with `-RequireReadyToRun`.
There is no separate Gallery package per RID. Native Linux matrix tests and Docker fallback qualify
the source revision; the final package is rebuilt on Windows, not assembled from matrix artifacts.

The publish job downloads the prepared nupkg, verifies its recorded hash, version and qualified
checkpoint, then uses `Publish-PSResource -NupkgPath` with the `psgallery` environment secret.
Publication uses the tagged checkpoint even if develop has advanced. Both stable and prerelease
publication require a tag push; workflow dispatch only prepares artifacts. The manual ReadyToRun A/B benchmark
is informational and never blocks a release. See the diagrams and platform details in
[the CI execution model](ci/execution-model.md).

The public PowerShell module and Gallery package are named `QuietCli`; they provide Core. `FrenchExDev2.QuietCli.Core.PoSh` is the internal source project name, not a public package. The Git example and test companion modules are not published.

## Installation

```powershell
# Objective: Install the latest stable QuietCli release from PowerShell Gallery.
Install-PSResource -Name QuietCli -Repository PSGallery -Scope CurrentUser

# Objective: Load QuietCli.
Import-Module QuietCli
```

Without `-Version`, installation selects the latest stable release available on PSGallery. The optional `-Version` parameter can select a specific release when needed.

Preparing a local nupkg does not make its version available on the gallery. Installation can select only versions actually published under the `QuietCli` package name.

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
Install-PSResource -Name QuietCli -Prerelease -Repository PSGallery -Scope CurrentUser
```

The development prerelease identity [0.2.0-preview] is an example, not evidence that it is already public. To select a specific release instead of the latest, the optional `-Version` parameter accepts its complete package version, including any prerelease suffix. Installed module directories use the numeric base version; the package identity retains the prerelease suffix.

PowerShell Gallery prerelease labels use the supported alphanumeric/hyphen form. Dotted SemVer 2 labels and build metadata are rejected explicitly. See Microsoft's [prerelease module guidance](https://learn.microsoft.com/powershell/gallery/concepts/module-prerelease-support).

## Publication requirements

Gallery preparation copies the internal Core project into a separate `QuietCli` staging directory, with `QuietCli.psd1` and `QuietCli.psm1`. The package, publication plan, validation and installation probes use the public `QuietCli` identity. Source project names, manifest versions and GUIDs stay unchanged. Generated calls and companion dependencies use the identity of the imported module, including `QuietCli` after installation.

For generated artifact-only preview versions, independent module tags and release preparation, see
[preview releases](README-preview-releases.md). Source versions and GUIDs stay unchanged during CI packaging.

A QuietCli release requires qualification of the delivered revision across its supported runtime and platform matrix, including the required property, fuzzing and mutation campaigns for the selected scope. GitHub CI excludes native TTY/PTY campaigns; its reports do not qualify that transport. A targeted development run or a successful run for an older revision does not qualify a new release.

Both stable and prerelease publication are requested by explicit Core tag pushes after the configured CI qualification. Build, test and manual package preparation do not publish. Public package preparation and publication currently reject Git or any extra nupkg. Git and Vagrant retain independent source versions and reserved `QuietCli.Git/v*` / `QuietCli.Vagrant/v*` namespaces; their nonpublishable manifests and missing public packaging reject release requests before qualification. Their activation requires public dependency staging and offline installation/import checks, not a shared Core version bump.

Keep API keys out of code, CLI arguments, reports and chat. Follow [Microsoft's publishing guidelines](https://learn.microsoft.com/en-us/powershell/gallery/concepts/publishing-guidelines) and the [Publish-PSResource documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/publish-psresource) when preparing an explicitly authorized release.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
