# companions-ci.yml

<!-- workflow-source-sha256: 6C9707EF3AEEE6F69A39F21F5D30747EDF53F8D8FB4C78F21E6889DF3A9ECB2A -->

## Purpose

One stable pull-request/develop entry point for discovered companions. The complete no-rename diff and transitive catalogue requirements select a companion-only scope, shared All scope or tooling-only campaign. Unknown inputs conservatively require All. Documentation-only plans can omit native tests while the final QuietCli required CI check remains present.

Develop reuses successful merged-PR evidence only when its bounded artifact, authoritative workflow run/attempt and exact Git tree match. Legacy/missing/expired/mismatched receipts fall back to complete All qualification. Reuse still verifies the merged source lock, Core integration and native image caches. No module publication occurs on develop.

## Validation and limits

The unconditional final check rejects failed/cancelled planning and required campaigns, including incorrectly skipped product/tooling jobs. Configure required checks, up-to-date branches and direct-push restrictions separately in repository rules. No repository settings are changed by this workflow. Publication requires its own exact revision/current-run evidence and explicit module tags.

## Triggers

Every pull request and develop push; the plan decides which campaigns are required.

## Scripts and effects

Uses the shared scripts/ entry points, validated source lock, selected builds and private artifacts described above. Network access is limited to pinned dependency preparation, verified image caches and explicit GitHub evidence reads. No module publication occurs here.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push"]
    job_ci_status["ci-status"]
    job_companions["companions"]
    job_develop_images["develop-images"]
    job_develop_smoke["develop-smoke"]
    job_plan["plan"]
    job_tooling_only["tooling-only"]
    job_plan --> job_ci_status
    job_companions --> job_ci_status
    job_tooling_only --> job_ci_status
    job_develop_smoke --> job_ci_status
    job_develop_images --> job_ci_status
    job_plan --> job_companions
    job_plan --> job_develop_images
    job_plan --> job_develop_smoke
    event --> job_plan
    job_plan --> job_tooling_only
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| ci-status | runner ubuntu-latest | plan, companions, tooling-only, develop-smoke, develop-images | ${{ always() }} |  |
| companions | reuses ./.github/workflows/ci.yml | plan | needs.plan.outputs.run_products == 'true' |  |
| develop-images | runner ${{ matrix.runner }} | plan | github.event_name == 'push' && needs.plan.outputs.run_products == 'false' && github.repository == 'FrenchExDev2/QuietCli.PoSh' | ./scripts/New-CiSuiteImage.ps1 |
| develop-smoke | runner windows-latest | plan | github.event_name == 'push' && needs.plan.outputs.run_products == 'false' | ./scripts/Build-Workspace.ps1, ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1 |
| plan | runner ubuntu-latest |  | default success condition | ./scripts/New-CiImpactPlan.ps1 |
| tooling-only | reuses ./.github/workflows/tooling-ci.yml | plan | needs.plan.outputs.run_products == 'false' && needs.plan.outputs.run_tooling == 'true' |  |

<!-- workflow-generated:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
