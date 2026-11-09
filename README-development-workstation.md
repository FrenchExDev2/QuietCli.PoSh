# Development workstation

[Development workflow](README-development.md) · [Tests and qualification](README-qualification.md) · [Documentation index](docs/README.md)

Install **PowerShell Core 7.6 or later first**, obtain this repository, then run
`scripts/Install-DevelopmentWorkstation.ps1`. The installer prepares a complete workstation by default.
It can run before QuietCli has been built: native tools use the independent CI process helper.

## What to install

| Tool | Purpose and required version | Installation | Verification |
| --- | --- | --- | --- |
| PowerShell | Core **7.6+**; normal profiles and UTF-8 | Bootstrap below; repository Windows qualification locks Stable 7.6.7 and Preview 7.7.0-preview.5 separately | `$PSVersionTable`; `[Environment]::Version` |
| .NET SDK | **Exact `sdk.version` in `global.json`**, currently `11.0.100-rc.3.26522.148` | Checksum-locked official archive in the user tool directory | `dotnet --version` from this checkout; `dotnet --list-sdks` |
| Git | Stable **>= 2.40.0, < 2.57.0** for the Git companion | Preserve a compatible Git; otherwise install the locked 2.56.0 beside the system copy | `git --version` |
| VS Code | Stable by default; **`-Insiders`** selects Insiders | WinGet on Windows; official DEB/RPM on glibc Linux; remote editing on Alpine | `code --version` or `code-insiders --version` |
| Editor extensions | Saved Insiders inventory plus the minimum PowerShell/C#/remote set | Shared extension synchronizer in the selected channel | `code --list-extensions` or `code-insiders --list-extensions` |
| Podman | Distribution/current official release; Windows release requires Windows 11 and virtualization | Distribution packages or WinGet, then WSL/machine preparation | `podman info --format json` |
| wrkflw | **0.8.0**, local GitHub Actions listing, validation and execution | SHA-256-locked official native archive; `-SkipWorkflows` excludes it | `wrkflw --version`; a version check does not qualify workflows |
| Vagrant | Stable **>= 2.3.0, < 2.5.0** for the Vagrant companion; **Windows/Debian/Ubuntu/Fedora only**, not Alpine | Official HashiCorp apt repository, WinGet/MSI or Fedora build -- see [Vagrant](#vagrant-windowsdebianubuntufedora-only) below; `./scripts/Install-ModuleWorkstation.ps1 -Modules Vagrant` | `vagrant --version` |
| GCC / Clang | Linux C properties, libFuzzer and ASan/UBSan/LSan | Distribution compiler, headers and compiler-runtime packages | `gcc --version`; `clang --version`; native qualification below |
| Zig | **0.15.2**, from `build/zig.lock.json` | Checksum-verified portable archive | `zig version` |
| Profiler / dotnet-trace | **4.3.0 / 10.0.750501** | Existing `Initialize-Profilers.ps1` and its checked package cache | Pinned archives and entrypoints checked by the installer |

The SDK compiles both **`net10.0` and `net11.0`** targets. A separate .NET 10 SDK is not required for the
normal build. PowerShell's bundled CLR is a different selection: Stable 7.6 uses .NET 10, and the locked
Preview host uses .NET 11. Keep engine hosting at `Auto`; isolated `Process` hosting uses the .NET 11
runtime included in the pinned SDK. A runtime alone cannot compile the repository.

Alpine's distribution PowerShell is framework-dependent and needs the distribution's .NET 10 runtime.
When preparing a private SDK root, the installer copies the already running host's shared framework
beside .NET 11 and verifies it remains discoverable. This preserves new `pwsh` processes after activation;
installing a .NET 10 SDK remains unnecessary. Re-run setup after updating that distribution runtime.

The workstation installer requires the exact SDK even when `global.json` allows roll-forward. Windows SDK hashes are
in `build/development-workstation.lock.json`; Linux hashes reuse `build/ci-images.lock.json`. Both must
match `global.json`. Update these reviewed locks together when intentionally changing SDK versions.
Official [.NET release metadata](https://builds.dotnet.microsoft.com/dotnet/release-metadata/11.0/releases.json)
provides artifact URLs and SHA-512 digests. Checksums verify content; package publishers remain separate
trust decisions.

The automated recipes cover native x64 and ARM64 on **Windows 11; Debian 12/13; Ubuntu 24.04/26.04 LTS;
Fedora 43/44; Alpine 3.23/3.24**. Unknown distributions, versions and emulated PowerShell processes are
rejected. These recipes describe installation targets, not an assertion that every target has passed
the product's release matrix. Existing product qualification covers its recorded hosts only.

### Local workflows with wrkflw

The default installer includes wrkflw in the `Workflows` component. It preserves an existing exact
0.8.0 installation; otherwise it extracts the reviewed binary into `<InstallRoot>/wrkflw`, keeps its
verified archive in `<InstallRoot>/downloads`, and includes the tool in the generated session activation
script. Rust and Cargo are not needed. The lock's release URLs and SHA-256 digests are reviewed inputs;
setup never resolves a moving latest release or changes a profile.

Published native artifacts cover Windows x64, glibc Linux x64/ARM64 and musl Linux x64. **Windows ARM64
and Alpine ARM64 require `-SkipWorkflows`**: the component reports `Unsupported` and a mutating setup
fails before other provisioning if no reviewed native artifact exists. Setup does not substitute an
emulated binary. This exception narrows the wrkflw component, not the remaining workstation recipes.

After activation, 0.8.0 supports listing with `list --jobs`, definition checks with `validate`,
execution with `run --runtime podman`, and interactive use with `tui --runtime podman`.
It has no `plan`, general JSON output or MCP interface. Emulation runs commands and is not a dry run.
The planned PowerShell helpers and their `-WhatIf` contract are documented in
[scripts to create](docs/scripts/README-wrkflw-plan.md); they are not implemented commands.
Installing or checking wrkflw does not launch any workflow, container or remote run. Existing test
monitors, CI images and release qualification remain required for actual execution.

Sources: [0.8.0 release](https://github.com/bahdotsh/wrkflw/releases/tag/v0.8.0),
[MIT license](https://github.com/bahdotsh/wrkflw/blob/v0.8.0/LICENSE) and
[versioned CLI contract](https://github.com/bahdotsh/wrkflw/blob/v0.8.0/crates/wrkflw/src/main.rs).

## Bootstrap PowerShell and obtain the checkout

These initial commands run before a local `quiet` engine exists. Use an ordinary terminal, and install
only the bootstrap tools here; the PowerShell installer handles the remaining dependencies.
The shell blocks use `sudo`; omit it when already root. Later, run the installer as your normal user,
after `sudo -v` when Linux system packages are needed. It uses `sudo -n` rather than collecting passwords.

### Windows: WinGet

From Windows PowerShell or a terminal with [WinGet](https://learn.microsoft.com/windows/package-manager/winget/):

```powershell
winget install --exact --id Microsoft.PowerShell --source winget
winget install --exact --id Git.Git --version 2.56.0 --source winget
```

WinGet selects x64 or ARM64 for the host. Close the terminal and open **PowerShell 7.6+**, with its normal
profile. If WinGet is absent, install App Installer using Microsoft's linked instructions, or use the
official [PowerShell MSI/ZIP instructions](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).
Windows PowerShell 5.1 cannot execute the workstation installer.

### Debian: APT

For x64, register the Microsoft repository for the actual supported Debian version:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git tar gzip
. /etc/os-release
curl --fail --location "https://packages.microsoft.com/config/debian/$VERSION_ID/packages-microsoft-prod.deb" -o /tmp/quietcli-microsoft.deb
sudo dpkg -i /tmp/quietcli-microsoft.deb
sudo apt-get update
sudo apt-get install -y powershell
pwsh
```

For ARM64, use the verified binary-archive block below after installing the Debian runtime dependencies:

```bash
# Debian 12; on Debian 13 replace libicu72/libssl3 with libicu76/libssl3t64.
sudo apt-get install -y libicu72 libssl3 libgcc-s1 libstdc++6 libgssapi-krb5-2 zlib1g
```

See [PowerShell on Debian](https://learn.microsoft.com/powershell/scripting/install/install-debian).

### Ubuntu: APT

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git tar gzip
. /etc/os-release
curl --fail --location "https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb" -o /tmp/quietcli-microsoft.deb
sudo dpkg -i /tmp/quietcli-microsoft.deb
sudo apt-get update
sudo apt-get install -y powershell
pwsh
```

Use the archive block for ARM64 after installing `libicu74 libssl3t64 libgcc-s1 libstdc++6
libgssapi-krb5-2 zlib1g` on Ubuntu 24.04; use `libicu78` on 26.04. Avoid mixing distribution and Microsoft
.NET packages: the workstation installer uses its private SDK directory.
See [PowerShell on Ubuntu](https://learn.microsoft.com/powershell/scripting/install/install-ubuntu).

### Fedora: DNF and official archive

```bash
sudo dnf install -y ca-certificates curl git tar gzip libicu openssl-libs krb5-libs libgcc libstdc++ zlib-ng-compat
# Continue with the verified archive block below (x64 or ARM64).
```

This uses an official PowerShell archive instead of registering a RHEL package repository on Fedora.
Distribution support and installation mechanics are distinct; see Microsoft's
[alternative installation methods](https://learn.microsoft.com/powershell/scripting/install/alternate-install-methods).

### Shared verified PowerShell archive: glibc Linux x64/ARM64

Run after installing the bootstrap dependencies above:

```bash
set -eu
case "$(uname -m)" in
  x86_64) ps_arch=x64 ;;
  aarch64) ps_arch=arm64 ;;
  *) echo 'Unsupported architecture' >&2; exit 1 ;;
esac
ps_version=7.6.7
ps_work=$(mktemp -d)
cd "$ps_work"
ps_archive="powershell-$ps_version-linux-$ps_arch.tar.gz"
curl --fail --location "https://github.com/PowerShell/PowerShell/releases/download/v$ps_version/$ps_archive" -o "$ps_archive"
curl --fail --location "https://github.com/PowerShell/PowerShell/releases/download/v$ps_version/hashes.sha256" -o hashes.sha256
# Select exactly the downloaded artifact, then verify before extracting.
awk -v name="$ps_archive" '$2 == name || $2 == "*" name { print; found=1 } END { if (!found) exit 1 }' hashes.sha256 > selected.sha256
sha256sum -c selected.sha256
sudo mkdir -p "/opt/microsoft/powershell/$ps_version"
sudo tar -xzf "$ps_archive" -C "/opt/microsoft/powershell/$ps_version"
sudo chmod +x "/opt/microsoft/powershell/$ps_version/pwsh"
# Use the absolute path; this does not replace an existing /usr/bin/pwsh.
"/opt/microsoft/powershell/$ps_version/pwsh"
```

Subsequent commands can use that absolute PowerShell path when `pwsh` is not on `PATH`.

### Alpine: APK and musl

Enable **community for the same stable Alpine branch** if it is not already enabled. Do not mix stable
repositories with edge. Alpine's community PowerShell package provides native x86_64/aarch64 builds;
check the candidate is 7.6+.

```sh
sudo apk add --no-cache ca-certificates curl git bash tar gzip xz icu-libs icu-data-full libgcc libstdc++ libssl3 krb5-libs zlib
sudo apk add --no-cache powershell
pwsh
```

If the package is unavailable, check `/etc/apk/repositories` and the selected stable branch before
continuing. The upstream musl archive recipe is described in
[PowerShell on Alpine](https://learn.microsoft.com/powershell/scripting/install/install-alpine);
do not substitute a glibc archive or an x64 archive on ARM64.

**Alpine has no official VS Code Desktop package.** The installer reports `RemoteRequired` for the
editor and prepares the command-line workstation. Install VS Code on Windows or a glibc desktop and
attach through WSL or Dev Containers. Some extensions bundle native code that does not support musl;
see [Remote Development with Linux](https://code.visualstudio.com/docs/remote/linux). The selected
`-Insiders` channel applies to the external desktop in this arrangement.

### Vagrant (Windows/Debian/Ubuntu/Fedora only)

The [Vagrant companion module](FrenchExDev2.QuietCli.Vagrant.PoSh/README.md) is optional and installed
separately from the main workstation pipeline above, via
`./scripts/Install-ModuleWorkstation.ps1 -Modules Vagrant` (see [that script's own
documentation](scripts/Install-ModuleWorkstation.ps1) for `-CheckOnly`/`-Download`/`-WhatIf`). It targets
**development-workstation hosts only** -- Windows, Debian, Ubuntu and Fedora -- not Alpine/musl, which this
repository only uses as a CI/container target (`EditorMode='Remote'`), never as a Vagrant host.

Install Vagrant itself from HashiCorp's own official channels:

- **Windows**: `winget install --exact --id Hashicorp.Vagrant --source winget`, or the official
  [Windows installer](https://developer.hashicorp.com/vagrant/install#windows).
- **Debian/Ubuntu**: HashiCorp's [official apt repository](https://developer.hashicorp.com/vagrant/install#linux)
  (adds HashiCorp's own signing key and repository, then `sudo apt-get install vagrant`).
- **Fedora**: use HashiCorp's published build for the installed Fedora release from the same
  [Linux installation page](https://developer.hashicorp.com/vagrant/install#linux), or build from the
  [official source releases](https://developer.hashicorp.com/vagrant/downloads) when HashiCorp has not yet
  published a build for that release.

A container provider (Docker or Podman) is **not redocumented here**: it is the same `Containers` component
(`podman`) already covered above and probed by `Get-DevelopmentInventory`. See the Vagrant module's own
[fixture documentation](FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/fixture/README.md) for the Docker-provider
choice and the Podman "sans plugin" (`DOCKER_HOST`) alternative.

### Clone once, then select the workstation

In PowerShell 7.6+, using Git installed during bootstrap:

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
New-Item -ItemType Directory -Path (Split-Path $checkout -Parent) -Force | Out-Null
git clone --branch develop https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh.git $checkout
if ($LASTEXITCODE -ne 0) { throw 'CheckoutFailed' }
Set-Location $checkout
```

For an existing checkout, change to its root and skip the clone.

## Install the workstation

Editor setup installs/updates the saved [Insiders extension inventory](build/vscode-extensions.json)
through `Sync-DevelopmentEditorExtensions.ps1 -Update`. See the [extension export and synchronization
guide](docs/README-development-editor-extensions.md) for `-Export`, `-Update`, `-WhatIf`, release preferences
and standalone Stable/Insiders examples. Use `-ExtensionManifest` to select another inventory.

```powershell
# Inspect local versions and missing components; offline and read-only.
./scripts/Install-DevelopmentWorkstation.ps1 -CheckOnly
./scripts/Install-DevelopmentWorkstation.ps1 -Insiders -WhatIf

# Complete workstation with Stable, or explicitly choose Insiders.
$report = ./scripts/Install-DevelopmentWorkstation.ps1
# $report = ./scripts/Install-DevelopmentWorkstation.ps1 -Insiders
$report.Components | Format-List Name, State, Version, Path, Detail
```

The script preserves compatible tools, installs missing system dependencies, verifies private SDK/Git/Zig
archives, and prepares the existing pinned profiler cache. An incompatible distribution Git triggers a
separate source build under the user tool directory; its compiler packages remain necessary even with
`-SkipNativeTools`. Windows extracts the locked official MinGit ZIP in a separate user directory,
preserving system Git registration and persistent `PATH`. This CLI distribution omits the Git GUI.

The editor is intentionally a current Stable/Insiders channel, rather than a locked compiler artifact.
Windows uses the WinGet manifest verification; Linux downloads the official channel DEB/RPM and installs
its dependencies through APT/DNF. Local DEB installation does not authenticate an archive with a pinned
repository digest. SDK, Git and Zig remain checksum-pinned separately.

| Option | Behavior |
| --- | --- |
| `-Insiders` | Select `code-insiders`; Stable is the default |
| `-InstallRoot <absolute path>` | Override `%LOCALAPPDATA%/QuietCli2/development` or `~/.local/share/QuietCli2/development` |
| `-PodmanMachineName <name>` | Select an existing or new Windows machine; otherwise reuse the default/unique machine |
| `-SkipEditor` | Exclude editor and extensions; useful on servers |
| `-SkipContainers` | Exclude Podman and WSL/machine preparation |
| `-SkipNativeTools` | Exclude Zig and optional native campaign packages |
| `-SkipProfilers` | Exclude diagnostic packages |
| `-CheckOnly` | Read local inventory; no downloads, writes or extension installation |
| `-WhatIf` | Show the proposed operation with the same read-only inventory |

The report distinguishes `Ready`, `NeedsInstallation`, `RestartRequired` and `Failed`, with per-component
states and explicit exclusions. Provisioning failures emit the report and throw. Control modes return
`NeedsInstallation` when prerequisites are missing; check the report rather than inferring readiness from
the script's return alone. Rootless Podman configuration, unavailable packages, missing rights and failed
downloads remain actionable failures.

### Windows WSL2 and Podman

The default prepares Podman as well as installing its CLI. Windows needs virtualization, WSL2 and
sufficient memory; new machines request 6 GiB. If WSL must be enabled, run the installer from an elevated
PowerShell session **for the same user**, restart Windows when `RestartRequired` is returned, then rerun
the same command. The script never initiates a restart.

Existing machines are preserved. Multiple machines without a clear default require
`-PodmanMachineName`. A selected connection is written to the activation script through
`CONTAINER_CONNECTION`; existing global default connections are not switched. Docker installations
are preserved; these recipes prepare Podman for the repository's Podman-based launchers.
See [Podman installation](https://podman.io/docs/installation) and
[Windows setup](https://podman-desktop.io/docs/installation/windows-install).

### Activate, verify and open the editor

The installer prints the exact activation command. In each new normal-profile PowerShell session:

```powershell
$toolRoot = if ($IsWindows) { Join-Path $env:LOCALAPPDATA 'QuietCli2/development' } else { Join-Path $HOME '.local/share/QuietCli2/development' }
. (Join-Path $toolRoot 'Activate-DevelopmentEnvironment.ps1')
Set-Location $checkout
dotnet --version
dotnet --list-runtimes
git --version
podman info --format json
code ./QuietCli2.code-workspace
# Insiders: code-insiders ./QuietCli2.code-workspace
```

Launch VS Code from this activated session so its terminals and C# extension inherit the selected SDK.
The activation script is idempotent and does not edit profiles. Zig is available as `zig` and through
`$env:QUIETCLI_DEVELOPMENT_ZIG`; profiler paths are recorded in `<toolRoot>/profilers/tool-receipt.json`.
When using a custom `-InstallRoot`, substitute that directory in the block above.

The manual editor equivalents are `winget install --exact --id Microsoft.VisualStudioCode` or
`Microsoft.VisualStudioCode.Insiders`; on Linux use the official
[APT/RPM installation recipes](https://code.visualstudio.com/docs/setup/linux), selecting `code` or
`code-insiders`. Extensions install with `--install-extension ms-vscode.PowerShell`,
`ms-dotnettools.csharp` and `ms-vscode-remote.remote-containers`; add
`ms-vscode-remote.remote-wsl` on Windows.

## Select Git and Vagrant independently

```powershell
./scripts/Install-ModuleWorkstation.ps1 -Modules Git,Vagrant -CheckOnly
./scripts/Install-ModuleWorkstation.ps1 -Modules Git,Vagrant -WhatIf
./scripts/Install-ModuleWorkstation.ps1 -Modules Vagrant -Download
./scripts/Install-ModuleWorkstation.ps1 -Modules Git,Vagrant
```

The selector requires an explicit module list and preserves its order. `-CheckOnly` only probes;
`-Download` caches and verifies artifacts even on an already ready host, without installation.
These switches are mutually exclusive. `-WhatIf` suppresses both downloading and installation.
The default installs missing tools without a confirmation prompt under PowerShell's default preferences;
system package operations still need administrator/root rights or pre-authorized `sudo -n`.

Git uses the existing locked source/MinGit recipes. Its owned installation is preferred by subsequent
checks; add its `git/cmd` (Windows) or `git/bin` (Linux) directory to the calling session's PATH when
using it outside these scripts. The module cache is `%LOCALAPPDATA%/QuietCli2/modules` on Windows and
`~/.local/share/QuietCli2/modules` on Linux. Linux download mode caches Git source; distribution build
dependencies remain the package manager's responsibility.

Vagrant uses [HashiCorp's official packages](https://developer.hashicorp.com/vagrant/install), version
`2.4.9`, with SHA-256 values recorded in `build/vagrant-installers.lock.json` from the
[official checksum list](https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9_SHA256SUMS).
Windows x64 uses MSI (`/qn /norestart`); Debian/Ubuntu x64 use the DEB through APT; Fedora x64 uses
the RPM through DNF. No ARM64 package for these targets appears in that release: those installer
targets and Alpine are explicit gaps. A compatible existing tool can still be checked there.
No installer restarts the machine; MSI code 3010 reports `RestartRequired`.

Vagrant readiness also requires a working `docker info` client. For the documented Podman socket
wiring, provide a Docker-compatible client and set `DOCKER_HOST`; installing Podman alone does not
establish provider readiness. These scripts do not configure a container engine. See the
[Vagrant fixture guide](FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/fixture/README.md) for provider setup
and manual multi-machine checks. `State` describes readiness; `Action` and `CachePath` separately
record what download/install mode did. Real installation tests are manual; automated tests trap
all download/install effects.

## First build and qualification boundaries

```powershell
./scripts/Initialize-Workspace.ps1 -Restore
./scripts/Build-Workspace.ps1
# Open a fresh normal-profile PowerShell session, activate it, then:
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1
./scripts/Invoke-WorkspaceCi.ps1 -Suite All -SkipBuild
```

On an intentionally modified checkout, refresh the local source lock using
`Initialize-Workspace.ps1` without `-Restore` before validation. Builds verify existing bundled PTY
bridges. To rebuild their C source explicitly:

```powershell
./scripts/Build-PtyBridge.ps1 -CompilerPath $env:QUIETCLI_DEVELOPMENT_ZIG
```

Installed compilers do not constitute native qualification. Full native C campaigns require generated
properties, 20,000 libFuzzer executions with sanitizers and the targeted mutation catalogue. On musl the
fuzzer requires a container memory limit of at most 1 GiB. Use the existing monitored container/native
launchers and matching architecture; see [Tests and qualification](README-qualification.md).

The local visible monitor currently uses the Windows host launcher. Linux hosts can develop/build and
run CI headlessly, but a headless local test does not satisfy the repository's visible-monitor rule.
The installer does not claim to add a Linux desktop test monitor or qualify unexecuted architectures.

## Disposable installation smoke tests and cleanup

From a Windows host with working Podman, run the companion smoke launcher:

```powershell
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-DevelopmentWorkstationSmoke.ps1

# Windows controls and wrkflw archive/list/validation smoke only; no Podman required.
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-DevelopmentWorkstationSmoke.ps1 -Targets Windows
```

It opens the shared visible monitor. Windows exercises read-only control modes, installs only the
reviewed wrkflw binary in an external toolchain cache, and checks real job listing plus valid/invalid
workflow definition exit codes without executing workflow steps. Debian, Ubuntu,
Alpine and Fedora perform real package/tool installations inside disposable containers, with a
read-only source snapshot. Editor and nested Podman installation are excluded in those guests.
The guest checks activation, a second idempotent installation and a small sanitizer/linker probe;
this smoke probe is separate from the product's complete native fuzz/mutation qualification.

Every new run records `ownership.json`: source workspace, worker PID and creation time, host/user,
terminal state and exact labelled disposable image/container names. A live `run.lease` protects the
run independently of timestamps. Completed runs release their own inactive containers and images
without `--force` or `prune`; base images and resources in use are preserved. Reports and failure
diagnostics remain available under the printed temporary run directory. Monitor errors are saved
to `monitor*.stderr.log`; repeated monitor failure is bounded and stops the owned worker.

```powershell
# Read the cleanup decisions before removing anything.
./scripts/Remove-DevelopmentWorkstationRun.ps1 -WhatIf
# Normal policy: retain seven days and at least the three latest runs.
./scripts/Remove-DevelopmentWorkstationRun.ps1
```

The enclosing workspace's `scripts/Invoke-ArtifactsCleanup.ps1` also calls this cleanup, including
when its `.artifacts` directory is absent. Use `-Category workstation` to select these runs or
`-SkipQuietCliWorkstation` to leave them out. Active, foreign, linked or unverifiable runs are kept;
legacy runs without an ownership receipt are reported as `Unmanaged` and preserved. User tool
installations under LocalAppData or `~/.local/share` are never treated as disposable smoke artifacts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
