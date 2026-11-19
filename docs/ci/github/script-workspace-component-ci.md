# workspace-component-ci.yml

<!-- workflow-source-sha256: BD19E3AA73E4D943BE77511A61D6B195E37A431FFB420D3C7C8BA0A736A9D655 -->

## Purpose

Shared profile-validated workspace build/smoke engine. Supports individual components and an explicit nonempty SmokeBatch. It verifies paths, prepares source-bound dependencies, restores verified target-scoped caches and uses the common local/headless test runner. Full Tooling delegates to its existing workflow. Smokes are separate evidence and never publication qualification.

## Triggers

Reusable workflow_call.

## Scripts and effects

Before build-cache restoration and execution, Initialize-CiEnvironment selects the checkout's GitHub Docker preset and Initialize-Workspace restores checksum-pinned runtime resources. A cold cache therefore has the same dependency prerequisites as a product job.

Uses profile validation, source-bound build preparation, explicit selected qualification/smoke entry points and private artifacts. The PR planner publishes plan.json and impact.md; build_projects_json passes affected CSharp paths to Build-Workspace. GitHub may prepare pinned SDK/PowerShell resources and verified image caches. No module publication or repository setting change is performed here.

## Validation and limits

The stable automatic gate requires planning, source checks, generated-layout tests and every selected job. Skipped scopes are untested, not passed. A smoke/build result is not full product or publication qualification. Full native product runs retain their declared host/RID matrix, profiling policy and explicit TTY/Preview exclusions. Cache hits require source/payload/target verification; partial restores rebuild stale distributions.

Local WorkspaceLayout and CompanionSmoke reports exercise the selection and actual integration paths. Hosted matrix results must be inspected for the delivered revision. Authored workflow-source-sha256 receipts are reviewed separately from generated YAML and job graphs.

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/workspace-component-ci.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_call"]
    job_component["component"]
    job_tooling["tooling"]
    job_validate["validate"]
    job_validate --> job_component
    job_validate --> job_tooling
    event --> job_validate
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| component | <code>runner &#36;{{ inputs.runner }}</code> | validate | <code>inputs.suite != 'Tooling' &#124;&#124; inputs.qualification&#95;mode != 'full'</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Get-CompanionBuildKey.ps1`](../../scripts/Get-CompanionBuildKey.md), [`./scripts/Invoke-ComponentCheck.ps1`](../../scripts/Invoke-ComponentCheck.md) |
| tooling | reuses ./.github/workflows/tooling-ci.yml | validate | <code>inputs.suite == 'Tooling' &#38;&#38; inputs.qualification&#95;mode == 'full'</code> |  |
| validate | runner ubuntu-latest |  | default success condition | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Invoke-ComponentCheck.ps1`](../../scripts/Invoke-ComponentCheck.md) |

<!-- workflow-generated:end -->

See [companion layout and selective CI](../../README-companion-layout-and-ci.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
