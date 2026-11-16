# ci.yml

<!-- workflow-source-sha256: 9358FF7C965AD471945C008E3F25A67C6EFF387EFC189CBE9AF7119DD5797BDF -->

## Purpose

Shared product qualification engine. The same workflow accepts the generated companion profiles and explicit affected CSharp project paths from the PR matrix. Full mode retains locked native Windows/Linux qualification, explicit optional Preview, Core performance evidence, source-bound distributions and the exact-revision gate. Smoke/build modes route to workspace-component-ci.yml. Profile validation runs before expensive work. Build caches are namespaced by target/scope and verified before reuse. Artifacts are suite-scoped to avoid matrix collisions; All retains the legacy quietcli2-qualification-gate artifact name consumed by publication.

## Triggers

Reusable workflow_call and explicit workflow_dispatch.

## Scripts and effects

Profile validation initializes the checkout's deterministic GitHub environment immediately after checkout, like execution jobs; it performs no product build.

Uses profile validation, source-bound build preparation, explicit selected qualification/smoke entry points and private artifacts. The PR planner publishes plan.json and impact.md; build_projects_json passes affected CSharp paths to Build-Workspace. GitHub may prepare pinned SDK/PowerShell resources and verified image caches. No module publication or repository setting change is performed here.

## Validation and limits

The stable automatic gate requires planning, source checks, generated-layout tests and every selected job. Skipped scopes are untested, not passed. A smoke/build result is not full product or publication qualification. Full native product runs retain their declared host/RID matrix, profiling policy and explicit TTY/Preview exclusions. Cache hits require source/payload/target verification; partial restores rebuild stale distributions.

The Linux image producer serializes per suite and RID (`quietcli2-suite-image-<suite>-<rid>`). GitHub keeps only one pending job per concurrency group, so a group shared by the parallel Core/Git/Vagrant calls from companions-ci.yml cancelled the waiting suites' producers. Concurrent publication of a shared base remains safe because GHCR cache entries are content-addressed by fingerprint.

Local WorkspaceLayout and CompanionSmoke reports exercise the selection and actual integration paths. Hosted matrix results must be inspected for the delivered revision. Authored workflow-source-sha256 receipts are reviewed separately from generated YAML and job graphs.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_call, workflow_dispatch"]
    job_component_check["component-check"]
    job_linux["linux"]
    job_linux_images["linux-images"]
    job_linux_matrix["linux-matrix"]
    job_linux_result["linux-result"]
    job_linux_selection["linux-selection"]
    job_linux_test_driver["linux-test-driver"]
    job_performance_results["performance-results"]
    job_qualification_gate["qualification-gate"]
    job_tooling["tooling"]
    job_validate["validate"]
    job_windows["windows"]
    job_validate --> job_component_check
    job_linux_selection --> job_linux
    job_linux_matrix --> job_linux_images
    job_validate --> job_linux_matrix
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
    event --> job_validate
    job_linux_matrix --> job_windows
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| component-check | reuses ./.github/workflows/workspace-component-ci.yml | validate | inputs.qualification_mode == 'smoke' &#124;&#124; inputs.qualification_mode == 'build' |  |
| linux | runner ${{ matrix.runner }}; container ${{ matrix.image }} | linux-selection | ${{ !cancelled() && needs.linux-selection.result == 'success' && needs.linux-selection.outputs.has_container == 'true' }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Get-CompanionBuildKey.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| linux-images | runner ${{ matrix.runner }} | linux-matrix | github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' && (github.event_name == 'push' &#124;&#124; github.event_name == 'workflow_dispatch') | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/New-CiSuiteImage.ps1 |
| linux-matrix | runner ubuntu-latest | validate | inputs.qualification_mode == '' &#124;&#124; inputs.qualification_mode == 'full' | ./scripts/Initialize-CiCompanions.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/lib/GitHubCi.psm1, ./scripts/Select-PowerShellCiMatrix.ps1 |
| linux-result | runner ubuntu-latest | linux-selection, linux, linux-test-driver | ${{ always() && !inputs.images_only && (inputs.qualification_mode == '' &#124;&#124; inputs.qualification_mode == 'full') }} | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/lib/GitHubCi.psm1 |
| linux-selection | runner ubuntu-latest | linux-matrix, linux-images | ${{ always() && !cancelled() && !inputs.images_only && needs.linux-matrix.result == 'success' && (needs.linux-images.result == 'success' &#124;&#124; needs.linux-images.result == 'skipped') }} | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Select-GitHubCiMatrix.ps1 |
| linux-test-driver | runner ${{ matrix.runner }} | linux-selection | ${{ !cancelled() && needs.linux-selection.result == 'success' && needs.linux-selection.outputs.has_docker_container_runtime == 'true' }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Get-CompanionBuildKey.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CiSuiteImage.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| performance-results | runner ubuntu-latest | linux-matrix, windows, linux, linux-test-driver | ${{ always() && !inputs.images_only && (inputs.qualification_mode == '' &#124;&#124; inputs.qualification_mode == 'full') && inputs.collect_performance && needs.linux-matrix.outputs.has_core == 'true' }} | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| qualification-gate | runner ubuntu-latest | linux-matrix, windows, linux-result, performance-results, tooling | ${{ always() && !inputs.images_only && (inputs.qualification_mode == '' &#124;&#124; inputs.qualification_mode == 'full') }} | ./scripts/Assert-QualificationGate.ps1, ./scripts/Initialize-CiEnvironment.ps1 |
| tooling | reuses ./.github/workflows/tooling-ci.yml |  | inputs.run_tooling && !inputs.images_only && (inputs.qualification_mode == '' &#124;&#124; inputs.qualification_mode == 'full') |  |
| validate | runner ubuntu-latest |  | default success condition | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Invoke-ComponentCheck.ps1 |
| windows | runner ${{ matrix.image }} | linux-matrix | ${{ !inputs.images_only && (inputs.qualification_mode == '' &#124;&#124; inputs.qualification_mode == 'full') }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Get-CompanionBuildKey.ps1, ./scripts/Initialize-CiCompanions.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |

<!-- workflow-generated:end -->

See [companion layout and selective CI](../../README-companion-layout-and-ci.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
