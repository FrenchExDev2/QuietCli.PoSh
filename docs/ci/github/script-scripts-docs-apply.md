# scripts-docs-apply.yml

<!-- workflow-source-sha256: A130CAE1A641CD5874A3C7C235FF489EDBD76AA736BE35757E4FC5B4194E1185 -->

## Purpose

Regenerate the existing scripts documentation index and commit/push that result on explicit dispatch.

## Triggers

Manual workflow_dispatch only. Dispatch is the existing workflow authorization for writing its branch; it is never invoked automatically on PR/push.

<!-- workflow-generated:begin -->
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
| apply | runner ubuntu-latest |  | default success condition | ./scripts/Sync-ScriptsReadme.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

Sync-ScriptsReadme -Apply regenerates docs/scripts/README.md only after every script already has a document. The final step stages that index and uses the GitHub bot identity to commit and push if changed. contents:write and persisted checkout credentials are intentional for this manual operation.

## Validation and limits

Missing script documents remain a blocking error. This workflow cannot author semantic documentation, refresh workflow review receipts or exempt scripts from ShouldProcess. It is not called by local validation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
