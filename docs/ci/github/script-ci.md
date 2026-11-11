# ci.yml

<!-- workflow-source-sha256: 54C99E151E44B1BFF4B8ADA4E7D42F55909F25C974603ADC2C3D6729C2D78328 -->

## Purpose

Shared qualification for the selected Core, Git or All source scope across six Windows host/mode combinations and four native Linux RID targets.

## Triggers

Reusable workflow_call accepts suite and collect_performance (boolean, default false); workflow_dispatch uses All and exposes the same optional collect_performance checkbox. Core/Git callers provide path-filtered PR/develop events without requesting performance collection. Image publication is restricted in job conditions to upstream develop pushes/manual dispatch; PR images are never published.


## .NET SDK source pin

The reviewed setup-dotnet steps read the checked-out global.json through global-json-file, so the CI, publication preparation and manual ReadyToRun jobs follow the selected SDK instead of embedding an old RC string. This source review does not establish hosted execution or full matrix qualification.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_call, workflow_dispatch"]
    job_linux["linux"]
    job_linux_git_images["linux-git-images"]
    job_linux_images["linux-images"]
    job_linux_matrix["linux-matrix"]
    job_linux_result["linux-result"]
    job_linux_selection["linux-selection"]
    job_linux_test_driver["linux-test-driver"]
    job_performance_results["performance-results"]
    job_qualification_gate["qualification-gate"]
    job_windows["windows"]
    job_linux_selection --> job_linux
    job_linux_matrix --> job_linux_git_images
    job_linux_images --> job_linux_git_images
    job_linux_matrix --> job_linux_images
    event --> job_linux_matrix
    job_linux_selection --> job_linux_result
    job_linux --> job_linux_result
    job_linux_test_driver --> job_linux_result
    job_linux_images --> job_linux_selection
    job_linux_git_images --> job_linux_selection
    job_linux_selection --> job_linux_test_driver
    job_windows --> job_performance_results
    job_linux --> job_performance_results
    job_linux_test_driver --> job_performance_results
    job_windows --> job_qualification_gate
    job_linux_result --> job_qualification_gate
    event --> job_windows
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| linux | runner ${{ matrix.runner }}; container ${{ matrix.image }} | linux-selection | ${{ !cancelled() && needs.linux-selection.result == 'success' && needs.linux-selection.outputs.has_container == 'true' }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| linux-git-images | runner ${{ matrix.runner }} | linux-matrix, linux-images | github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' && (github.event_name == 'push' &#124;&#124; github.event_name == 'workflow_dispatch') && ((inputs.suite &#124;&#124; 'All') == 'Git' &#124;&#124; (inputs.suite &#124;&#124; 'All') == 'All') | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/New-CiModuleImage.ps1 |
| linux-images | runner ${{ matrix.runner }} | linux-matrix | github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' && (github.event_name == 'push' &#124;&#124; github.event_name == 'workflow_dispatch') | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/New-CiImage.ps1 |
| linux-matrix | runner ubuntu-latest |  | default success condition |  |
| linux-result | runner ubuntu-latest | linux-selection, linux, linux-test-driver | always() | ./scripts/GitHubCi.ps1, ./scripts/Initialize-CiEnvironment.ps1 |
| linux-selection | runner ubuntu-latest | linux-images, linux-git-images | ${{ always() && !cancelled() && (needs.linux-images.result == 'success' &#124;&#124; needs.linux-images.result == 'skipped') && (needs.linux-git-images.result == 'success' &#124;&#124; needs.linux-git-images.result == 'skipped') }} | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Select-GitHubCiMatrix.ps1 |
| linux-test-driver | runner ${{ matrix.runner }} | linux-selection | ${{ !cancelled() && needs.linux-selection.result == 'success' && needs.linux-selection.outputs.has_docker_container_runtime == 'true' }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CiImage.ps1, ./scripts/New-CiModuleImage.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| performance-results | runner ubuntu-latest | windows, linux, linux-test-driver | ${{ always() && inputs.collect_performance }} | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/New-CorePerformanceReport.ps1 |
| qualification-gate | runner ubuntu-latest | windows, linux-result | ${{ always() }} | ./scripts/Assert-QualificationGate.ps1, ./scripts/Initialize-CiEnvironment.ps1 |
| windows | runner ${{ matrix.image }} |  | default success condition | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

All native/job-container build steps and Docker test-driver preparation use `Build-Workspace.ps1`, as does the local launcher. It compiles `Quietly.slnx` once, prepares portable outputs from `Get-QuietWorkspaceBuildProjects` using `dotnet publish --no-build`, then performs the existing RID/ReadyToRun engine publications. Binary identity reads the same manifest declarations. Container staging preserves `Quietly.slnx` and `Directory.Build.props`. No additional solution-only step recompiles the same projects in a matrix row. These source contracts do not establish that the hosted matrix has executed.

Every checkout initializes `.env` through `Initialize-CiEnvironment.ps1 -Target GitHub
-ContainerRuntime docker` before subsequent automation. The initializer writes only the public
runtime selection through the shared literal editor; it preserves other keys and loads no product
engine. Explicit Docker arguments remain authoritative. See [environment resolution](../environment.md).

Selected native Windows and Docker test-driver preparation jobs also use the shared optional resource-archive cache. The key includes runner OS and dependencies.lock.json hash; Restore-CoreResources still verifies extracted bytes. GitHub job-container preparation remains self-contained and does not depend on cache availability.

Windows runs natively. Linux selection partitions verified GHCR digests into supported GitHub job containers (`linux`) and the Docker test driver (`linux-test-driver`), including Alpine ARM64. Each row builds Release ReadyToRun for its tested RID and uses Invoke-GitHubCi with shared workers, SkipBuild and SkipTty. Functional evidence bundles are always collected. Only an explicit collect_performance=true request enables pinned profiling for Core/All, per-row performance reports and the combined performance-results job. Ordinary PR, develop and publication callers leave this disabled; missing performance evidence cannot fail those runs. Image builders explicitly select Docker. Failure bundles are bounded and redacted before 14-day upload.

Both selected Linux execution jobs explicitly use `!cancelled()`, require a successful selection
job and check their own selection flag. The status function overrides GitHub's implicit `success()`
condition, so skipped image-publication ancestors on a PR do not skip the selected tests. Failed
selection, cancellation and an unselected path still prevent execution. See the official
[dependency rules](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idneeds)
and [status functions](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions).

## Validation and limits

linux-result validates the selected paths and qualification-gate requires only Windows and Linux success before returning the exact qualified revision. Optional performance-results is not a gate dependency. When performance collection is explicitly requested, incomplete evidence still fails its requested report; the report validator is not weakened. The workflow contract regression checks default-off inputs, guarded reports and the absence of a performance gate dependency. Native TTY campaigns are excluded. wrkflw 0.8.0 cannot qualify the expression-valued matrices locally. Source qualification precedes a separate Windows package rebuild; it does not attest byte-identical matrix/package outputs.


## Mandatory tooling dependencies

Windows Core/All stable x64 InProcess prepares both tools explicitly with -Module profiler,dottrace even when collect_performance is false, because RunProfiles requires both official cached archives. Other Windows rows prepare tools only for explicitly requested performance collection; Git-only rows do not prepare them. Preparing dependencies does not activate Core profiling or performance reports. This fixes the missing-cache failure of run 42928490873. The source regression checks this condition separately from the opt-in performance contract.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
