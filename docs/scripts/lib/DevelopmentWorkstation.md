# DevelopmentWorkstation.psm1 (lib)

## Purpose

Implements the core logic for detecting, planning, and provisioning an independently bootstrappable development workstation (Windows or Linux: Debian/Ubuntu/Fedora/Alpine) — host/architecture detection, package-manager recipes, locked SDK/Git/Zig artifact resolution, checksum-verified downloads, package installation, editor installation, and Podman/WSL setup for containers. It solves "how do I get a brand-new machine to the exact pinned toolchain this repo needs, reproducibly and without touching anything that isn't explicitly owned by this installer." It is the business-logic module consumed by `Install-DevelopmentWorkstation.ps1` (the end-user-facing script) and by `ModuleWorkstation.psm1` (which reuses `Get-DevelopmentArchive`/`Install-DevelopmentGit`/`Get-DevelopmentSpecification` for module-specific tool installs like Git/Vagrant). It is a sizeable, business-critical module — essentially the entire "workstation setup" domain lives here.

## Usage

Exported functions (`Export-ModuleMember`, line 635): `Get-DevelopmentHost`, `Get-DevelopmentPackages`, `Test-DevelopmentGitVersion`, `Test-DevelopmentVagrantVersion`, `Get-DevelopmentSpecification`, `New-DevelopmentPlan`, `Get-DevelopmentInventory`, `Get-DevelopmentActions`, `Select-DevelopmentPodmanMachine`, `Invoke-DevelopmentProvisioning`, `Find-DevelopmentApplication`, `Invoke-DevelopmentCommand`.

Key signatures:
- `Get-DevelopmentHost [-OperatingSystem <string>] [-Architecture <string>] [-OsReleaseText <string>]` — detects/validates the host; throws on emulated architecture or unsupported distro/version.
- `Get-DevelopmentPackages -Target <obj> [-Component {System|Native|Containers}]` — returns package name arrays per distro.
- `Get-DevelopmentSpecification -WorkspaceRoot <string> -Target <obj>` — resolves pinned SDK/Zig/Git artifact metadata from repo lock files.
- `New-DevelopmentPlan -Target <obj> -WorkspaceRoot <string> -InstallRoot <string> -Specification <obj> [-Insiders] [-Skipped <string[]>] [-PodmanMachineName <string>] [-Extensions <string[]>] [-ExtensionManifest <string>]` — builds an immutable plan; `InstallRoot` must be an absolute path or it throws.
- `Invoke-DevelopmentProvisioning -Plan <obj> -Inventory <obj> -ShouldApply <scriptblock> [-CheckOnly]` — the actual mutating entry point, gated entirely by the `$ShouldApply` callback.

Example:
```powershell
Import-Module ./scripts/lib/DevelopmentWorkstation.psm1
$target = Get-DevelopmentHost
$spec = Get-DevelopmentSpecification -WorkspaceRoot $root -Target $target
$plan = New-DevelopmentPlan -Target $target -WorkspaceRoot $root -InstallRoot 'C:\QuietCli2\tools' -Specification $spec
$inventory = Get-DevelopmentInventory -Plan $plan
Invoke-DevelopmentProvisioning -Plan $plan -Inventory $inventory -ShouldApply { param($t,$d) $true }
```

## Dependencies

- Dot-sources `../Ci.Process.ps1` (line 3) for `Invoke-CiProcess`.
- Reads repository lock files directly: `global.json`, `build/development-workstation.lock.json`, `build/ci-images.lock.json`, `build/zig.lock.json`, `FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/ci-image.lock.json`, `.../UpstreamSources.json` (lines 120–125).
- Imports `RunToolCache.psm1` (line 269) for `Get-RunProfilerPackages`.
- Shells out to many native package managers/tools depending on platform: `dpkg-query`, `rpm`, `apk`, `sudo`, `apt-get`, `dnf`, `make`, `tar`, `winget`, `wsl.exe`, `podman`.
- Network: `Invoke-WebRequest` for SDK/Git/Zig/VS Code archive downloads (lines 356, 482) against a hardcoded allow-list of HTTPS prefixes (line 352).
- Filesystem: reads `/etc/os-release` on Linux, `pwsh.runtimeconfig.json` under `$PSHOME`, `.vscode(-insiders)/extensions/extensions.json` under `$HOME`.
- Calls `scripts/Sync-DevelopmentEditorExtensions.ps1` and `scripts/Initialize-Profilers.ps1` as child scripts (lines 496, 624).

## Side effects

- Downloads and extracts archives into `$InstallRoot` (SDK, Git, Zig, VS Code), creates directories under it.
- Installs system packages via the detected package manager, potentially via `sudo` (`Install-DevelopmentPackages`, line 363–381) — this is a genuine privilege-escalating mutation of the host OS package database.
- On Windows: can run `winget install` (VS Code, Podman) and `wsl.exe --install` (which can require/trigger a reboot — `RestartRequired` is explicitly tracked, line 536–537).
- Writes `Activate-DevelopmentEnvironment.ps1`, an explicit, non-profile-modifying activation script with `$env:PATH`/`$env:DOTNET_ROOT` assignments (`Write-DevelopmentActivation`, lines 557–588).
- Can initialize/start a Podman machine on Windows (`Initialize-DevelopmentPodman`, lines 517–555), mutating Podman's own machine registry and starting a VM-backed service.
- Compiles Git from source on Linux (`make ... install`, line 439) when the system package manager's Git is outside the supported range.

## Findings

- DESIGN: This single file mixes host detection, package-manager policy, artifact resolution, process execution, downloading, archive extraction, package installation, editor installation, and Podman/WSL orchestration — roughly eight distinct responsibilities in one ~640-line module. AGENTS.md explicitly calls for "cohesive responsibility" per module and separating "parsing, business policy, orchestration and infrastructure." This module would benefit from being split along those lines (e.g. a `WorkstationArtifacts` module for lock-file resolution/download, a `WorkstationPackages` module for OS package operations, a `WorkstationContainers` module for Podman/WSL), even though the functions inside are individually well-documented and mostly single-purpose.
- DESIGN: `Install-DevelopmentProvisioning`'s (actually named `Invoke-DevelopmentProvisioning`, lines 590–633) `try/catch` at the end (`catch{$report.State='Failed';$report.Error=$_.Exception.Message}`, line 631) discards the stack trace — only `$_.Exception.Message` is kept, not `$_.ScriptStackTrace`, unlike `Invoke-TestWorker.ps1`'s `worker-failure.json`, which captures `Stack` and `Position` too. A failed multi-step provisioning run (which can fail at any of ~7 install steps) would be much harder to diagnose from the message alone.
- CONVENTION: Line 356, `Invoke-WebRequest -Uri $Url -OutFile $partial -TimeoutSec 600` is a fully synchronous blocking call; AGENTS.md's "always prefer async methods... even in sync PowerShell use `.GetAwaiter().GetResult()`" convention is not applied here (compare to the same file's own `[IO.File]::WriteAllTextAsync(...).GetAwaiter().GetResult()` pattern used elsewhere, e.g. line 586). `Invoke-WebRequest` has no async overload in PowerShell, so this specific violation would require switching to `HttpClient` to truly comply — a reasonable candidate for a follow-up, not a trivial fix.
- Security: The downloaded-archive allow-list (line 352) is a reasonable mitigation, restricting URLs to specific official hosts/paths before any digest check — a good practice. However, `Install-DevelopmentEditor`'s VS Code download (line 482) is explicitly called out in its own comment as "deliberately not a reproducible toolchain pin" and has no digest verification at all (unlike every other artifact in this module), relying solely on the package manager's own signature verification after the fact. This is a real, if intentional and commented, trust-boundary gap worth flagging given the rest of the module's discipline.
- Testability: `DevelopmentWorkstation.Tests.ps1` exists under `FrenchExDev2.QuietCli.Core.Tests.PoSh/`, so this module does have dedicated test coverage — good. Whether that test file covers the Podman/WSL and package-installation mutation paths (which are hard to unit test without a real host) was not verified line-by-line here, but the existence of the suite is a positive finding, not a gap, for at least the pure-function paths (`Get-DevelopmentHost`, `Test-DevelopmentGitVersion`, etc.).
- No input validation issue found in `New-DevelopmentPlan`'s `PodmanMachineName` regex (line 317) or `Skipped` allow-list (line 318) — both are strict and reject unexpected values, which is good defensive design.

## Verdict

Functionally thorough and carefully defensive about checksums, architecture mismatches, and unsupported platforms, but the module's scope has grown into roughly eight responsibilities that should be split per SOLID/modular guidance, and the swallowed stack trace in `Invoke-DevelopmentProvisioning`'s catch block is the highest-priority fix since it directly hurts diagnosability of the module's riskiest multi-step operation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
