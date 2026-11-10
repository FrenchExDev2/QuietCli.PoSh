# ModuleWorkstation.psm1 (lib)

## Purpose

Provides per-module (currently `Git` or `Vagrant`) tool-installation status checking and installation, as a lighter-weight sibling to the full workstation installer in `DevelopmentWorkstation.psm1`. It solves the narrower problem of "does this one module's companion native tool (e.g. a Vagrant-backed test harness) have what it needs, and if not, fetch/install just that tool into a per-user module cache" — without running the full workstation provisioning flow. It is consumed by `Install-ModuleWorkstation.ps1` (the end-user-facing script for this narrower scope).

## Usage

Exported functions (`Export-ModuleMember`, line 114): `Get-ModuleWorkstationCacheRoot`, `Get-ModuleWorkstationStatus`, `Get-ModuleWorkstationArtifact`, `Save-ModuleWorkstationDownload`, `Install-ModuleWorkstationTool`.

Key signatures:
- `Get-ModuleWorkstationCacheRoot` — no parameters; returns `%LOCALAPPDATA%\QuietCli2\modules` on Windows or `~/.local/share/QuietCli2/modules` elsewhere.
- `Get-ModuleWorkstationStatus -Name {Git|Vagrant} -Target <obj>` — read-only probe; for `Vagrant` also checks a usable `docker` client (including via a Podman socket, detected through `$env:DOCKER_HOST -match 'podman'`, line 37).
- `Get-ModuleWorkstationArtifact -Name {Git|Vagrant} -Target <obj>` — resolves a checksum-pinned download URL/hash from repo lock files; throws `UnsupportedVagrantInstallerTarget`/`VagrantInstallerPathInvalid` for unsupported platforms or suspicious filenames.
- `Save-ModuleWorkstationDownload -Name {Git|Vagrant} -Target <obj>` — downloads/verifies into the module cache, reusing `DevelopmentWorkstation.psm1`'s `Get-DevelopmentArchive` via `& $development {...}` module-scoped invocation (line 82).
- `Install-ModuleWorkstationTool -Name {Git|Vagrant} -Target <obj>` — installs Git (reusing `Install-DevelopmentGit`) or Vagrant (`msiexec` on Windows, native package manager with `sudo` elsewhere).

Example:
```powershell
Import-Module ./scripts/lib/ModuleWorkstation.psm1
$target = Get-DevelopmentHost
$status = Get-ModuleWorkstationStatus -Name Vagrant -Target $target
if ($status.State -eq 'NeedsInstallation') { Install-ModuleWorkstationTool -Name Vagrant -Target $target }
```

## Dependencies

- `Import-Module (Join-Path $PSScriptRoot 'DevelopmentWorkstation.psm1') -ErrorAction Stop` (line 2) — hard dependency; reuses `Find-DevelopmentApplication`, `Invoke-DevelopmentCommand`, `Test-DevelopmentGitVersion`, `Test-DevelopmentVagrantVersion`, `Get-DevelopmentSpecification`, `Install-DevelopmentGit`, `Get-DevelopmentArchive` (the last two via `& (Get-Module DevelopmentWorkstation) {...}` module-private-scope invocation, lines 82, 98).
- Computes `$script:ModuleWorkspaceRoot` as two levels up from `$PSScriptRoot` (line 3) — i.e. hardcodes the assumption that this file lives at `<WorkspaceRoot>/scripts/lib/ModuleWorkstation.psm1`.
- Reads `build/vagrant-installers.lock.json` directly (line 60).
- Shells out to `msiexec.exe` (Windows Vagrant install) or the detected Linux package manager with `sudo` (line 107–110).
- Filesystem: downloads into `Get-ModuleWorkstationCacheRoot()/<Name>/downloads/`.

## Side effects

- Downloads and caches installer archives/MSIs per module.
- Installs Git (via `Install-DevelopmentGit`, which can compile from source on Linux) or Vagrant (`msiexec /i ... /qn /norestart`, or the native package manager) — genuine host mutations, Vagrant via `msiexec` can require a reboot (exit code `3010` is explicitly tolerated and surfaced as a `bool` return, lines 104–105).
- No `ShouldProcess`/confirmation gate exists in this module itself — `Install-ModuleWorkstationTool` installs unconditionally once called; any confirmation must be handled entirely by the caller script (`Install-ModuleWorkstation.ps1`), not this module.

## Findings

- DESIGN: `& $development {param($artifact,$destination) Get-DevelopmentArchive $artifact.Url $artifact.SHA256 $destination} $artifact $destination` (line 82) and the equivalent at line 98 use PowerShell's module-private-scriptblock-invocation trick to call a function that is *not* exported from `DevelopmentWorkstation.psm1` (`Get-DevelopmentArchive` and `Install-DevelopmentGit` are not in that module's `Export-ModuleMember` list at its line 635 — wait, `Install-DevelopmentGit` is similarly not exported; `Get-DevelopmentArchive` is not exported either). Reaching into another module's private functions via `& (Get-Module X) {...}` is a well-known PowerShell idiom but it is fragile: it silently breaks if `DevelopmentWorkstation.psm1` ever renames or refactors those internal functions, with no compiler/static check protecting the contract. A cleaner design would export a small, deliberate internal API (or put these specific shared primitives in a third, lower-level module both import) rather than reaching past the module boundary.
- CONVENTION: `$script:ModuleWorkspaceRoot=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent` (line 3) hardcodes a two-levels-up relative layout assumption with no fallback or validation that the resulting path is actually a valid workspace root (e.g. no check that `global.json` exists there). If this file is ever relocated, the failure would surface later and confusingly (e.g. a missing lock file error) rather than at import time with a clear message.
- No input validation issue found in `Get-ModuleWorkstationArtifact`'s filename check (`if([IO.Path]::GetFileName($entry.File) -cne $entry.File){throw 'VagrantInstallerPathInvalid'}`, line 65) — this correctly guards against a path-traversal-style filename in the lock file data.
- Testability: No Pester test file referencing `ModuleWorkstation.psm1` or its functions (`Get-ModuleWorkstationStatus`, `Get-ModuleWorkstationArtifact`, etc.) was found under `FrenchExDev2.QuietCli.Core.Tests.PoSh/`. Given `DevelopmentWorkstation.Tests.ps1` exists for the sibling module, the absence of an equivalent for this one is a concrete coverage gap — e.g. `Get-ModuleWorkstationArtifact`'s platform-switch logic (line 61) and lock-file schema/version assertions (line 63) are pure, easily testable functions with no coverage at all.
- No property-based/fuzz/mutation testing evidence found for this module's parsing/validation paths (the lock-file JSON shape check at line 63, the filename check at line 65), which AGENTS.md's mandatory testing-strategy section calls for given this is validation/parsing logic.

## Verdict

The module is small, reuses existing logic reasonably, and has no obvious bugs, but it has zero dedicated test coverage (unlike its sibling `DevelopmentWorkstation.psm1`) and leans on a fragile module-private-function-reach-through pattern that should be replaced with a proper shared/exported API. Highest-priority fix: add a Pester test file covering `Get-ModuleWorkstationArtifact`'s platform/version validation, since that is pure logic with zero current coverage.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Returns the per-user module tool/cache directory without creating it.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
