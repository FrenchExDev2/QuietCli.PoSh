# sync-credits-check.yml

<!-- workflow-source-sha256: 680FC011359B4F34C455E9E1F02C7091953E8B6B2D3E419424E2B5BFE139F7BC -->

## Purpose

Read-only validation of aggregate credits and mandatory documentation footers.

## Triggers

PR/develop path filters cover documentation, READMEs, module license credits, CREDITS.md, the relevant generator/project scripts and these credits workflows; manual dispatch is supported.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push, workflow_dispatch"]
    job_check["check"]
    event --> job_check
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| check | runner ubuntu-latest |  | default success condition | ./scripts/Sync-Credits.ps1, ./scripts/Sync-DocsCredits.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

The check job calls Sync-Credits and Sync-DocsCredits without Apply, using contents:read and no persisted checkout credentials.

## Validation and limits

Missing or stale generated content fails rather than being repaired silently. The shared Invoke-WorkspaceChecks registry runs these same gates for commit preparation and automation checks; none establishes semantic documentation accuracy.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
