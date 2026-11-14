# New-CiModuleImage.ps1

## Purpose and usage

Builds a declared companion overlay over a verified Core or explicit preceding image. Suite composition normally uses [New-CiSuiteImage](New-CiSuiteImage.md).

```powershell
./scripts/New-CiModuleImage.ps1 -Module Git -RuntimeIdentifier linux-x64 -PlanOnly
```

The module owns `ci/Get-CiImageArguments.ps1`, recipe fragments, arguments and locks. CiImages renders the Containerfile; its input and parent fingerprints define the final identity. `Module` is the short declared name, such as Git; RuntimeIdentifier selects a native Linux target.

Without ParentPlan, registry reuse checks the final overlay before building Core. On a miss, the wrapper resolves Core, tags the verified parent under a fingerprint-bound local reference, then builds the overlay. With ParentPlan, a real build requires ParentImage and verifies its RID/fingerprint/identity. It never substitutes an unrelated parent.

## Dependencies and side effects

Loads Common and CiImages and invokes the selected module's image contract. PlanOnly resolves local metadata without native/network/credential access. WhatIf returns before effectful preparation. RegistryCache, PublishCache and ContainerRuntime use the shared [environment](../ci/environment.md) and [image policies](../ci/linux-images.md).

Real preparation may pull/build/tag images and write receipts. The temporary credential survives the base call only in the owning process so the overlay can authenticate; it is redacted and cleaned up by the shared builder. Direct overlay preparation does not request base publication; suite preparation owns missing base/overlay publication in its producer job. No Gallery package is produced.

## Critical review and verdict

`scripts/New-CiModuleImage.ps1:38` validates explicit parents, and `:48` checks the final cache before base preparation. Shared tests cover parent provenance, credential handoff, default FROM references and no-build cache misses. Cross-runner/cache behavior still requires hosted evidence.



<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [CiImages.psm1](lib/CiImages.md), [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds a Core-consumer module's own derived Podman image, from the module's own Containerfile and locks.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
