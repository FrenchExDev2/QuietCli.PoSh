# sync-credits-apply.yml

<!-- workflow-source-sha256: D2CFAC81599F411B8FDF577BA485CAD4BFBFBF61D73F02BDAE19071EC9C0539F -->

## Purpose

Regenerate aggregate credits and mandatory documentation footers, then commit/push on explicit manual dispatch.

## Triggers

Manual workflow_dispatch only. No automatic PR/push trigger.

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/sync-credits-apply.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_dispatch"]
    job_apply["apply"]
    event --> job_apply
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| apply | runner ubuntu-latest |  | default success condition | [`./scripts/Sync-Credits.ps1`](../../scripts/Sync-Credits.md), [`./scripts/Sync-DocsCredits.ps1`](../../scripts/Sync-DocsCredits.md) |

<!-- workflow-generated:end -->

## Scripts and effects

`Sync-Credits -Apply` writes CREDITS.md. `Sync-DocsCredits -Apply` updates credits blocks in docs, root READMEs and `readmes/` guides. The final bot step stages these paths, commits if changed and pushes to the dispatched branch using contents:write and persisted credentials.

## Validation and limits

These generators cover attribution linkage, not semantic accuracy or workflow review. The local check pipeline never invokes this mutating manual workflow. A no-change dispatch creates no commit.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
