# scripts-docs-apply.yml

<!-- workflow-source-sha256: E289236E238B57C4AFDADEF28947A711E18E423EC8E04002EF9C378A2E17E14A -->

## Purpose

Regenerate the scripts documentation index and managed source links on explicit dispatch, then commit and push the result.

## Triggers

Manual workflow_dispatch only. Dispatch is the existing workflow authorization for writing its branch; it is never invoked automatically on PR/push.

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/scripts-docs-apply.yml)

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
| apply | runner ubuntu-latest |  | default success condition | [`./scripts/Sync-ScriptsReadme.ps1`](../../scripts/Sync-ScriptsReadme.md) |

<!-- workflow-generated:end -->

## Scripts and effects

`Sync-ScriptsReadme -Apply` checks that every script has a document, then updates stale source links and the index. The final step stages `docs/scripts` and uses the GitHub bot identity to commit and push any changes. The workflow uses `contents: write` and persisted checkout credentials for that step.

## Validation and limits

Missing script documents remain a blocking error. This workflow cannot author semantic documentation, refresh workflow review receipts or exempt scripts from ShouldProcess. It is not called by local validation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
