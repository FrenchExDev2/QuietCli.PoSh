# Invoke-ContainerColdStartWorker.ps1

Runtime selection follows the [shared environment contract](../ci/environment.md): explicit argument, checkout dotenv key, then Podman-first application discovery on Windows and Linux. Initialize-CiEnvironment.ps1 generates deterministic Local/GitHub presets.

## Purpose and usage

Stages a built baseline/candidate and runs Invoke-ColdStartGate.ps1 in an owned networkless container.

```powershell
./scripts/Invoke-ContainerColdStartWorker.ps1 -WorkspaceRoot <root> -RunDirectory <owned-directory> -Image <local-id> -Platform alpine -CandidateModule <manifest> -ExpectedRuntimeIdentifier linux-musl-arm64 -ContainerRuntime docker
```

WorkspaceRoot, RunDirectory, Image, Platform and CandidateModule are required. CandidateLabel defaults to readytorun; ExpectedRuntimeIdentifier verifies the guest target. ContainerRuntime accepts Docker/Podman; empty reads checkout `.env`, then discovers Podman before Docker on Windows and Linux using Get-Command. GitHub explicitly selects Docker on native Ubuntu CPU runners and calls this worker without Watch-Tests or an extra launcher PowerShell process.

## Dependencies and side effects

Requires Common.ps1, the selected existing engine, a prepared platform image and candidate. Creates an owned container with no network and no pull, copies the current scripts/binaries, polls status, retrieves reports and removes the owned container in finally. Saves state/summary and bounded crash diagnostics. The guest deadline is 900 seconds; the workflow job has an outer deadline. No image publication or test-suite dispatch.

## Critical review

- `scripts/Invoke-ContainerColdStartWorker.ps1:44` selects the engine consistently for inspect/create/copy/start/logs/cleanup. Podman is not a GitHub prerequisite.
- Architecture is checked from retained guest reports. Missing reports, failed infrastructure and unstable timing controls must not be presented as successful qualification.
- The worker is specific to the informational A/B benchmark, not an alternative functional CI. Its manual workflow has no dependency edge into develop qualification/publication.
- Actual manual multi-platform benchmark execution remains distinct from tested command adapters and the real Docker functional import smoke.

## Verdict

Shared local/GitHub cold-start transport with explicit engine selection. Measurement results never gate develop delivery.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Stages a baseline and a ReadyToRun candidate module into a private, networkless container and runs Invoke-ColdStartGate.ps1 as the guest entrypoint, then retrieves artifacts/coldstart back to the host.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
