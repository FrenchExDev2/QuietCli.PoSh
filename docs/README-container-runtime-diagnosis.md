# Container runtime and RID diagnosis

This guide starts from the repository and a working Podman engine. It explains how to prepare an image,
obtain its actual local ID, and diagnose its PowerShell runtime and native-resource selection.
No previously cached image or copied GHCR fingerprint is required.

The two operations are separate: the image builder prepares the toolchain with network access;
the diagnostic then examines that image in a private networkless container.

## 1. Prepare the host and select a target

Open PowerShell Core 7.6+ with its normal profile in the QuietCli monorepo root: the directory containing
`scripts/`, `build/` and `FrenchExDev2.QuietCli.Core.PoSh/`.

You need:

- The repository scripts, lock files and actual bundled native resources, including the SQLite libraries
  under `FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/`.
- Podman on `PATH`, connected to a running Linux backend. On Windows this is the Podman machine; the
  build script checks the backend OS and architecture, not the OS of the PowerShell client.
- Network access from the build environment to fetch base images, locked tool archives and distribution
  packages, plus disk space for image layers and build caches. A warm cache is optional.

For workstation setup, see [the installation guide](../README-development-workstation.md), especially
[Windows WSL2 and Podman](../README-development-workstation.md#windows-wsl2-and-podman).
The image build downloads its SDK inside the build stages; the diagnostic does not require importing
or compiling the QuietCli engine on the host.

Choose the intended Linux distribution family and architecture:

| Target RID | Image family | Native Podman backend architecture |
| --- | --- | --- |
| `linux-x64` | Debian / glibc | `amd64` |
| `linux-musl-x64` | Alpine / musl | `amd64` |
| `linux-arm64` | Debian / glibc | `arm64` |
| `linux-musl-arm64` | Alpine / musl | `arm64` |

Use a target matching the backend architecture for native observations. Local cross-architecture builds
can depend on separately configured emulation; they do not establish native release qualification.
The following steps use Alpine x64:

```powershell
$ErrorActionPreference = 'Stop'
$rid = 'linux-musl-x64'
```

## 2. Inspect the image recipe before building

The repository provides [`New-CiImage.ps1`](../scripts/New-CiImage.ps1). First render its plan offline:

```powershell
$plan = ./scripts/New-CiImage.ps1 -RuntimeIdentifier $rid -PlanOnly
$plan | Format-List Rid, Platform, Architecture, Base, Fingerprint
$plan.ContainerfileText
```

`-PlanOnly` reads local declarations and computes the fingerprint. It does not build, pull, contact a
registry or require a running engine.

The inputs come from:

- [`global.json`](../global.json): the SDK version.
- [`build/ci-images.lock.json`](../build/ci-images.lock.json): base-image digests and tool/package versions
  and checksums.
- [Core's image declaration](../FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1): build
  arguments, final-stage packages, environment and entry point.
- [`CiImages.ps1`](../scripts/CiImages.ps1) and [the build context](../.github/containers/): shared rendering,
  downloads and orchestration.

The generated final stage must contain a working PowerShell host, its runtime dependencies and the
native dependencies being investigated. Merely declaring `ARG POWERSHELL_PACKAGE` and
`ENTRYPOINT ["pwsh"]` does not install PowerShell.

For Alpine, the declaration includes `powershell=$POWERSHELL_PACKAGE` in the final-stage package
installation, with the argument taken from the reviewed lock. PowerShell uses the distribution runtime
through `DOTNET_ROOT=/usr/lib/dotnet`. The SDK remains first on `PATH` under `/usr/share/dotnet`, so the
same image can start stable PowerShell on CLR 10 and the pinned SDK on its own CLR 11.

Verify these entries in the rendered plan after changing the declaration. No package installation on
the Windows host is required. The builder verifies image identity and labels; successful host startup
and SDK execution are checked separately below.

Keep the actual recipe defaults when investigating a runtime-root problem: the diagnostic compares
those defaults with explicit runtime roots. Do not mask the original problem by changing unrelated
variables before collecting evidence.

## 3. Build the image from the repository inputs

Once the recipe includes the tools you intend to diagnose, build it:

```powershell
$build = ./scripts/New-CiImage.ps1 -RuntimeIdentifier $rid
$build | Format-List Image, RuntimeIdentifier, Fingerprint, Published, Dockerfile, LogPath
```

Without `-RegistryCache` or `-PublishCache`, this follows the local build path. It pulls the declared
base by digest, downloads and verifies the locked tool archives, resolves distribution packages, renders
the Containerfile and builds the final image. It then checks the resulting architecture, Linux OS,
source label and input fingerprint.

The script can be called from PowerShell on Windows when its Podman backend is Linux. PowerShell does
not need to be installed inside the Podman machine just to invoke this host-side builder.

The local image tag may begin with `ghcr.io/`; assigning that tag locally does not publish the image.
`$build.Image` is the inspected local image ID and is the value to pass to the diagnostic. Use the
returned receipt instead of copying a tag or fingerprint from another machine or an older report.

Build outputs are saved under `artifacts/ci-images/<target>-<run>/`:

- `Containerfile`: the generated recipe.
- `podman.log`: build output, including failure diagnostics.
- `image.json`: the successful receipt with the image ID, target and fingerprint.

Distribution repositories can withdraw a locked package version. A failed download or unavailable
version is a preparation failure requiring review of the recipe/locks; it is not evidence of a RID
compatibility problem. Signed package resolution also means the build is not claimed to be bit-for-bit
reproducible merely because the SDK and base image are pinned.

To reuse your own successful receipt in another PowerShell session, keep the same Podman connection:

```powershell
$receiptPath = Join-Path (Split-Path -Parent $build.LogPath) 'image.json'
# In a later session, set $receiptPath to that saved file.
$build = Get-Content -LiteralPath $receiptPath -Raw -Encoding utf8 | ConvertFrom-Json
$rid = $build.RuntimeIdentifier
```

An image in another Podman connection or another machine is not automatically available in the current
engine. Build there using the same repository inputs, or explicitly obtain the published image as
explained in [the CI image guide](ci/linux-images.md).

### Optional registry reuse

If you deliberately want to consult the published cache, use:

```powershell
$build = ./scripts/New-CiImage.ps1 -RuntimeIdentifier $rid -RegistryCache
```

This resolves the current source fingerprint and verifies a retrieved image by digest and labels.
A cache miss takes the build path; registry/network failures remain errors. This option is not required
for the from-source workflow above. Publication is a separate restricted CI operation and is not part
of these commands.

## 4. Diagnose the image you just prepared

From the same Windows PowerShell session and Podman connection:

```powershell
$run = ./scripts/Invoke-ContainerRuntimeDiagnosis.ps1 `
    -Image $build.Image `
    -ExpectedRuntimeIdentifier $rid |
    Select-Object -Last 1

$diagnosis = Get-Content -LiteralPath (Join-Path $run.RunDirectory 'diagnosis.json') `
    -Raw -Encoding utf8 | ConvertFrom-Json
$diagnosis | Format-List Decision, Findings, NextSteps
```

[`Invoke-ContainerRuntimeDiagnosis.ps1`](../scripts/Invoke-ContainerRuntimeDiagnosis.ps1) resolves the
supplied reference to an immutable image ID. It creates a uniquely labelled networkless container,
copies its explicit scripts/native assets, runs the controls, saves the reports and removes its own
container. It does not pull or repair a missing image. If image preparation failed, resolve that failure
before this step.

The local launcher opens the shared visible monitoring window and closes it after saving the terminal
report. Its first lines identify Core, the task, project directory and workspace. Rows identify each
control's container and actual reported RID; unavailable identities/counters remain unknown.
`Select-Object -Last 1` retains the returned report object after the launcher's monitor message.

Reopen the saved result with:

```powershell
./scripts/Watch-Tests.ps1 -RunDirectory $run.RunDirectory
```

The local visible-monitor launcher currently requires Windows. CI on Linux can explicitly use
`-Headless`; a headless local run does not satisfy the repository's visible-monitor rule.

For Alpine targets, the companion's combined build-and-smoke launcher performs these steps and also
verifies that `dotnet --version` still returns the pinned SDK version with unchanged image defaults:

```powershell
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-AlpineImageSmoke.ps1 -RuntimeIdentifier $rid
```

It opens a visible monitor for the build/smoke run and another for the runtime controls, retains the
prepared image, and confirms removal of its runtime/SDK probe containers. It requires a matching native
Linux Podman backend. A successful bootstrap smoke does not resolve a separate module RID selection finding.

To investigate Debian instead, repeat planning and building with `$rid = 'linux-x64'`, then pass that
new receipt to the same diagnostic. Changing only the expected RID while retaining an Alpine image
would compare different libc targets rather than build a Debian control.

## 5. Understand the controls and reports

The controls are the unchanged image default and one child execution per explicit runtime root.
Defaults for `-RuntimeRoots` are `/usr/lib/dotnet` and `/usr/share/dotnet`. A root override sets both
`DOTNET_ROOT` and the image architecture's corresponding variable for that child only. The probe records
the actual CLR and runtime directory; a variable's value is not proof that the host used it.

`-ExpectedRuntimeMajor` defaults to `10`. Use `11` only when the image intentionally supplies a Preview
host running that CLR. This parameter states an expectation; it does not install or select a new host.
`-RunDirectory` can select a new private output directory instead of the shared temporary report root.

On the corrected Alpine recipe, the unchanged default and `/usr/lib/dotnet` controls can start stable
PowerShell, while explicitly pointing it at the SDK-only `/usr/share/dotnet` root fails. That negative
control is distinct from the working default; inspect the decision and individual observations together.

[`Probe-ContainerRuntime.ps1`](../scripts/Probe-ContainerRuntime.ps1) records actual PowerShell/CLR
versions, the unmodified RID, process/OS architectures, ELF machine, OS release and mapped libc from
`/proc/self/maps`. Only allowlisted runtime-root variables are retained, not an environment dump.

It compares SQLite directories named by the reported RID and by the expected portable target. Before
loading, it verifies the staged SHA-256, ELF architecture and libc family. A successful load calls
`sqlite3_libversion`; it creates no database and imports no QuietCli engine. Incompatible or incomplete
probes are not counted as successful loads. Each phase is saved before loading native code.

The report directory contains:

| File | Evidence |
| --- | --- |
| `request.json`, `inputs.json` | Requested controls, immutable image ID, source bindings, script and asset hashes |
| Per-control JSON | Actual runtime/ABI observations and native-load results, when the guest starts |
| `commands.json` | Exit states and bounded startup/failure diagnostics, including controls with no guest report |
| `diagnosis.json` | Interpreted findings and next steps |
| `summary.json`, `status.json` | Overall collection state, controls and cleanup outcome |

Temporary storage may be cleared by the OS. Retain reports needed for later comparison. A crash or
timeout can leave cleanup unconfirmed; inspect the exact owned identity recorded in the report.
The prepared image and reusable build caches remain available after normal diagnostic cleanup.

## 6. Decide what needs changing

[`RuntimeDiagnosis.psm1`](../scripts/lib/RuntimeDiagnosis.psm1) separates these outcomes:

| Decision | Meaning and next action |
| --- | --- |
| `BootstrapAndAssetSelection` | Review both the image/launcher runtime-root configuration and raw-RID resource selection |
| `BootstrapConfiguration` | An explicit root works where the default host control fails; review the runtime-root configuration |
| `AssetSelection` | Architecture/libc evidence agrees and verified portable assets load where raw-RID assets are absent; review resource paths and RID comparisons |
| `ArchitectureMismatch` | Select an image/backend matching the requested native architecture |
| `NativeAssetsUnusable` | Inspect native-load diagnostics and required assets before attributing the failure to a RID alias |
| `HostUnavailable` | No complete successful host probe is available; inspect installation and startup diagnostics |
| `Inconclusive` | Collect the missing or inconsistent evidence before choosing a correction |
| `NoMismatchObserved` | These controls found no mismatch within their limited scope |

`State = Success` means collection and cleanup completed, not that the product passed qualification.
`Qualification` remains `DiagnosticOnly`; `WholeProductCompatibilityProven` is always false. The
recreation finding is false for identified configuration/selection faults and null when no such
conclusion is established. No reported RID is rewritten or spoofed.

Rebuild after changing image inputs such as its packages, runtime installation or environment. An input
change produces a new fingerprint. Recreating a container from unchanged image inputs does not apply
such a correction. Conversely, changes to module resource selection or CI RID comparisons must be
implemented and validated in their own source; the toolchain image contains no application checkout
that an image rebuild could silently update.

The SQLite probe does not qualify PTY bridges, tokenizers, the complete engine, other architectures or
the absence of emulation across the release matrix. Historical observations and the exact images used
for them belong in the [recorded diagnosis](audits/2026-11-09-container-runtime-diagnosis.md), not in the
image-preparation instructions as a universal prerequisite.
The [Alpine recipe verification](audits/2026-11-09-alpine-image-recipe.md) records the rebuilt image's
default-host, native-library and SDK results and the remaining resource-selection boundary.

## Reinterpret evidence or validate the policy

Reuse saved observations without starting a container:

```powershell
Import-Module ./scripts/lib/RuntimeDiagnosis.psm1
$saved = Get-Content -LiteralPath (Join-Path $run.RunDirectory 'summary.json') `
    -Raw -Encoding utf8 | ConvertFrom-Json
Get-QuietRuntimeDiagnosis -Image $saved.Image -Observations $saved.Observations `
    -ExpectedRuntimeIdentifier $rid -ExpectedRuntimeMajor 10
```

For contributors with the engine and companion fixture already built, the focused development check is:

```powershell
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -Case '*container runtime diagnosis*' -SkipBuild
```

If the fixture is not built, follow [workspace build instructions](../README-qualification.md#local-suites)
first. That test preparation is separate from building the container image. The focused suite includes
independent examples, generated architecture/RID cases, malformed report inputs, single-element-array
regressions and targeted mutants. Its filtered result is partial and does not replace release qualification.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
