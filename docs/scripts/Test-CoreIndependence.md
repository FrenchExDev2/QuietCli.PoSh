# Test-CoreIndependence.ps1

Private SDK selection is shared with the normal test worker through WorkspaceProjects. The CI copy receives an explicit public Docker preset; local copies keep local Podman/Docker discovery. No private dotenv values are copied.

Builds only Core and Core.Tests in a fresh short temporary path, deliberately excluding the real Git product directory. Existing Git executable fixtures remain required. The copied Git test sources are inert catalogue inputs; their parser project is never built.

`./scripts/Test-CoreIndependence.ps1 -Case '*module scaffolding*'` runs the focused local regression with the visible monitor. Omit Case for the entire Core suite. GitHub requires the complete suite. WhatIf returns before copying, building or launching processes.

The script reuses an existing checkout-local pinned SDK by temporarily setting process PATH/DOTNET_ROOT, then restores them. It installs nothing and changes no profile. NuGet restore/audit retains the build's normal network and warning policies. Sources and failed copies remain in an owned short temporary directory; evidence is copied to artifacts/core-independence. No user checkout or Git history is deleted.

## Critical review and verdict

scripts/Test-CoreIndependence.ps1:1 owns the isolation regression. The short staging path avoids Windows native-library path limits. Build dependency closure and ProjectReference guards prevent accidentally compiling Git. Local filtered success establishes the generated-handler scenario only; hosted full Core evidence remains separate. No measured CI speedup is claimed.

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds Core in an owned source copy containing no real Git companion and runs its qualification.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
