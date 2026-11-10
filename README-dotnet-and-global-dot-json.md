# .NET SDK updates and global.json

Run these commands from the QuietCli checkout in PowerShell **7.6+ / .NET 10+** with
the normal profile. These repository scripts use the independent `Ci.Process.ps1`
helper, so SDK checks and installation do not require a compiled QuietCli engine.

## Check the current situation

```powershell
Set-Location C:/code/FrenchExDev/FrenchExDev_i2/PoSh/FrenchExDev/QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh

# Preview without HTTP/native probes or report writes.
./scripts/Test-DotNetReadiness.ps1 -WhatIf

$report = ./scripts/Test-DotNetReadiness.ps1
$report.Checks | Select-Object Category, Target, Status, Detail

# Optionally include published previews and release candidates.
$report = ./scripts/Test-DotNetReadiness.ps1 -Preleases

# Save observations; the parent directory must already exist.
$report = ./scripts/Test-DotNetReadiness.ps1 -ReportPath ./readiness.json
```

The report separates SDK publication/archive availability, MCR manifests/platforms,
installed SDKs/runtimes and actual SDK resolution in the selected project directory.
`Available` requires successful evidence; `Missing` means explicit absence or no
eligible version/platform; `Unknown` means failed/unavailable evidence, including TLS
or authentication errors; `NotChecked` means skipped, declined or previewed.
Readiness never installs anything. The existing
[`Test-SdkReadiness.ps1`](docs/scripts/Test-SdkReadiness.md) separately checks pinned
SDK freshness and ReadyToRun/Crossgen2 feasibility.

## Install the latest stable SDK and included runtimes

The SDK includes the .NET and ASP.NET Core runtimes and, on Windows, Desktop.
The portable installation lives under `.dotnet/<SDK-version>` and needs no administrator
rights. Each version has its own host. It does not register a machine-wide installation
or install IIS Hosting Bundle, native OS packages or workloads.

```powershell
# Review first; no downloads, extraction, files or environment edits.
./scripts/Install-DotNet.ps1 -Channel 11.0 -UpdateGlobalJson -ActivateSession -WhatIf

# Install the latest eligible SDK and update this checkout's global.json.
$setup = ./scripts/Install-DotNet.ps1 -Channel 11.0 `
    -UpdateGlobalJson -ActivateSession -Confirm

$setup | Select-Object Status, Version, RuntimeVersion, SdkDirectory, DotNetPath
$setup.GlobalJson | Select-Object Path, Status, BackupPath
```

Use the same command later to install the newest published patch/feature band in that
channel. Existing complete versions are verified and reused; older versions are not
deleted. Existing incomplete installations are rejected instead of silently overwritten.

For a precise version or a different channel:

```powershell
# Pin an exact published SDK version within its channel.
$setup = ./scripts/Install-DotNet.ps1 -Channel 11.0 -Version 11.0.100 `
    -UpdateGlobalJson -ActivateSession -Confirm

# A future channel works after Microsoft publishes eligible release metadata.
./scripts/Install-DotNet.ps1 -Channel 12.0 -Preleases -WhatIf

# Install only: leave source pins and session activation to separate commands.
$setup = ./scripts/Install-DotNet.ps1 -Channel 11.0 -Confirm
```

`-Preleases` includes preview/RC candidates; stable remains eligible and semantic
ordering determines the highest version. `-Prerelease` and `-Prereleases` are aliases.
An explicit prerelease version also requires this switch. Changing an existing pin
to a lower semantic version requires explicit `-AllowDowngrade`.

The installer verifies the published archive SHA-512 **before extraction**, then requires
successful exact SDK and applicable runtime inventories **before promotion**. Download
timeout is controlled by `-DownloadTimeoutSeconds` (900 seconds by default). Installation
does not establish application restore/build/test, workload or IDE compatibility.

## Optionally download the container images

```powershell
$setup = ./scripts/Install-DotNet.ps1 -Channel 11.0 `
    -UpdateGlobalJson -ActivateSession -PullImages -Confirm

# Explicitly override the selected checkout's container setting.
$setup = ./scripts/Install-DotNet.ps1 -Channel 11.0 -UpdateGlobalJson `
    -PullImages -ContainerRuntime podman -Platform linux/amd64 -Confirm

# Other platforms or an official variant can be selected deliberately.
./scripts/Install-DotNet.ps1 -Channel 11.0 -PullImages `
    -ContainerRuntime docker -Platform linux/amd64,linux/arm64 `
    -ImageVariant alpine -WhatIf
```

`-PullImages` selects `sdk`, `runtime`, `aspnet` and `runtime-deps`. Container runtime
resolution follows the shared contract: explicit argument, checkout `.env`
`QUIET_CONTAINER_RUNTIME`, then discovery preferring Podman before Docker. Invalid,
empty or duplicate configured values fail. The selected daemon must already be running;
the script does not start it. WhatIf performs no runtime resolution.

Tags are `<channel>` for stable or `<channel>-preview` for preview/RC, plus any explicit
variant suffix. Floating tags do not guarantee a particular SDK patch inside an image.
A failed requested pull stops pin updates and session activation; the verified SDK
already installed remains available. There is no automatic retry or rollback.

## Update only global.json

```powershell
# Preview an exact version offline.
./scripts/Update-DotNetGlobalJson.ps1 -Version 11.0.100 -WhatIf

# Verify the exact SDK using its portable host and add its relative search path.
./scripts/Update-DotNetGlobalJson.ps1 -Version $setup.Version `
    -DotNetPath $setup.DotNetPath -SdkDirectory $setup.SdkDirectory -Confirm

# For an exact SDK already available through the system dotnet host:
./scripts/Update-DotNetGlobalJson.ps1 -Version 11.0.100 -Confirm

# Resolve the latest eligible published SDK and verify it is installed first.
./scripts/Update-DotNetGlobalJson.ps1 -Channel 11.0 -Confirm

# Explicit CI preparation: pin without a local installation check.
./scripts/Update-DotNetGlobalJson.ps1 -Version 11.0.100 -SkipInstalledCheck -Confirm
```

The default target is **this checkout's root `global.json`**. Select another file or
several exact files explicitly with `-Path` (updater) or `-GlobalJsonPath` (installer):

```powershell
$pins = @('./global.json', '../another-project/global.json')
./scripts/Update-DotNetGlobalJson.ps1 -Path $pins -Version $setup.Version `
    -DotNetPath $setup.DotNetPath -SdkDirectory $setup.SdkDirectory -WhatIf
```

Only list files you intend to migrate. Missing files require `-Create` on the standalone
updater. All documents are validated before any selected file is changed. Unrelated
JSON values, including `msbuild-sdks` and test-runner settings, survive. Existing
`sdk.rollForward` is preserved unless `-RollForward` is supplied; a new policy defaults
to `latestFeature`. `sdk.allowPrerelease` follows the supplied prerelease policy.

`-SdkDirectory` prepends a relative `sdk.paths` entry for each target and retains
existing entries plus `$host$` fallback. A **.NET 10+ host** is required for sdk.paths.
It affects SDK resolution, not application runtime discovery.

Each changed file receives a unique original-byte `global.json.bak-<UTC>-<GUID>` backup,
then an atomic per-file UTF-8/LF replacement. Duplicate properties and observed
concurrent changes are rejected. An unchanged pin is not rewritten and creates no
backup. Changed formatting and comments may be normalized. A multi-file operation
is not a transaction: a later I/O failure can leave an earlier file updated.

To restore a deliberately selected backup:

```powershell
Copy-Item -LiteralPath '<BackupPath returned by the updater>' `
    -Destination ./global.json -WhatIf
# Review the exact paths, then repeat without WhatIf.
```

## Synchronize CI SDK hashes and Debian/Alpine bases

Changing global.json does not automatically rewrite the independent CI lock. Use:

```powershell
# WhatIf makes no registry or Microsoft metadata requests.
./scripts/Update-DotNetCiLock.ps1 -IncludeDevelopmentLock -RefreshBaseImages -WhatIf

# Resolve and inspect the proposed CI/Windows lock documents without writing.
$plans = ./scripts/Update-DotNetCiLock.ps1 -IncludeDevelopmentLock `
    -RefreshBaseImages -PlanOnly

# Apply with original-byte backups.
./scripts/Update-DotNetCiLock.ps1 -IncludeDevelopmentLock -RefreshBaseImages -Confirm
```

The command refreshes SDK SHA-512 values for all four Linux RIDs and, when requested,
Windows x64/ARM64 ZIPs. It retains unrelated Git, Zig, PowerShell and other tool pins.
The separately pinned .NET 10 runtime serves Alpine PowerShell; it is not the .NET 11
SDK/runtime used by the projects. Use an explicit `-AlpineRuntimeVersion 10.0.15` when
you intend to change that host runtime and refresh its two musl hashes.

The lock's `Base` entries are **OS base images** (Debian/Alpine). The image build then
downloads the exact .NET SDK archive and verifies its SDK_SHA512 before extraction.
`-RefreshBaseImages` updates the digest of the **existing tags**; it does not choose
a different distribution version. Registry index bytes must match their reported digest
and include Linux amd64/arm64. No container client, daemon or layer download is needed.

To inspect available official tags or select a different tag deliberately:

```powershell
./scripts/Get-DotNetBaseImages.ps1 -Image debian -Name bookworm -Limit 20
./scripts/Get-DotNetBaseImages.ps1 -Image alpine -Name 3.24 -Limit 20
./scripts/Update-DotNetCiLock.ps1 -DebianTag bookworm-slim -AlpineTag 3.24 -PlanOnly
```

Tag discovery returns one bounded page, with HasMore when another page exists. Updating
an index digest keeps the selected tag's OS policy. A different Debian codename or Alpine
release can require adjusting native packages or the pinned PowerShell package: registry
availability is not build compatibility. Build and run the required CI matrix before
claiming that a new distribution version is qualified. Failed/malformed metadata leaves
the selected lock batch unchanged. Writes are atomic per file, with unique backups.

## Update RuntimeFrameworkVersion in source projects

An SDK version such as `11.0.100` and its runtime version `11.0.0` are separate pins:

```powershell
./scripts/Update-DotNetRuntimeFrameworkVersion.ps1 -WhatIf
$projects = ./scripts/Update-DotNetRuntimeFrameworkVersion.ps1 -PlanOnly

# Defaults to the runtime paired with global.json's exact published SDK.
./scripts/Update-DotNetRuntimeFrameworkVersion.ps1 -Confirm

# Or select an exact runtime version explicitly.
./scripts/Update-DotNetRuntimeFrameworkVersion.ps1 -Version 11.0.0 -Confirm
```

The default scope is net11.0 project/props files inside this checkout. Discovery prunes
generated/toolchain directories. The updater handles an explicit net11.0 property/group
condition and unconditional pins in single-target net11.0 projects. Other framework
properties and surrounding XML/comments survive. Ambiguous conditions, unconditional
multi-target pins, DTDs and links fail instead of triggering a broad text replacement.
Use `-Path`, `-Framework`, `-Preleases` and explicit `-AllowDowngrade` for deliberate
scope/version changes. Original-byte backups precede each atomic changed-file replacement.

After changing SDK/runtime/lock sources, refresh repository metadata:

```powershell
./scripts/Update-WorkspaceLock.ps1
```

Its SDK and runtime labels follow global.json and the engine's net11.0 runtime property.
SDK setup steps in CI, package preparation and the manual ReadyToRun workflow also read
global.json. Rebuild before relying on compiled payloads: changing a runtime pin does not
rebuild assemblies or runtimeconfig files, nor qualify an existing binary under the new pin.

## Use the installation in a new terminal

`-ActivateSession` changes only the current process PATH/DOTNET_ROOT; it never persists
profile or user/machine settings. In a new terminal, use the installed host explicitly,
or deliberately activate the version you selected:

```powershell
$sdkDirectory = Join-Path $PWD '.dotnet/11.0.100'
$env:DOTNET_ROOT = $sdkDirectory
$env:PATH = $sdkDirectory + [IO.Path]::PathSeparator + $env:PATH
$report = ./scripts/Test-DotNetReadiness.ps1
```

A portable .NET 11 root does not merge system .NET 8/9/10 runtimes. Continue using the
appropriate system host for applications or multi-target tests needing those runtimes.

## Functions, documentation and offline tests

```powershell
Import-Module ./scripts/lib/DotNetProvisioning.psm1
$plan = Get-DotNetGlobalJsonPlan -Path ./global.json -Version 11.0.100
$setup = Install-DotNetEnvironment -Channel 11.0 -UpdateGlobalJson -WhatIf

./scripts/Invoke-DotNetTests.ps1
./scripts/Invoke-DotNetTests.ps1 -Suite Provisioning
./scripts/Invoke-DotNetTests.ps1 -Suite Locks
# Equivalent shared launcher:
./scripts/Invoke-WorkspaceCi.ps1 -Suite DotNet -SkipBuild
```

The shared launcher opens a visible monitor and saves reports under the checkout's
external temporary report root. It prints a reopening command. SDK downloads, native
inventories and pulls are stubbed in the offline suites; actual small archives, file
hashes, pin updates and policy fixtures are exercised. Targeted mutation counts,
generated properties and malformed-input counts remain separate. Real installation,
native image pulls, interactive confirmation and unexecuted platforms remain outside
that offline evidence.

Detailed script reviews and parameter contracts: [script index](docs/scripts/README.md),
[readiness library](docs/scripts/lib/DotNetReadiness.md),
[provisioning library](docs/scripts/lib/DotNetProvisioning.md),
[CI/runtime/base-image library](docs/scripts/lib/DotNetLocks.md).
The libraries live under `scripts/lib/` as required by **RAC-PS-003**;
**RAC-NET-001–009** in [AGENTS.md](AGENTS.md) define their effect boundaries.

Official references: [Microsoft SDK/runtime installation](https://learn.microsoft.com/en-us/dotnet/core/install/windows),
[global.json](https://learn.microsoft.com/en-us/dotnet/core/tools/global-json),
[Docker pull](https://docs.docker.com/reference/cli/docker/image/pull/),
[Podman pull](https://docs.podman.io/en/latest/markdown/podman-pull.1.html).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
