# New-CiImage.ps1

## Purpose and usage

Prepares Core's native Linux toolchain image for one RID. Main workflows normally enter through [New-CiSuiteImage](New-CiSuiteImage.md), which checks the final suite cache before preparing any parent.

```powershell
./scripts/New-CiImage.ps1 -RuntimeIdentifier linux-arm64 -PlanOnly
./scripts/New-CiImage.ps1 -RuntimeIdentifier linux-x64 -RegistryCache -ContainerRuntime docker -WhatIf
```

`RuntimeIdentifier` accepts the four Linux x64/ARM64 glibc/musl targets. `WorkspaceRoot` selects the checkout. `PlanOnly` returns the fingerprint/recipe plan without native execution, registry access or credential reads. WhatIf stops before engine discovery and build/pull effects; local recipe planning can still read source files.

`RegistryCache` resolves an immutable GHCR digest and verifies architecture, Linux OS, source and fingerprint. A miss permits a native build. `PublishCache` is an additional request enforced in CiImages: only upstream develop push/manual contexts may publish, never PRs. Runtime selection is explicit ContainerRuntime, checkout `.env`, then Podman before Docker. GitHub explicitly selects Docker.

## Dependencies and side effects

Loads Common and CiImages; the Core `ci/Get-CiImageArguments.ps1` contract supplies recipe inputs and pins. Preparation can pull/build/tag/push an image and write image/recipe/log receipts. Temporary registry credentials are scrubbed and removed. No workspace source, module package or Gallery publication is part of this operation.

## Critical review and verdict

`scripts/New-CiImage.ps1:18` delegates effect and publication policy to the shared image builder. The restriction is enforced there, not merely in YAML. Source-bound plans, label verification and adapter/preview regressions cover the local contract. Native ARM execution and hosted cache performance remain separate evidence. See [Linux image policy](../ci/linux-images.md).



<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [CiImages.psm1](lib/CiImages.md), [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Builds native multi-stage test images; optional GHCR cache uses a content fingerprint, then pulls by digest.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
