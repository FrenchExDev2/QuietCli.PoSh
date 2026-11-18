# sync-credits-check.yml

<!-- workflow-source-sha256: 3C01691F0C36EE381E88F195AF62C84B6FA56EAA75207F35FBF78927D7781454 -->

## Purpose

Read-only validation of aggregate credits and mandatory documentation footers.

## Triggers

PR/develop path filters cover documentation, root READMEs, `readmes/README-*.md` guides, module license credits, CREDITS.md, the relevant generator/project scripts and these credits workflows. Manual dispatch is available.

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/sync-credits-check.yml)

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
| check | runner ubuntu-latest |  | default success condition | [`./scripts/Sync-Credits.ps1`](../../scripts/Sync-Credits.md), [`./scripts/Sync-DocsCredits.ps1`](../../scripts/Sync-DocsCredits.md) |

<!-- workflow-generated:end -->

## Scripts and effects

The check job calls Sync-Credits and Sync-DocsCredits without Apply, using contents:read and no persisted checkout credentials.

## Validation and limits

Missing or stale generated content fails rather than being repaired silently. The shared Invoke-WorkspaceChecks registry runs these same gates for commit preparation and automation checks; none establishes semantic documentation accuracy.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
