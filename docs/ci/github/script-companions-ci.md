# companions-ci.yml

<!-- workflow-source-sha256: 45FB63F483B744583010DD0835F2AE56E61A7E819E4CB6A4CCF307AE1AE98AC7 -->

## Purpose

One automatic PR/develop entry point reads the complete diff and publishes the package/project/companion/action reason chain. A matrix runs full qualification only for selected groups; a grouped Windows/Linux smoke checks runtime dependents. Source checks and layout/property/malformed-input/mutation checks remain separate. Tooling and Distribution run when selected. The final check remains exactly QuietCli required CI, required by release automation. Missing prior merge evidence never broadens a targeted change to All; explicit shared/unknown inputs remain conservatively explained.

## Triggers

Every pull request and develop push. The planner selects work from the complete diff.

## Scripts and effects

Uses profile validation, source-bound build preparation, explicit selected qualification/smoke entry points and private artifacts. The PR planner publishes plan.json and impact.md; build_projects_json passes affected CSharp paths to Build-Workspace. GitHub may prepare pinned SDK/PowerShell resources and verified image caches. No module publication or repository setting change is performed here.

## Validation and limits

The stable automatic gate requires planning, source checks, generated-layout tests and every selected job. Skipped scopes are untested, not passed. A smoke/build result is not full product or publication qualification. Full native product runs retain their declared host/RID matrix, profiling policy and explicit TTY/Preview exclusions. Cache hits require source/payload/target verification; partial restores rebuild stale distributions.

Local WorkspaceLayout and CompanionSmoke reports exercise the selection and actual integration paths. Hosted matrix results must be inspected for the delivered revision. Authored workflow-source-sha256 receipts are reviewed separately from generated YAML and job graphs.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push"]
    job_ci_status["ci-status"]
    job_distribution["distribution"]
    job_layout_tests["layout-tests"]
    job_plan["plan"]
    job_products["products"]
    job_smokes["smokes"]
    job_source_checks["source-checks"]
    job_tooling_only["tooling-only"]
    job_plan --> job_ci_status
    job_source_checks --> job_ci_status
    job_layout_tests --> job_ci_status
    job_products --> job_ci_status
    job_smokes --> job_ci_status
    job_tooling_only --> job_ci_status
    job_distribution --> job_ci_status
    job_plan --> job_distribution
    event --> job_layout_tests
    event --> job_plan
    job_plan --> job_products
    job_plan --> job_smokes
    event --> job_source_checks
    job_plan --> job_tooling_only
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| ci-status | runner ubuntu-latest | plan, source-checks, layout-tests, products, smokes, tooling-only, distribution | ${{ always() }} | ./scripts/Assert-CiPlanResults.ps1 |
| distribution | reuses ./.github/workflows/distribution-ci.yml | plan | needs.plan.outputs.run_distribution == 'true' |  |
| layout-tests | runner windows-latest |  | default success condition | ./scripts/Invoke-WorkspaceChecks.ps1, ./scripts/Invoke-WorkspaceCi.ps1 |
| plan | runner ubuntu-latest |  | default success condition | ./scripts/New-CiImpactPlan.ps1 |
| products | reuses ./.github/workflows/ci.yml | plan | needs.plan.outputs.run_products == 'true' |  |
| smokes | reuses ./.github/workflows/workspace-component-ci.yml | plan | needs.plan.outputs.run_smokes == 'true' |  |
| source-checks | runner ubuntu-latest |  | default success condition | ./scripts/Invoke-WorkspaceChecks.ps1 |
| tooling-only | reuses ./.github/workflows/tooling-ci.yml | plan | needs.plan.outputs.run_tooling == 'true' |  |

<!-- workflow-generated:end -->

See [companion layout and selective CI](../../README-companion-layout-and-ci.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
