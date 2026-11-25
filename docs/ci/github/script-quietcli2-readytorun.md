# quietcli2-readytorun.yml

<!-- workflow-source-sha256: 4D26349E5B5758F4AB10870A550B2502C13A04363961E1BD76254146C6A7D481 -->

## Purpose

Informational IL-versus-ReadyToRun cold-start comparison, separate from production R2R qualification builds.

Native orchestration and test/smoke steps select checksum-pinned GA PowerShell through the local setup-powershell action. Linux guest images retain their own reviewed lock (Debian 7.7.0; accepted Alpine 7.6.10-r0 exception). The setup changes only the job PATH; it does not install a machine-wide host or enable optional Preview.

## Triggers

Manual workflow dispatch is informational and offers the optional `aa_control` switch. A PR workflow call with `require_complete` requires a usable A/B report on each target. The benchmark is outside the automatic develop and publication flows.


## .NET SDK source pin

The reviewed setup-dotnet steps read the checked-out global.json through global-json-file, so the CI, publication preparation and manual ReadyToRun jobs follow the selected SDK instead of embedding an old RC string. This source review does not establish hosted execution or full matrix qualification.

## Measurement and artifacts

Windows and Linux restore pinned Core resources before building the IL baseline and copying it into the ReadyToRun candidate. Both variants carry the native runtime files that Core verifies on engine startup. Windows and native Linux run paired A/B directly by default and save source-bound reports. Instrumentation runs outside timed samples. [Report and dispatch guide](../../README-readytorun_profiling.md)

Linux comparisons wait for the Core image handoff. A PR reuses its workspace producer. A standalone dispatch calls the same producer for Core. The Linux runner verifies the archive or registry image before executing the comparison. [Linux CI images](../linux-images.md)

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
| readytorun | runner windows-latest |  | default success condition | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/New-ReadyToRunCandidate.ps1`](../../scripts/New-ReadyToRunCandidate.md), [`./scripts/Invoke-ColdStartGate.ps1`](../../scripts/Invoke-ColdStartGate.md), [`./scripts/Show-ColdStartReport.ps1`](../../scripts/Show-ColdStartReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |
| readytorun-linux | <code>runner &#36;{{ matrix.runner }}</code> | linux-images | <code>&#36;{{ !cancelled() &#38;&#38; (needs.linux-images.result == 'success' &#124;&#124; (inputs.images&#95;prepared &#38;&#38; needs.linux-images.result == 'skipped')) }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/New-ReadyToRunCandidate.ps1`](../../scripts/New-ReadyToRunCandidate.md), [`./scripts/Invoke-ContainerColdStartWorker.ps1`](../../scripts/Invoke-ContainerColdStartWorker.md), [`./scripts/Show-ColdStartReport.ps1`](../../scripts/Show-ColdStartReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |

<!-- workflow-generated:end -->

## Scripts and effects

Both checkout paths run `Initialize-CiEnvironment.ps1 -Target GitHub -ContainerRuntime docker`.
Workspace initialization validates manifests and restores pinned external resources without an
internal source-lock refresh; source-bound benchmark artifacts still identify their actual inputs.
The shared initializer deterministically prepares the ignored runtime key without loading an engine
or starting a daemon. Explicit Docker worker arguments remain overrides; no trigger or blocking
dependency is added. See [environment resolution](../environment.md).

Both preparation paths can reuse resource archives through the shared cache action. Initialization extracts and verifies the pinned files even when the archive cache hits.

Windows runs the comparison directly. Linux rows use native Ubuntu CPU runners and the prepared Docker image. The Linux worker stages the IL baseline at its grouped checkout-relative location. Each candidate is built in a fresh RUNNER_TEMP directory and offers ReadyToRun for .NET 10 and .NET 11 on the selected RID. Report uploads run after the comparison is attempted, so partial reports can be retained. A strict PR run still requires a complete A/B report. Job failures also export bounded redacted diagnostics for 14 days.

## Validation and limits

Both build variants must complete the requested measurements for strict PR evidence. Inconclusive, faster and slower A/B verdicts are accepted. Failed executions and missing comparisons fail the strict PR check. Optional manual A/A calibration applies the existing control rule before the comparison.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
