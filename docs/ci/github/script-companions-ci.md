# companions-ci.yml

<!-- workflow-source-sha256: CED6FEF283537FC749F56DFFFDA7753D1B5F5D065FB51162429C587099B3DA49 -->

## Purpose

One automatic PR/develop entry point reads the complete diff and publishes the package/project/companion/action reason chain. A matrix runs full qualification only for selected groups; a grouped Windows/Linux smoke checks runtime dependents. Source checks and layout/property/malformed-input/mutation checks remain separate. Tooling and Distribution run when selected. The final check remains exactly QuietCli required CI, required by release automation. Missing prior merge evidence never broadens a targeted change to All; explicit shared/unknown inputs remain conservatively explained.

## Triggers

Every pull request and develop push. The planner selects work from the complete diff. A change limited to repository scripts (`scripts/**`, `test/scripts/**`) runs only the script tests and the script mutation targets it reaches:
- `tooling-only` calls `tooling-ci.yml` with `scope: scripts` and the planned `script_tests` and `script_mutation_targets`;
- `layout-tests`, products, smokes, images and distribution are skipped;
- `scripts-docs-check.yml` still runs every workspace check.

A manual `workflow_dispatch` on any branch takes a `suites` input: comma-separated companion names, `Tooling`, or `all` by default.
- It qualifies the named companions in full and reads no diff. Distribution never runs.
- `Tooling` runs the full tooling workflow: Core without Git, run profiles, every script test with coverage and every script mutation target. Use it after a change to qualification scripts.
- `all` runs every companion plus the full tooling. Dependents of the chosen companions get their usual smoke. On develop, the run also warms and publishes the Linux images. See [New-CiImpactPlan](../../scripts/New-CiImpactPlan.md#manual-dispatch).

## Scripts and effects

The planner supplies a companion-check matrix for requested mutation and profiling. When both options select the same companion, one matrix row profiles its mutation pass. The matrix result is required when the PR selects a pass. Each matrix respects the declared parallelism.

Selected campaigns wait for successful planning, source checks and layout validation, so invalid shared inputs stop before costly builds and test campaigns.

When the plan selects products, ReadyToRun or image cache renewal, the `images` job calls the shared image workflow once for the run. Four native jobs prepare the selected chains and upload one handoff per RID. `products` and `readytorun` restore or load the identified images. Checking **Renew images caches** forces fresh images and records the option in the CI plan. Registry publication is restricted to upstream develop pushes and dispatches. A failed producer blocks its consumers and fails the required status.

For a PR with a selected binary consumer, the `build` job on Windows x64 compiles the Release solution once and prepares the declared libraries. Product and benchmark plans request the six ReadyToRun RIDs. Benchmarks also request the six IL apphost publications. The job verifies the archive's checkout SHA and checksum after either building or restoring an exact cache entry. It uploads the archive for the current run and passes its immutable artifact ID to product, smoke, distribution, tooling and profiling consumers. Plans containing only source checks and source-only campaigns skip the build job.

The PR planner publishes plan.json and impact.md with the affected project paths and test scopes. Test runners still qualify the planned suites, host modes and native RIDs. Standalone and develop invocations retain their own build/cache path. The Git-absent Core build and mutation builds still execute in their isolated source copies.

## Validation and limits

The stable automatic gate requires planning, source checks and every selected job. Generated-layout tests are selected (`run_layout`) unless script tests are the whole plan. `tooling-only` waits for them, or for their planned skip. Skipped scopes are untested, not passed. A smoke/build result is not full product or publication qualification. Full native product runs retain their declared host/RID matrix, profiling policy and explicit TTY/Preview exclusions. Cache hits require source/payload/target verification; partial restores rebuild stale distributions.

Local WorkspaceLayout and CompanionSmoke reports exercise the selection and actual integration paths. Hosted matrix results must be inspected for the delivered revision. Authored workflow-source-sha256 receipts are reviewed separately from generated YAML and job graphs.

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/companions-ci.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push, workflow_dispatch"]
    job_build["build"]
    job_ci_status["ci-status"]
    job_companion_checks["companion-checks"]
    job_distribution["distribution"]
    job_images["images"]
    job_layout_tests["layout-tests"]
    job_plan["plan"]
    job_products["products"]
    job_readytorun["readytorun"]
    job_smokes["smokes"]
    job_source_checks["source-checks"]
    job_tooling_only["tooling-only"]
    job_plan --> job_build
    job_source_checks --> job_build
    job_plan --> job_ci_status
    job_source_checks --> job_ci_status
    job_layout_tests --> job_ci_status
    job_build --> job_ci_status
    job_images --> job_ci_status
    job_products --> job_ci_status
    job_smokes --> job_ci_status
    job_tooling_only --> job_ci_status
    job_companion_checks --> job_ci_status
    job_distribution --> job_ci_status
    job_readytorun --> job_ci_status
    job_plan --> job_companion_checks
    job_source_checks --> job_companion_checks
    job_layout_tests --> job_companion_checks
    job_build --> job_companion_checks
    job_plan --> job_distribution
    job_source_checks --> job_distribution
    job_layout_tests --> job_distribution
    job_build --> job_distribution
    job_plan --> job_images
    job_source_checks --> job_images
    job_plan --> job_layout_tests
    event --> job_plan
    job_plan --> job_products
    job_source_checks --> job_products
    job_layout_tests --> job_products
    job_images --> job_products
    job_build --> job_products
    job_plan --> job_readytorun
    job_source_checks --> job_readytorun
    job_layout_tests --> job_readytorun
    job_images --> job_readytorun
    job_build --> job_readytorun
    job_plan --> job_smokes
    job_source_checks --> job_smokes
    job_layout_tests --> job_smokes
    job_build --> job_smokes
    event --> job_source_checks
    job_plan --> job_tooling_only
    job_source_checks --> job_tooling_only
    job_layout_tests --> job_tooling_only
    job_build --> job_tooling_only
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| build | runner windows-latest | plan, source-checks | <code>github.event&#95;name == 'pull&#95;request' &#38;&#38; needs.plan.outputs.run&#95;shared&#95;build == 'true'</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/lib/RuntimeTargets.psm1`](../../scripts/lib/RuntimeTargets.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/Sync-CiBuildArtifact.ps1`](../../scripts/Sync-CiBuildArtifact.md) |
| ci-status | runner ubuntu-latest | plan, source-checks, layout-tests, build, images, products, smokes, tooling-only, companion-checks, distribution, readytorun | <code>&#36;{{ always() }}</code> | [`./scripts/Assert-CiPlanResults.ps1`](../../scripts/Assert-CiPlanResults.md) |
| companion-checks | reuses ./.github/workflows/workspace-component-ci.yml | plan, source-checks, layout-tests, build | <code>&#36;{{ !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; needs.layout-tests.result == 'success' &#38;&#38; needs.plan.outputs.run&#95;companion&#95;checks == 'true' &#38;&#38; (github.event&#95;name != 'pull&#95;request' &#124;&#124; needs.plan.outputs.run&#95;shared&#95;build == 'false' &#124;&#124; needs.build.outputs.artifact != '') }}</code> |  |
| distribution | reuses ./.github/workflows/workspace-component-ci.yml | plan, source-checks, layout-tests, build | <code>&#36;{{ !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; needs.layout-tests.result == 'success' &#38;&#38; needs.plan.outputs.run&#95;distribution == 'true' &#38;&#38; (github.event&#95;name != 'pull&#95;request' &#124;&#124; needs.build.outputs.artifact != '') }}</code> |  |
| images | reuses ./.github/workflows/linux-images.yml | plan, source-checks | <code>needs.plan.outputs.run&#95;products == 'true' &#124;&#124; needs.plan.outputs.run&#95;readytorun == 'true' &#124;&#124; needs.plan.outputs.renew&#95;image&#95;caches == 'true'</code> |  |
| layout-tests | runner windows-latest | plan | <code>needs.plan.outputs.run&#95;layout == 'true'</code> | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md), [`./scripts/Invoke-WorkspaceCi.ps1`](../../scripts/Invoke-WorkspaceCi.md) |
| plan | runner ubuntu-latest |  | default success condition | [`./scripts/Invoke-GitHubCiPlan.ps1`](../../scripts/Invoke-GitHubCiPlan.md) |
| products | reuses ./.github/workflows/ci.yml | plan, source-checks, layout-tests, images, build | <code>&#36;{{ always() &#38;&#38; !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; needs.layout-tests.result == 'success' &#38;&#38; needs.images.result == 'success' &#38;&#38; needs.plan.outputs.run&#95;products == 'true' &#38;&#38; (github.event&#95;name != 'pull&#95;request' &#124;&#124; needs.build.outputs.artifact != '') }}</code> |  |
| readytorun | reuses ./.github/workflows/quietcli2-readytorun.yml | plan, source-checks, layout-tests, images, build | <code>&#36;{{ !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; needs.layout-tests.result == 'success' &#38;&#38; needs.images.result == 'success' &#38;&#38; needs.plan.outputs.run&#95;readytorun == 'true' &#38;&#38; (github.event&#95;name != 'pull&#95;request' &#124;&#124; needs.build.outputs.artifact != '') }}</code> |  |
| smokes | reuses ./.github/workflows/workspace-component-ci.yml | plan, source-checks, layout-tests, build | <code>&#36;{{ !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; needs.layout-tests.result == 'success' &#38;&#38; needs.plan.outputs.run&#95;smokes == 'true' &#38;&#38; (github.event&#95;name != 'pull&#95;request' &#124;&#124; needs.build.outputs.artifact != '') }}</code> |  |
| source-checks | runner ubuntu-latest |  | default success condition | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md) |
| tooling-only | reuses ./.github/workflows/tooling-ci.yml | plan, source-checks, layout-tests, build | <code>&#36;{{ always() &#38;&#38; !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; (needs.layout-tests.result == 'success' &#124;&#124; (needs.layout-tests.result == 'skipped' &#38;&#38; needs.plan.outputs.run&#95;layout == 'false')) &#38;&#38; needs.plan.outputs.run&#95;tooling == 'true' &#38;&#38; (github.event&#95;name != 'pull&#95;request' &#124;&#124; needs.plan.outputs.tooling&#95;requires&#95;build == 'false' &#124;&#124; needs.build.outputs.artifact != '') }}</code> |  |

<!-- workflow-generated:end -->

See [companion layout and selective CI](../../README-companion-layout-and-ci.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

## Pull request checklist

The script mutation cache checkbox passes `script_mutation_no_input_cache` to `tooling-ci.yml`. It changes how the selected script mutation shards run. Their selection still comes from the diff and the repository script mutation checkbox.

PR description edits recompute the plan. Invoke-GitHubCiPlan passes the raw description to New-CiImpactPlan, and the required check verifies complete evidence from the selected jobs and the current PR. See [PR options](../../README-pull-request-ci.md).
