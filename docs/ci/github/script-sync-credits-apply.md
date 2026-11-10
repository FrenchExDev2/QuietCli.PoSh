# sync-credits-apply.yml

<!-- workflow-source-sha256: 321D4C448089802B4C5A5A86A4BA7F247F57477924290A535924669885023ED1 -->

## Purpose

Regenerate aggregate credits and mandatory documentation footers, then commit/push on explicit manual dispatch.

## Triggers

Manual workflow_dispatch only. No automatic PR/push trigger.

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
| apply | runner ubuntu-latest |  | default success condition | ./scripts/Sync-Credits.ps1, ./scripts/Sync-DocsCredits.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

Sync-Credits -Apply writes CREDITS.md; Sync-DocsCredits -Apply writes docs/root README credits blocks. The final bot step stages the documented paths, commits if changed and pushes to the dispatched branch using contents:write and persisted credentials.

## Validation and limits

These generators cover attribution linkage, not semantic accuracy or workflow review. The local check pipeline never invokes this mutating manual workflow. A no-change dispatch creates no commit.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
