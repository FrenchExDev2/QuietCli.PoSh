# companions-ci.yml

<!-- workflow-source-sha256: 7436BECDF0DB0D58BDC73553FF5C7429B6AD1F90E7C1B12515361420BF3DFF1A -->

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

When the plan selects products or ReadyToRun, the `images` job calls the shared image workflow once for the run. Four native jobs prepare the selected chains and upload one bundle per RID. `products` and `readytorun` wait for the producer and use those bundles. Registry publication is restricted to upstream develop pushes and dispatches. A failed producer blocks its consumers and fails the required status.

Uses profile validation, source-bound build preparation, explicit selected qualification/smoke entry points and private artifacts. The PR planner publishes plan.json and impact.md; build_projects_json passes affected CSharp paths to Build-Workspace. GitHub may prepare pinned SDK/PowerShell resources and verified image caches. No module publication or repository setting change is performed here.

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
    job_plan --> job_ci_status
    job_source_checks --> job_ci_status
    job_layout_tests --> job_ci_status
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
    job_plan --> job_distribution
    job_source_checks --> job_distribution
    job_layout_tests --> job_distribution
    job_plan --> job_images
    job_source_checks --> job_images
    job_plan --> job_layout_tests
    event --> job_plan
    job_plan --> job_products
    job_source_checks --> job_products
    job_layout_tests --> job_products
    job_images --> job_products
    job_plan --> job_readytorun
    job_source_checks --> job_readytorun
    job_layout_tests --> job_readytorun
    job_images --> job_readytorun
    job_plan --> job_smokes
    job_source_checks --> job_smokes
    job_layout_tests --> job_smokes
    event --> job_source_checks
    job_plan --> job_tooling_only
    job_source_checks --> job_tooling_only
    job_layout_tests --> job_tooling_only
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| ci-status | runner ubuntu-latest | plan, source-checks, layout-tests, images, products, smokes, tooling-only, companion-checks, distribution, readytorun | <code>&#36;{{ always() }}</code> | [`./scripts/Assert-CiPlanResults.ps1`](../../scripts/Assert-CiPlanResults.md) |
| companion-checks | reuses ./.github/workflows/workspace-component-ci.yml | plan, source-checks, layout-tests | <code>needs.plan.outputs.run&#95;companion&#95;checks == 'true'</code> |  |
| distribution | reuses ./.github/workflows/distribution-ci.yml | plan, source-checks, layout-tests | <code>needs.plan.outputs.run&#95;distribution == 'true'</code> |  |
| images | reuses ./.github/workflows/linux-images.yml | plan, source-checks | <code>needs.plan.outputs.run&#95;products == 'true' &#124;&#124; needs.plan.outputs.run&#95;readytorun == 'true'</code> |  |
| layout-tests | runner windows-latest | plan | <code>needs.plan.outputs.run&#95;layout == 'true'</code> | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md), [`./scripts/Invoke-WorkspaceCi.ps1`](../../scripts/Invoke-WorkspaceCi.md) |
| plan | runner ubuntu-latest |  | default success condition | [`./scripts/Invoke-GitHubCiPlan.ps1`](../../scripts/Invoke-GitHubCiPlan.md) |
| products | reuses ./.github/workflows/ci.yml | plan, source-checks, layout-tests, images | <code>&#36;{{ always() &#38;&#38; !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; needs.layout-tests.result == 'success' &#38;&#38; needs.images.result == 'success' &#38;&#38; needs.plan.outputs.run&#95;products == 'true' }}</code> |  |
| readytorun | reuses ./.github/workflows/quietcli2-readytorun.yml | plan, source-checks, layout-tests, images | <code>needs.plan.outputs.run&#95;readytorun == 'true'</code> |  |
| smokes | reuses ./.github/workflows/workspace-component-ci.yml | plan, source-checks, layout-tests | <code>needs.plan.outputs.run&#95;smokes == 'true'</code> |  |
| source-checks | runner ubuntu-latest |  | default success condition | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md) |
| tooling-only | reuses ./.github/workflows/tooling-ci.yml | plan, source-checks, layout-tests | <code>&#36;{{ always() &#38;&#38; !cancelled() &#38;&#38; needs.plan.result == 'success' &#38;&#38; needs.source-checks.result == 'success' &#38;&#38; (needs.layout-tests.result == 'success' &#124;&#124; (needs.layout-tests.result == 'skipped' &#38;&#38; needs.plan.outputs.run&#95;layout == 'false')) &#38;&#38; needs.plan.outputs.run&#95;tooling == 'true' }}</code> |  |

<!-- workflow-generated:end -->

See [companion layout and selective CI](../../README-companion-layout-and-ci.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

## Pull request checklist

The script mutation cache checkbox passes `script_mutation_no_input_cache` to `tooling-ci.yml`. It changes how the selected script mutation shards run. Their selection still comes from the diff and the repository script mutation checkbox.

PR description edits recompute the plan. Invoke-GitHubCiPlan passes the raw description to New-CiImpactPlan, and the required check verifies complete evidence from the selected jobs and the current PR. See [PR options](../../README-pull-request-ci.md).
