# ci.yml

<!-- workflow-source-sha256: 7433781CDE6F5448823FC66927DC90076BB0C98F87FC312E3080905B70F69980 -->

## Purpose

Shared qualification for the selected Core, Git or All source scope across six Windows host/mode combinations and four native Linux RID targets.

The host contract checks required prerequisites as a set rather than requiring an obsolete exact dependency line. Core evidence uploads include owned hidden files from artifacts/evidence only; literal bracketed Gallery XML paths retain their real byte counts and hashes. Functional failure prevents companion fan-out and the later profiling phase, but partial HTML and original failure diagnostics are retained. Missing profiles still block qualification.

## Triggers

Reusable workflow_call and workflow_dispatch accept a declared suite (default All) and
collect_performance (boolean, default true; required to qualify Core evidence). companions-ci.yml provides generic path-filtered
PR/develop events without requesting performance collection. Image publication remains restricted
to upstream develop pushes/manual dispatch; PR images are never published.


## .NET SDK source pin

The reviewed setup-dotnet steps read the checked-out global.json through global-json-file, so the CI, publication preparation and manual ReadyToRun jobs follow the selected SDK instead of embedding an old RC string. This source review does not establish hosted execution or full matrix qualification.

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
| qualification-gate | runner ubuntu-latest | linux-matrix, windows, linux-result, performance-results | ${{ always() }} | ./scripts/Assert-QualificationGate.ps1, ./scripts/Initialize-CiEnvironment.ps1 |
| windows | runner ${{ matrix.image }} | linux-matrix | default success condition | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-CiCompanions.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Initialize-Profilers.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-CoreEvidenceBundle.ps1, ./scripts/New-CorePerformanceReport.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

One `linux-images` matrix prepares the final suite image per RID. The producer uses ResolveOnly: existing registry configurations are verified without pulling layers; misses prepare/publish base and overlays on the same runner. Execution pulls only the verified final image, without preparing parents on a hit. PR fallback remains non-publishing. All tests share that image: Core completes first with its Git requirement, then other suites run in bounded isolated processes in the same matrix target. There is no extra build or image transfer for this fan-out. Windows host ZIP caching separates channel/architecture/lock keys; NuGet keys include central versions, build properties and global.json. Supported Linux job containers use resource and NuGet caches too. Every cache consumer retains integrity verification.

`build/companions.yml` separates product dependencies, image participation and independent test
suites. Initialize-CiCompanions.ps1 exports Core-evidence policy and RID/CLR-matched controls through
scripts/lib/CiCompanions.psm1. The shared workflow contains no companion-specific mutation variables
or image branch. New-CiSuiteImage.ps1 composes the declared layers for linux-suite-images, registry
selection and the non-publishing Docker fallback. Core's commit test declares its Git requirement
there, fixing Debian's Unsupported status result with distro Git 2.39 on x64 and ARM64.

Core/Vagrant integration tests can declare their own test module/runner and both required products;
Core's product graph remains unchanged. The shared entry wildcard covers future companion and
integration test directories. Image caching and test scheduling optimization are not part of this
generalization.

All native/job-container build steps and Docker test-driver preparation use `Build-Workspace.ps1`, as does the local launcher. It compiles `Quietly.slnx` once, prepares portable outputs from `Get-QuietWorkspaceBuildProjects` using `dotnet publish --no-build`, then performs the existing RID/ReadyToRun engine publications. Binary identity reads the same manifest declarations. Container staging preserves `Quietly.slnx` and `Directory.Build.props`. No additional solution-only step recompiles the same projects in a matrix row. These source contracts do not establish that the hosted matrix has executed.

Every checkout initializes `.env` through `Initialize-CiEnvironment.ps1 -Target GitHub
-ContainerRuntime docker` before subsequent automation. The initializer writes only the public
runtime selection through the shared literal editor; it preserves other keys and loads no product
engine. Explicit Docker arguments remain authoritative. See [environment resolution](../environment.md).

Selected native Windows and Docker test-driver preparation jobs also use the shared optional resource-archive cache. The key includes runner OS and dependencies.lock.json hash; Restore-CoreResources still verifies extracted bytes. GitHub job-container preparation remains self-contained and does not depend on cache availability.

Windows runs natively. Linux selection partitions verified GHCR digests into job containers and Docker test-driver fallback, including Alpine ARM64. Each row builds Release ReadyToRun for its tested RID and uses Invoke-GitHubCi with shared workers, SkipBuild and SkipTty. Every Core/All row requests pinned PowerShell/CLR profiling by default; automatic PR/develop/publication callers explicitly set collect_performance=true. Functional bundles and per-row reports are always collected; the combined job emits standalone HTML/Markdown/JSON for all ten environments. Disabling collection cannot pass Core qualification. Image builders explicitly select Docker. Failure bundles remain bounded/redacted; raw diagnostic traces remain in their per-environment artifacts.

Both selected Linux execution jobs explicitly use `!cancelled()`, require a successful selection
job and check their own selection flag. The status function overrides GitHub's implicit `success()`
condition, so skipped image-publication ancestors on a PR do not skip the selected tests. Failed
selection, cancellation and an unselected path still prevent execution. See the official
[dependency rules](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idneeds)
and [status functions](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions).

## Validation and limits

The shared final image explicitly includes GNU tar and zstd for actions/cache, including Alpine where BusyBox tar does not implement the archive flags used by the action. Recipe assertions cover all four RID declarations. This source check does not substitute for actual hosted archive restore/save.

linux-result validates every selected Linux path. qualification-gate additionally waits for performance-results and passes its outcome to Assert-QualificationGate; Core-evidence scopes require success. Current-run All receipt reuse also requires Performance=success and PerformanceRequired=true. Missing/failed/skipped profiling or incomplete matrix reports cannot emit qualified_sha. Native TTY campaigns remain explicitly excluded. Local workflow/source/property checks do not qualify unexecuted remote platforms, trace attachments or byte-identical matrix/package outputs.


## Mandatory tooling dependencies

The functional and mutation steps have stable IDs `run_profiles` and `run_profiles_mutation`.
Their combined artifact upload runs only if at least one selected campaign actually started
(success, failure or cancellation), including partial evidence after failure. If Core failed
before both campaigns, skipped/absent outcomes do not request a nonexistent artifact. An executed
campaign without reports still fails `if-no-files-found: error`; the evidence requirement is not
weakened. The actual workflow condition is checked across 400 eligibility/outcome combinations,
including a mutation that removes the started-campaign requirement.

Windows selections declaring Core evidence prepare both tools on stable x64 InProcess with
-Module profiler,dottrace even when collect_performance is false, because RunProfiles requires both
official cached archives. Other Windows rows prepare them only for requested Core performance
collection. Tool dependencies alone do not enable Core evidence. Preparing tools does not activate
profiling or reports. The source regression checks this separately from the matrix collection/qualification contract.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
