# companions-ci.yml

<!-- workflow-source-sha256: CC7BE0543AB68168A3E6838F11844665EB9F79CBEBF7EB71BFEF5423FE27A357 -->

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

Selected campaigns wait for successful planning, source checks and layout validation, so invalid shared inputs stop before costly builds and test campaigns.

On develop pushes and dispatches that qualify products, the `images` job is the single Linux image producer of the run: one job per RID, serialized across runs by `quietcli2-ci-images-<rid>` without cancelling a publication. It passes the plan's `image_suites` to New-CiSuiteImage.ps1, which resolves or builds each distinct chain once, base first, then caches the intermediate layers. `products` starts only after that job succeeded or was skipped (pull requests, other repositories) and passes `images_prepared`, so the per-suite calls of ci.yml do not race it. A failed warm-up blocks qualification and fails the required status.

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
    job_distribution["distribution"]
    job_images["images"]
    job_layout_tests["layout-tests"]
    job_plan["plan"]
    job_products["products"]
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
    job_distribution --> job_ci_status
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
| ci-status | runner ubuntu-latest | plan, source-checks, layout-tests, images, products, smokes, tooling-only, distribution | ${{ always() }} | [`./scripts/Assert-CiPlanResults.ps1`](../../scripts/Assert-CiPlanResults.md) |
| distribution | reuses ./.github/workflows/distribution-ci.yml | plan, source-checks, layout-tests | needs.plan.outputs.run_distribution == 'true' |  |
| images | runner ${{ matrix.runner }} | plan, source-checks | needs.plan.outputs.run_products == 'true' && github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' && (github.event_name == 'push' &#124;&#124; github.event_name == 'workflow_dispatch') | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/New-CiSuiteImage.ps1`](../../scripts/New-CiSuiteImage.md) |
| layout-tests | runner windows-latest | plan | needs.plan.outputs.run_layout == 'true' | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md), [`./scripts/Invoke-WorkspaceCi.ps1`](../../scripts/Invoke-WorkspaceCi.md) |
| plan | runner ubuntu-latest |  | default success condition | [`./scripts/New-CiImpactPlan.ps1`](../../scripts/New-CiImpactPlan.md) |
| products | reuses ./.github/workflows/ci.yml | plan, source-checks, layout-tests, images | ${{ always() && !cancelled() && needs.plan.result == 'success' && needs.source-checks.result == 'success' && needs.layout-tests.result == 'success' && (needs.images.result == 'success' &#124;&#124; needs.images.result == 'skipped') && needs.plan.outputs.run_products == 'true' }} |  |
| smokes | reuses ./.github/workflows/workspace-component-ci.yml | plan, source-checks, layout-tests | needs.plan.outputs.run_smokes == 'true' |  |
| source-checks | runner ubuntu-latest |  | default success condition | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md) |
| tooling-only | reuses ./.github/workflows/tooling-ci.yml | plan, source-checks, layout-tests | ${{ always() && !cancelled() && needs.plan.result == 'success' && needs.source-checks.result == 'success' && (needs.layout-tests.result == 'success' &#124;&#124; (needs.layout-tests.result == 'skipped' && needs.plan.outputs.run_layout == 'false')) && needs.plan.outputs.run_tooling == 'true' }} |  |

<!-- workflow-generated:end -->

See [companion layout and selective CI](../../README-companion-layout-and-ci.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
