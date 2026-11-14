# Invoke-ContainerCi.ps1

## Purpose and usage

Local supervisor for tests in an already prepared Linux image, using a background transport worker and the visible read-only monitor. It does not pull an image, install the host toolchain or start a daemon. GitHub fallback uses Invoke-GitHubCi/Invoke-ContainerWorker directly.

```powershell
# The image must already exist in the selected local engine.
./scripts/Invoke-ContainerCi.ps1 -Suite Core -Image $verifiedImageId -Platform debian -ExpectedRuntimeIdentifier linux-x64
```

Image is mandatory; Platform is debian/alpine. The image needs the pinned PowerShell, .NET SDK/runtime and declared suite tools. ExpectedRuntimeIdentifier prevents another CPU/libc environment from being accepted as the requested target. Suite is dynamically resolved through WorkspaceProjects, default All.

ContainerRuntime selects docker/podman explicitly; otherwise the checkout `.env` precedes Podman-first application discovery. `TimeoutSeconds` defaults to 900 (range 1–7200) and covers transport/staging/cleanup. `SkipTty` excludes terminal tests and is incompatible with Suite Mutation. `Case` selects Core cases only and keeps evidence partial. `Profiler` supports Core/All/Integration with a separate instrumented pass and optional explicit pinned profiler paths.

## Dependencies and side effects

Loads Common and delegates to Invoke-ContainerWorker. May prepare missing profiler tools when requested. Creates a run under the external containers report root, starts the hidden worker and visible Windows monitor, waits for a saved terminal summary and propagates failure with the run path. Headless is reserved for CI. A non-Windows invocation without Headless is rejected before starting the worker. WhatIf returns before profiler preparation, report creation or process effects.

The transport verifies the local image, stages source/binaries/restored packages and runs an owned networkless guest without implicit pull. It retains guest status, exit and host/guest identities, and cleans up owned containers/staging. Sources, configuration and reports remain distinct from baked toolchain images.

## Critical review and verdict

`scripts/Invoke-ContainerCi.ps1:33` is supervision around shared transport, not a second test implementation. Exact guest identity and successful terminal reports are necessary; image presence or a successful container start is insufficient. Local results establish only the selected guest/runtime/suite, never the complete GitHub matrix. See [execution boundaries](../ci/execution-model.md).



<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md), [WorkspaceProjects.psm1](lib/WorkspaceProjects.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Runs existing prepared images; no pull, host installation or implicit dependency download.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
