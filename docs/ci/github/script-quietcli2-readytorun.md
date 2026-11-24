# quietcli2-readytorun.yml

<!-- workflow-source-sha256: 2602568811FB7477D9DF73C18C1A63451368815F656F3818FAA01FF9C54C8A6A -->

## Purpose

Informational IL-versus-ReadyToRun cold-start comparison, separate from production R2R qualification builds.

Native orchestration and test/smoke steps select checksum-pinned GA PowerShell through the local setup-powershell action. Linux guest images retain their own reviewed lock (Debian 7.7.0; accepted Alpine 7.6.10-r0 exception). The setup changes only the job PATH; it does not install a machine-wide host or enable optional Preview.

## Triggers

Manual workflow_dispatch is informational. A workflow_call from a PR with require_complete enabled requires usable A/A and A/B reports on each target. The automatic develop and publication flows do not call this benchmark.


## .NET SDK source pin

The reviewed setup-dotnet steps read the checked-out global.json through global-json-file, so the CI, publication preparation and manual ReadyToRun jobs follow the selected SDK instead of embedding an old RC string. This source review does not establish hosted execution or full matrix qualification.

## Measurement and artifacts

Builds the IL baseline and ReadyToRun candidate from the same selected revision, rather than comparing PR head with develop. A/A noise control precedes paired A/B; instrumentation is separate from timed samples. Windows and native Linux paths save source-bound cold-start reports. A green informational run does not prove a speedup. See [the report/dispatch guide](../../README-readytorun_profiling.md).

Linux comparisons wait for the Core image bundle. A PR reuses its workspace producer. A standalone dispatch calls the same producer for Core. The Linux runner verifies and loads the archive before executing the comparison. [Linux CI images](../linux-images.md)

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/quietcli2-readytorun.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_call, workflow_dispatch"]
    job_linux_images["linux-images"]
    job_readytorun["readytorun"]
    job_readytorun_linux["readytorun-linux"]
    event --> job_linux_images
    event --> job_readytorun
    job_linux_images --> job_readytorun_linux
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| linux-images | reuses ./.github/workflows/linux-images.yml |  | <code>&#36;{{ !inputs.images&#95;prepared }}</code> |  |
| readytorun | runner windows-latest |  | default success condition | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/New-ReadyToRunCandidate.ps1`](../../scripts/New-ReadyToRunCandidate.md), [`./scripts/Invoke-ColdStartGate.ps1`](../../scripts/Invoke-ColdStartGate.md), [`./scripts/Show-ColdStartReport.ps1`](../../scripts/Show-ColdStartReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |
| readytorun-linux | <code>runner &#36;{{ matrix.runner }}</code> | linux-images | <code>&#36;{{ !cancelled() &#38;&#38; (needs.linux-images.result == 'success' &#124;&#124; (inputs.images&#95;prepared &#38;&#38; needs.linux-images.result == 'skipped')) }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/New-ReadyToRunCandidate.ps1`](../../scripts/New-ReadyToRunCandidate.md), [`./scripts/Import-CiImageBundle.ps1`](../../scripts/Import-CiImageBundle.md), [`./scripts/Invoke-ContainerColdStartWorker.ps1`](../../scripts/Invoke-ContainerColdStartWorker.md), [`./scripts/Show-ColdStartReport.ps1`](../../scripts/Show-ColdStartReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |

<!-- workflow-generated:end -->

## Scripts and effects

Both checkout paths run `Initialize-CiEnvironment.ps1 -Target GitHub -ContainerRuntime docker`.
Workspace initialization validates manifests and restores pinned external resources without an
internal source-lock refresh; source-bound benchmark artifacts still identify their actual inputs.
The shared initializer deterministically prepares the ignored runtime key without loading an engine
or starting a daemon. Explicit Docker worker arguments remain overrides; no trigger or blocking
dependency is added. See [environment resolution](../environment.md).

The Linux preparation path optionally reuses resource archives through the shared cache action. Missing cache entries follow normal verified restoration; this adds no trigger, publication or qualification dependency.

Windows runs the comparison directly. Linux rows use native Ubuntu CPU runners and the prepared Docker image. The Linux worker stages the IL baseline at its grouped checkout-relative location. Each candidate is built in a fresh RUNNER_TEMP directory and offers ReadyToRun for .NET 10 and .NET 11 on the selected RID. Report uploads run after the comparison is attempted, so partial reports can be retained. A strict PR run still requires a complete A/B report. Job failures also export bounded redacted diagnostics for 14 days.

## Validation and limits

Timing comparisons use the A/A noise-floor gate before A/B. Inconclusive/slower or noisy outcomes are informational on shared runners. The workflow publishes neither Gallery packages nor PR/GHCR images, and its results never block develop delivery. Actual multi-platform benchmark execution is separate evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
