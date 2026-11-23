# Install-ModuleWorkstation.ps1

<!-- script-source:begin -->
Source file: [`Install-ModuleWorkstation.ps1`](../../scripts/Install-ModuleWorkstation.ps1)
<!-- script-source:end -->

## Purpose

Runs the workstation installers owned by the selected QuietCli companions. The `workstation: true` entries in `build/companions.yaml` supply the allowed names, and the script calls their installers in the order requested.

## Usage

Select one or more names with `-Modules`. `-CheckOnly` probes readiness. `-Download` fetches the installers. Choose at most one of these two switches. Each companion installer receives the preview setting.

```powershell
./scripts/Install-ModuleWorkstation.ps1 -Modules Git,Vagrant -CheckOnly
```

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs the workstation installer for each selected QuietCli companion.

Boundary: **Executable**. Preview API: **DelegatedShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/Install-ModuleWorkstation.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
