# core-ci.yml

<!-- workflow-source-sha256: F1266C71FFADD247D8ADC72234ABB8B656089143DE3288659955C5788791D77F -->

## Purpose

Path-filtered Core development qualification through the shared CI implementation.

## Triggers

PRs and develop pushes matching Core/Core.Tests, shared scripts/build/.github, SDK or repository policy paths. No direct manual trigger.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push"]
    job_core["core"]
    event --> job_core
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| core | reuses ./.github/workflows/ci.yml |  | default success condition |  |

<!-- workflow-generated:end -->

## Scripts and effects

The core job calls ci.yml with suite=Core and packages:write. Core-only development does not run consumer Git suites. Image publication remains governed by the reusable workflow event/repository checks.

## Validation and limits

Qualification and evidence behavior are defined by ci.yml; a path filter is scope selection, not successful qualification. PSGallery delivery separately requests All.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
