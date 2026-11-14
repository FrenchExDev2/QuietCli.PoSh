# Initialize-CiEnvironment.ps1

Creates or updates the selected checkout's ignored `.env` through the shared safe editor.
`-Target Local` writes Podman on Windows and Linux. `-Target GitHub` writes Docker.
An explicit `-ContainerRuntime podman|docker` overrides the preset without querying installed
commands or running daemons. `-WorkspaceRoot` defaults to this checkout, independently of the caller's
working directory. The only assigned key is `QUIET_CONTAINER_RUNTIME`; other keys remain intact.

```powershell
./scripts/Initialize-CiEnvironment.ps1 -Target Local -WhatIf
./scripts/Initialize-CiEnvironment.ps1 -Target Local
./scripts/Initialize-CiEnvironment.ps1 -Target GitHub -ContainerRuntime docker -WhatIf
```

Identical inputs produce identical file contents; rerunning a prepared preset returns `Changed=false`.
`-WhatIf`/`-Confirm` use standard PowerShell semantics. The script starts no daemon, installs no tool,
loads no product engine and makes no network call. It reports only target/runtime/path/change metadata.

`ci.yml` and the manual `quietcli2-readytorun.yml` call the GitHub preset immediately after checkout.
Their explicit Docker arguments remain overrides. Container transport forwards only the effective
runtime key into a fresh staged `.env`, never the private source file or unrelated credentials.
See [the CI environment contract](../ci/environment.md) and RAC-ENV-001.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [EnvFile.psm1](lib/EnvFile.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Deterministically writes the selected Local or GitHub container runtime into the checkout's dotenv file.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
