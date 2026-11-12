# quietcli2-readytorun.yml

<!-- workflow-source-sha256: 3E7050C563E835372898CF39CD8F53AA3F58ACB23B5B15684FC9DFBED466638A -->

## Purpose

Informational IL-versus-ReadyToRun cold-start comparison, separate from production R2R qualification builds.

## Triggers

Manual workflow_dispatch only. No push, schedule or reusable caller; no qualification/publication job depends on this workflow.


## .NET SDK source pin

The reviewed setup-dotnet steps read the checked-out global.json through global-json-file, so the CI, publication preparation and manual ReadyToRun jobs follow the selected SDK instead of embedding an old RC string. This source review does not establish hosted execution or full matrix qualification.

## Measurement and artifacts

Builds the IL baseline and ReadyToRun candidate from the same selected revision, rather than comparing PR head with develop. A/A noise control precedes paired A/B; instrumentation is separate from timed samples. Windows and native Linux paths save source-bound cold-start reports. A green informational run does not prove a speedup. See [the report/dispatch guide](../../README-readytorun_profiling.md).

<!-- workflow-generated:begin -->
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
| readytorun | runner windows-latest |  | default success condition | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Invoke-ColdStartGate.ps1, ./scripts/New-ReadyToRunCandidate.ps1, ./scripts/Show-ColdStartReport.ps1 |
| readytorun-linux | runner ${{ matrix.runner }} |  | default success condition | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-ContainerColdStartWorker.ps1, ./scripts/New-CiImage.ps1, ./scripts/New-ReadyToRunCandidate.ps1, ./scripts/Show-ColdStartReport.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

Both checkout paths run `Initialize-CiEnvironment.ps1 -Target GitHub -ContainerRuntime docker`.
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
