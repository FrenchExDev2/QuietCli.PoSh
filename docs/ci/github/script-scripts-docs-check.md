# scripts-docs-check.yml

<!-- workflow-source-sha256: FF1DBE8C22FDB4125947704037531728801CA3889CB134C93A316EB10F73B818 -->

## Purpose

Shared automation-contract pipeline for script docs, workflow docs, resources, objectives and preview support.

## Triggers

PR/develop path filters cover scripts, docs/scripts, docs/ci/github, docs/resources, README-resources.md, Core resource declarations, the shared archive-cache action, the ShouldProcess policy and every .github/workflows file; manual dispatch is also available.

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
| check | runner ubuntu-latest |  | default success condition | ./scripts/Invoke-WorkspaceChecks.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

After checkout the optional shared cache action reuses NuGet resource archives, keyed by OS and resource-lock hash. Invoke-WorkspaceChecks runs ScriptsReadme, GitHubWorkflowDocs, ScriptShouldProcess, Resources, ScriptContracts, DocsCredits and Credits. Workflow parsing independently calls Ensure-QuietResource to verify/prepare the pinned YamlDotNet payload; there is no required preceding restore step. Preparation can write only the selected resource and download cache through ShouldProcess. Checks do not Apply documentation, build, stage, commit, push or access Gallery secrets; permissions are contents:read.

## Validation and limits

A missing/stale workflow receipt, generated graph/index, script doc, credits block or new-script ShouldProcess contract fails the job. Reviewed read-only exceptions are hash-bound. The frozen legacy script inventory is explicitly unqualified for preview support; static checks do not prove runtime side-effect safety.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
