# DotNetProvisioning.psm1

## Purpose

Share SDK-pin planning/updating and verified portable SDK installation. Exports
Get-DotNetGlobalJsonPlan, Update-DotNetGlobalJson and Install-DotNetEnvironment.
[Complete usage](../../../README-dotnet-and-global-dot-json.md).

## Usage and parameters

```powershell
Import-Module ./scripts/lib/DotNetProvisioning.psm1
$plan = Get-DotNetGlobalJsonPlan -Path ./global.json -Version 11.0.100
$setup = Install-DotNetEnvironment -Channel 11.0 -UpdateGlobalJson -WhatIf
```

The read-only planner accepts exact paths/version, prerelease/downgrade/create policy,
optional RollForward and SdkDirectory. The guarded updater adds installed-SDK validation
through DotNetPath and explicit SkipInstalledCheck for CI preparation. The installer adds
InstallRoot, optional images/platforms, exact pin selection and process-only activation.

## Dependencies and effects

Imports only sibling DotNetReadiness.psm1 at initialization. Native operations use the
independent process helper. Optional container resolution delegates to Common.ps1's
explicit/dotenv/discovery contract only after approval. Installation can download a verified
archive, extract/promote one version, write a receipt and optionally pull images, update
backed-up pins or activate this process. No persistent profile/PATH mutation occurs.

## Findings

- scripts/lib/DotNetProvisioning.psm1:29 validates JSON structure/duplicates and preserves
  unrelated values. :106 backs up original bytes and replaces each changed file atomically.
- :167 guards pin effects. Explicit versions can be planned entirely offline; changed
  formatting/comments are normalized, and a multi-file operation is not a transaction.
- :225 delegates runtime configuration to Common.ps1; :296 invokes resolution only after
  the installer guard. Invalid dotenv settings fail instead of falling back silently.
- :325 verifies actual SHA-512 before extraction. Exact applicable runtime inventories
  must pass before promotion. Existing incomplete versions are not repaired implicitly.
- Offline fixtures cover archive/file policies, shared resolver precedence and targeted
  mutations. Real SDK installation, native pulls and unexecuted platforms remain unqualified.

## Verdict

Keep this script dependency under scripts/lib with explicit exports. Its distinct pin and
installation responsibilities remain visible candidates for separate modules as usage grows.

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds a validated global.json update without changing any files.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 2.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
