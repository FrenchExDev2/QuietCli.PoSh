# quietcli2-readytorun.yml

<!-- workflow-source-sha256: 2BE33980CACCC651F770F475E487C69F4FA3EEF30BDD30AC8837C332B877C295 -->

## Purpose

Informational IL-versus-ReadyToRun cold-start comparison, separate from production R2R qualification builds.

Native orchestration and test/smoke steps select checksum-pinned GA PowerShell through the local setup-powershell action. Linux guest images retain their own reviewed lock (Debian 7.7.0; accepted Alpine 7.6.10-r0 exception). The setup changes only the job PATH; it does not install a machine-wide host or enable optional Preview.

## Triggers

Manual workflow_dispatch only. No push, schedule or reusable caller; no qualification/publication job depends on this workflow.


## .NET SDK source pin

The reviewed setup-dotnet steps read the checked-out global.json through global-json-file, so the CI, publication preparation and manual ReadyToRun jobs follow the selected SDK instead of embedding an old RC string. This source review does not establish hosted execution or full matrix qualification.

## Measurement and artifacts

Builds the IL baseline and ReadyToRun candidate from the same selected revision, rather than comparing PR head with develop. A/A noise control precedes paired A/B; instrumentation is separate from timed samples. Windows and native Linux paths save source-bound cold-start reports. A green informational run does not prove a speedup. See [the report/dispatch guide](../../README-readytorun_profiling.md).

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/quietcli2-readytorun.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_dispatch"]
    job_readytorun["readytorun"]
    job_readytorun_linux["readytorun-linux"]
    event --> job_readytorun
    event --> job_readytorun_linux
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| readytorun | runner windows-latest |  | default success condition | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/New-ReadyToRunCandidate.ps1`](../../scripts/New-ReadyToRunCandidate.md), [`./scripts/Invoke-ColdStartGate.ps1`](../../scripts/Invoke-ColdStartGate.md), [`./scripts/Show-ColdStartReport.ps1`](../../scripts/Show-ColdStartReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |
| readytorun-linux | runner ${{ matrix.runner }} |  | default success condition | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/New-ReadyToRunCandidate.ps1`](../../scripts/New-ReadyToRunCandidate.md), [`./scripts/New-CiImage.ps1`](../../scripts/New-CiImage.md), [`./scripts/Invoke-ContainerColdStartWorker.ps1`](../../scripts/Invoke-ContainerColdStartWorker.md), [`./scripts/Show-ColdStartReport.ps1`](../../scripts/Show-ColdStartReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |

<!-- workflow-generated:end -->

## Scripts and effects

Both checkout paths run `Initialize-CiEnvironment.ps1 -Target GitHub -ContainerRuntime docker`.
Workspace initialization validates manifests and restores pinned external resources without an
internal source-lock refresh; source-bound benchmark artifacts still identify their actual inputs.
The shared initializer deterministically prepares the ignored runtime key without loading an engine
or starting a daemon. Explicit Docker worker arguments remain overrides; no trigger or blocking
dependency is added. See [environment resolution](../environment.md).

The Linux preparation path optionally reuses resource archives through the shared cache action. Missing cache entries follow normal verified restoration; this adds no trigger, publication or qualification dependency.

Windows runs the baseline and separate net10.0 R2R candidate directly. Linux rows use native Ubuntu CPU runners, explicit Docker image preparation and Invoke-ContainerColdStartWorker directly; no desktop launcher or Watch-Tests is started. Candidate roots are fresh RUNNER_TEMP paths. Reports upload with always(); job failures also export bounded redacted diagnostics for 14 days.

## Validation and limits

Timing comparisons use the A/A noise-floor gate before A/B. Inconclusive/slower or noisy outcomes are informational on shared runners. The workflow publishes neither Gallery packages nor PR/GHCR images, and its results never block develop delivery. Actual multi-platform benchmark execution is separate evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
