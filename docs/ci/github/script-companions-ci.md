# companions-ci.yml

<!-- workflow-source-sha256: DAC2968438D84CE416CA2751A6F80E258425697FC61EFA755F9ADB8524FEF748 -->

## Purpose

One development qualification entry point for every YAML-declared companion and integration suite.

## Triggers

Pull requests and develop pushes matching `FrenchExDev2.QuietCli.*.PoSh/**` or shared automation,
build, workflow, SDK, solution, package or repository policy sources. The wildcard covers Vagrant
and future dedicated integration test projects without another per-companion workflow file.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push"]
    job_companions["companions"]
    event --> job_companions
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| companions | reuses ./.github/workflows/ci.yml |  | default success condition |  |

<!-- workflow-generated:end -->

## Scripts and effects

The companions job reuses ci.yml with suite=All and packages:write. All comes from
build/companions.yml; the generic resolver selects test runners, image layers and qualification
controls. Image publication retains the reusable workflow's explicit upstream develop guard.
The previous Core/Git-specific entry workflows are replaced by this shared entry.

## Validation and limits

This deliberately requests every declared suite. Changed-module selection, scheduling and image
cache optimization are separate future work. Local generated fixtures establish configuration
behavior, not hosted execution. Required-check names now come from this shared workflow/job;
remote branch protection is managed separately and is not modified by repository scripts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
