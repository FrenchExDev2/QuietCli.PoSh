# ci.yml

<!-- workflow-source-sha256: 57663F310EAA0407922EAE64A4E236BAADBDA97451BEEC8F33D0825A2F7B8711 -->

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

`images_prepared` (workflow_call, default false) skips that per-suite producer. companions-ci.yml passes it as true when its `images` job warmed every selected chain once per RID; linux-selection already accepts a skipped producer and verifies the final image identity itself. Standalone calls and dispatches keep their own producer.

Local WorkspaceLayout and CompanionSmoke reports exercise the selection and actual integration paths. Hosted matrix results must be inspected for the delivered revision. Authored workflow-source-sha256 receipts are reviewed separately from generated YAML and job graphs.

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/ci.yml)

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
| component-check | reuses ./.github/workflows/workspace-component-ci.yml | validate | <code>inputs.qualification&#95;mode == 'smoke' &#124;&#124; inputs.qualification&#95;mode == 'build'</code> |  |
| linux | <code>runner &#36;{{ matrix.runner }}; container &#36;{{ matrix.image }}</code> | linux-selection | <code>&#36;{{ !cancelled() &#38;&#38; needs.linux-selection.result == 'success' &#38;&#38; needs.linux-selection.outputs.has&#95;container == 'true' }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Get-CompanionBuildKey.ps1`](../../scripts/Get-CompanionBuildKey.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/Initialize-Profilers.ps1`](../../scripts/Initialize-Profilers.md), [`./scripts/Invoke-GitHubCi.ps1`](../../scripts/Invoke-GitHubCi.md), [`./scripts/New-CoreEvidenceBundle.ps1`](../../scripts/New-CoreEvidenceBundle.md), [`./scripts/New-CorePerformanceReport.ps1`](../../scripts/New-CorePerformanceReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |
| linux-images | <code>runner &#36;{{ matrix.runner }}</code> | linux-matrix | <code>github.repository == 'FrenchExDev2/QuietCli.PoSh' &#38;&#38; github.ref == 'refs/heads/develop' &#38;&#38; (github.event&#95;name == 'push' &#124;&#124; github.event&#95;name == 'workflow&#95;dispatch') &#38;&#38; !inputs.images&#95;prepared</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/New-CiSuiteImage.ps1`](../../scripts/New-CiSuiteImage.md) |
| linux-matrix | runner ubuntu-latest | validate | <code>inputs.qualification&#95;mode == '' &#124;&#124; inputs.qualification&#95;mode == 'full'</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Select-PowerShellCiMatrix.ps1`](../../scripts/Select-PowerShellCiMatrix.md), [`./scripts/lib/GitHubCi.psm1`](../../scripts/lib/GitHubCi.md), [`./scripts/Initialize-CiCompanions.ps1`](../../scripts/Initialize-CiCompanions.md) |
| linux-result | runner ubuntu-latest | linux-selection, linux, linux-test-driver | <code>&#36;{{ always() &#38;&#38; !inputs.images&#95;only &#38;&#38; (inputs.qualification&#95;mode == '' &#124;&#124; inputs.qualification&#95;mode == 'full') }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/lib/GitHubCi.psm1`](../../scripts/lib/GitHubCi.md) |
| linux-selection | runner ubuntu-latest | linux-matrix, linux-images | <code>&#36;{{ always() &#38;&#38; !cancelled() &#38;&#38; !inputs.images&#95;only &#38;&#38; needs.linux-matrix.result == 'success' &#38;&#38; (needs.linux-images.result == 'success' &#124;&#124; needs.linux-images.result == 'skipped') }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Select-GitHubCiMatrix.ps1`](../../scripts/Select-GitHubCiMatrix.md) |
| linux-test-driver | <code>runner &#36;{{ matrix.runner }}</code> | linux-selection | <code>&#36;{{ !cancelled() &#38;&#38; needs.linux-selection.result == 'success' &#38;&#38; needs.linux-selection.outputs.has&#95;docker&#95;container&#95;runtime == 'true' }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Get-CompanionBuildKey.ps1`](../../scripts/Get-CompanionBuildKey.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/New-CiSuiteImage.ps1`](../../scripts/New-CiSuiteImage.md), [`./scripts/Initialize-Profilers.ps1`](../../scripts/Initialize-Profilers.md), [`./scripts/Invoke-GitHubCi.ps1`](../../scripts/Invoke-GitHubCi.md), [`./scripts/New-CoreEvidenceBundle.ps1`](../../scripts/New-CoreEvidenceBundle.md), [`./scripts/New-CorePerformanceReport.ps1`](../../scripts/New-CorePerformanceReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |
| performance-results | runner ubuntu-latest | linux-matrix, windows, linux, linux-test-driver | <code>&#36;{{ always() &#38;&#38; !inputs.images&#95;only &#38;&#38; (inputs.qualification&#95;mode == '' &#124;&#124; inputs.qualification&#95;mode == 'full') &#38;&#38; inputs.collect&#95;performance &#38;&#38; needs.linux-matrix.outputs.has&#95;core == 'true' }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/New-CorePerformanceReport.ps1`](../../scripts/New-CorePerformanceReport.md) |
| qualification-gate | runner ubuntu-latest | linux-matrix, windows, linux-result, performance-results, tooling | <code>&#36;{{ always() &#38;&#38; !inputs.images&#95;only &#38;&#38; (inputs.qualification&#95;mode == '' &#124;&#124; inputs.qualification&#95;mode == 'full') }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Assert-QualificationGate.ps1`](../../scripts/Assert-QualificationGate.md) |
| tooling | reuses ./.github/workflows/tooling-ci.yml |  | <code>inputs.run&#95;tooling &#38;&#38; !inputs.images&#95;only &#38;&#38; (inputs.qualification&#95;mode == '' &#124;&#124; inputs.qualification&#95;mode == 'full')</code> |  |
| validate | runner ubuntu-latest |  | default success condition | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Invoke-ComponentCheck.ps1`](../../scripts/Invoke-ComponentCheck.md) |
| windows | <code>runner &#36;{{ matrix.image }}</code> | linux-matrix | <code>&#36;{{ !inputs.images&#95;only &#38;&#38; (inputs.qualification&#95;mode == '' &#124;&#124; inputs.qualification&#95;mode == 'full') }}</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Initialize-PowerShellHost.ps1`](../../scripts/Initialize-PowerShellHost.md), [`./scripts/Get-CompanionBuildKey.ps1`](../../scripts/Get-CompanionBuildKey.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/Initialize-CiCompanions.ps1`](../../scripts/Initialize-CiCompanions.md), [`./scripts/Initialize-Profilers.ps1`](../../scripts/Initialize-Profilers.md), [`./scripts/Invoke-GitHubCi.ps1`](../../scripts/Invoke-GitHubCi.md), [`./scripts/New-CoreEvidenceBundle.ps1`](../../scripts/New-CoreEvidenceBundle.md), [`./scripts/New-CorePerformanceReport.ps1`](../../scripts/New-CorePerformanceReport.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |

<!-- workflow-generated:end -->

See [companion layout and selective CI](../../README-companion-layout-and-ci.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
