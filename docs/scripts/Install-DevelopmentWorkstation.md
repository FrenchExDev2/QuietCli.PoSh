# Install-DevelopmentWorkstation.ps1

## Purpose

Provisions (or checks) a complete QuietCli development workstation for the detected host: editor
(VS Code/Insiders + extensions), containers (Podman/WSL machine), native tools (Zig, Linux native
property/fuzz/mutation compilers) and pinned profilers, while deliberately staying outside the QuietCli
engine itself (relies on the "independent CI process helper", i.e. `Invoke-CiProcess`/`Common.ps1`
machinery rather than `quiet`). It is the top-level setup script a developer runs once per machine, and
it is referenced from `README-development-workstation.md` and `README-development.md` as the documented
onboarding step; `DevelopmentWorkstation.Tests.ps1` and `Invoke-DevelopmentWorkstationSmoke.ps1` exercise
it (or its underlying module) directly. It is not invoked by any other orchestration script in `scripts/`
— it is a human-run entry point.

## Usage

Parameters (from the comment-based help and `param()` block):
- `-WorkspaceRoot` (string, optional, default `(Split-Path $PSScriptRoot -Parent)`) — QuietCli monorepo containing `global.json` and reviewed artifact locks.
- `-InstallRoot` (string, optional, default computed at runtime: `%LOCALAPPDATA%/QuietCli2/development` on Windows, `~/.local/share/QuietCli2/development` otherwise) — isolated user tool directory.
- `-Insiders` (switch, optional, default `$false`) — selects VS Code Insiders instead of Stable.
- `-PodmanMachineName` (string, optional) — explicit Windows Podman machine name.
- `-SkipEditor` (switch, optional) — excludes editor/extension installation.
- `-SkipContainers` (switch, optional) — excludes Podman/WSL preparation.
- `-SkipNativeTools` (switch, optional) — excludes Zig and native fuzz/mutation compiler packages.
- `-SkipProfilers` (switch, optional) — excludes pinned PowerShell/CLR diagnostic tools.
- `-CheckOnly` (switch, optional) — read-only probing mode, no download/write.
- `-ExtensionManifest` (string, optional, default `Join-Path $WorkspaceRoot 'build/vscode-extensions.json'`) — saved VS Code/Insiders extension inventory.

Supports `-WhatIf`/`-Confirm` (`[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]`, line 36).

Examples (from the file's own help, lines 30–34):
```powershell
./scripts/Install-DevelopmentWorkstation.ps1 -Insiders -WhatIf
$report = ./scripts/Install-DevelopmentWorkstation.ps1
if ($report.RestartRequired) { Write-Host 'Restart Windows, then rerun the same command.' }
```

## Dependencies

- Imports `lib/DevelopmentWorkstation.psm1` and `lib/EditorExtensions.psm1` (lines 50–51) — all real provisioning logic (`Get-DevelopmentHost`, `Get-DevelopmentSpecification`, `New-DevelopmentPlan`, `Get-DevelopmentInventory`, `Invoke-DevelopmentProvisioning`, `Read-EditorExtensionManifest`) lives there.
- Implicitly depends on VS Code/Insiders, Podman, WSL (Windows), and whatever native tool installers the module shells out to — none of that is visible in this file.
- Filesystem assumption: `$ExtensionManifest` file existing (when not `-SkipEditor`); `$WorkspaceRoot` containing the expected monorepo layout.

## Side effects

- Installs software (editor extensions, Podman/WSL machines, native toolchains, pinned profilers) unless `-CheckOnly` or `-WhatIf` is used — real, host-level mutation delegated entirely to `Invoke-DevelopmentProvisioning`.
- Writes to `$InstallRoot`.
- Prints follow-up instructions to the console (`Write-Host`, lines 63–64) and throws on `Failed` state (line 65).
- `$PSCmdlet.ShouldProcess` is correctly wired (lines 59–60) so `-WhatIf`/`-Confirm` suppress destructive actions performed by the module, assuming the module also consistently calls the `-ShouldApply` closure before every state-changing action (not verified here).

## Findings

- DESIGN: Like `Initialize-Profilers.ps1`, nearly all behavior is delegated to `lib/DevelopmentWorkstation.psm1` and `lib/EditorExtensions.psm1`; this script itself is a well-documented, thin CLI surface. This is good separation of concerns (SOLID) but means a reviewer cannot assess correctness of the actual installation logic from this file alone.
- Missing input validation: none of the string parameters (`-WorkspaceRoot`, `-InstallRoot`, `-PodmanMachineName`, `-ExtensionManifest`) have `[ValidateNotNullOrEmpty()]` or existence checks before being handed to the module; an empty `-PodmanMachineName ''` (as opposed to omitted) would be forwarded as an empty string rather than `$null`, and the module's "ambiguity is rejected" contract (per the `.PARAMETER PodmanMachineName` doc) may or may not treat that correctly — not verified, but worth a defensive check here.
- CONVENTION: `Write-Host` (lines 63, 64) is used for user-facing status messages, not pure data output; that's an acceptable use of `Write-Host` for human-readable progress text but is worth flagging since the "no incidental pipeline output" principle from `AGENTS.md` (written for QuietCli callbacks) could be seen to argue for more structured reporting. This is minor since `$report` is still emitted via the pipeline at line 62 before the `Write-Host` lines.
- No explicit UTF-8 I/O enforcement visible in this file (it does none itself); delegated to the module.
- Test coverage: `FrenchExDev2.QuietCli.Core.Tests.PoSh\DevelopmentWorkstation.Tests.ps1` and `Invoke-DevelopmentWorkstationSmoke.ps1` exist and reference `Install-ModuleWorkstation.ps1`/underlying module functions (confirmed via grep, lines 216, 220, 281 of the Tests file), so this script area is unusually well covered compared to most others in this set — a positive finding, not a gap.
- Line 53's host/platform branch (`if($target.Id -ceq 'windows')`) assumes `Get-DevelopmentHost` always returns an object with an `.Id` property that is either `'windows'` or implicitly treated as non-Windows for the `~/.local/share` fallback; no explicit handling for macOS is visible, though that may be intentional given this is a Windows/Linux-container-focused ecosystem per `AGENTS.md`.

## Verdict

Fit for purpose: well-documented, `ShouldProcess`-aware, and uniquely has real test coverage among the scripts in this review batch. No severe bugs found in this file; the highest-priority improvement is adding basic parameter validation (`[ValidateNotNullOrEmpty()]`) for the string parameters before they reach the provisioning module.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
