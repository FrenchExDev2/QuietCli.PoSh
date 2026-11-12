# Get-CiImageForDevelopment.ps1

## Purpose and usage

Pull-only developer helper for an existing Core CI image at the checkout's exact fingerprint. It does not build images. Main GitHub suite preparation uses New-CiSuiteImage instead.

```powershell
$image = ./scripts/Get-CiImageForDevelopment.ps1 -RuntimeIdentifier linux-x64
```

RuntimeIdentifier is one of the four Linux targets. WorkspaceRoot defaults to the checkout. Optional RegistryToken defaults to QUIETCLI_REGISTRY_TOKEN for lookup; empty permits anonymous lookup. Missing matching cache throws rather than preparing a replacement.

## Dependencies and side effects

Loads Common/CiImages, performs GHCR lookup, then explicitly invokes **Podman** pull and inspect. This helper has no ContainerRuntime option and does not use the general Docker/Podman selector for those calls. It requires a working Podman backend and registry access. It verifies local architecture, Linux OS, fingerprint/source labels before returning image ID/digest metadata. WhatIf returns before lookup/pull effects.

## Critical review and verdict

`scripts/Get-CiImageForDevelopment.ps1:43` still mentions waiting for main in its cache-miss error. Actual trusted producers use develop; see [cache-only preparation](../ci/linux-images.md#trusted-cache-only-preparation). Pulling an ARM image on x64 does not establish native ARM qualification. This source review documents the existing Podman-only/error-message limitations; it changes no image or application configuration.



<!-- script-contract:begin -->
## Execution contract

Purpose: Pulls an already-published, cache-verified CI test image by its locked digest, for use from any host OS.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
