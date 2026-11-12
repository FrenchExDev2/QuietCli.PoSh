# qualification.yml

<!-- workflow-source-sha256: 0AA9397C93847960C24D0FA5D776F38B587D29F5BF4C78AF9CB24021CA3BE4FA -->

## Purpose

Explicit full Git capability qualification on a separately provisioned self-hosted runner.

## Triggers

Manual workflow_dispatch only; no develop or publication dependency.

## Execution and limits

This manual path declares a separately provisioned self-hosted Linux/Podman/KVM runner. Its full capability runner remains deliberately unimplemented and fails closed; it cannot currently establish exhaustive Git qualification. It is independent of the hosted ten-target product matrix and has no release/develop dependency. See [execution boundaries](../execution-model.md).

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_dispatch"]
    job_qualification["qualification"]
    event --> job_qualification
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| qualification | runner self-hosted, linux, x64, podman, kvm |  | default success condition | ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitQualification.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

An optional shared resource-archive cache precedes preparation. Cache hits do not qualify the self-hosted runner or bypass resource hash verification.

Requires self-hosted Linux x64 labels podman and kvm, restores the source lock, then calls Invoke-GitQualification with QUIETCLI_QUALIFICATION_CONFIG. Qualification artifacts upload with always().

## Validation and limits

Invoke-GitQualification is deliberately unimplemented and fails closed. Runner labels declare prerequisites, not proof of an installed/working Podman/KVM or completed full qualification. This workflow is distinct from the normal GitHub-hosted CI.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
