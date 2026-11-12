# ci.yml

<!-- workflow-source-sha256: F95A633522EC9EF1E5172C8C19F9442F59CC15F94B66FC95E3005CB16411E781 -->

## Purpose

Shared manual/reusable qualification. Six native Windows host/mode rows and four Linux glibc/musl architecture rows run the selected product suite. Core/All keeps mandatory per-environment import, controlled Git-status and PowerShell/CLR profiling evidence. Git/Vagrant-only selections do not claim Core qualification.

run_tooling defaults true for manual/release callers; PR planning may disable it for companion-only changes. The separate tooling-ci.yml workflow must succeed when required, and qualification receipts record its outcomes plus the exact Git tree. Failures, missing profiles and cancelled jobs block qualification.

Core requires only the base toolchain image. All runs Core completely before bounded independent companion workers consume the same image. Build-Workspace compiles only the selected dependency closure and publishes the tested RID. Public packaging retains all required RIDs in its separate workflow.

Linux resolves verified final GHCR images before building parents. Missing images use Docker BuildKit mode=max intermediate caches via cache-ci-layers. Its default builder uses the containerd image store so local parent images remain visible. Cache save follows image preparation and precedes tests. PRs never publish images. Native architecture, fingerprints, parent provenance and labels remain mandatory.

## Validation and limits

Source changes preserve all ten product targets. RunProfiles functional/mutation campaigns moved out of the product matrix; profiling each environment remains independent. Local mocked/cache-boundary tests do not establish hosted cache transfer speed or ARM64 execution. See [scalable companion qualification](../scalable-companions.md).

## Triggers

Manual workflow_dispatch and reusable workflow_call. Suite, collect_performance and run_tooling are explicit inputs.

## Scripts and effects

Uses the shared scripts/ entry points, validated source lock, selected builds and private artifacts described above. Network access is limited to pinned dependency preparation, verified image caches and explicit GitHub evidence reads. No module publication occurs here.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_call, workflow_dispatch"]
    job_linux["linux"]
    job_linux_images["linux-images"]
    job_linux_matrix["linux-matrix"]
    job_linux_result["linux-result"]
    job_linux_selection["linux-selection"]
    job_linux_test_driver["linux-test-driver"]
    job_performance_results["performance-results"]
    job_qualification_gate["qualification-gate"]
    job_tooling["tooling"]
    job_windows["windows"]
    job_linux_selection --> job_linux
    job_linux_matrix --> job_linux_images
    event --> job_linux_matrix
    job_linux_selection --> job_linux_result
    job_linux --> job_linux_result
    job_linux_test_driver --> job_linux_result
    job_linux_matrix --> job_linux_selection
    job_linux_images --> job_linux_selection
    job_linux_selection --> job_linux_test_driver
    job_linux_matrix --> job_performance_results
    job_windows --> job_performance_results
    job_linux --> job_performance_results
    job_linux_test_driver --> job_performance_results
    job_linux_matrix --> job_qualification_gate
    job_windows --> job_qualification_gate
    job_linux_result --> job_qualification_gate
    job_performance_results --> job_qualification_gate
    job_tooling --> job_qualification_gate
    event --> job_tooling
    job_linux_matrix --> job_windows
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| linux | runner ${{ matrix.runner }}; container ${{ matrix.image }} | linux-selection | ${{ !cancelled() && needs.linux-selection.result == 'success' && needs.linux-selection.outputs.has_container == 'true' }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| linux-images | runner ${{ matrix.runner }} | linux-matrix | github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' && (github.event_name == 'push' &#124;&#124; github.event_name == 'workflow_dispatch') | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/New-CiSuiteImage.ps1 |
| linux-matrix | runner ubuntu-latest |  | default success condition | ./scripts/Initialize-CiCompanions.ps1, ./scripts/Initialize-CiEnvironment.ps1 |
| linux-result | runner ubuntu-latest | linux-selection, linux, linux-test-driver | always() | ./scripts/GitHubCi.ps1, ./scripts/Initialize-CiEnvironment.ps1 |
| linux-selection | runner ubuntu-latest | linux-matrix, linux-images | ${{ always() && !cancelled() && needs.linux-matrix.result == 'success' && (needs.linux-images.result == 'success' &#124;&#124; needs.linux-images.result == 'skipped') }} | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Select-GitHubCiMatrix.ps1 |
| linux-test-driver | runner ${{ matrix.runner }} | linux-selection | ${{ !cancelled() && needs.linux-selection.result == 'success' && needs.linux-selection.outputs.has_docker_container_runtime == 'true' }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CiSuiteImage.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| performance-results | runner ubuntu-latest | linux-matrix, windows, linux, linux-test-driver | ${{ always() && inputs.collect_performance && needs.linux-matrix.outputs.has_core == 'true' }} | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| qualification-gate | runner ubuntu-latest | linux-matrix, windows, linux-result, performance-results, tooling | ${{ always() }} | ./scripts/Assert-QualificationGate.ps1, ./scripts/Initialize-CiEnvironment.ps1 |
| tooling | reuses ./.github/workflows/tooling-ci.yml |  | inputs.run_tooling |  |
| windows | runner ${{ matrix.image }} | linux-matrix | default success condition | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiCompanions.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |

<!-- workflow-generated:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
