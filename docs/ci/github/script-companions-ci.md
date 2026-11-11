# companions-ci.yml

<!-- workflow-source-sha256: B6C17ED39E0A302CDE6D7A154F548BC68B6A3F5771175C1BD1C1C62AA3E6514D -->

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
    job_preview["preview"]
    event --> job_companions
    job_companions --> job_preview
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| companions | reuses ./.github/workflows/ci.yml |  | default success condition |  |
| preview | reuses ./.github/workflows/publish-psgallery.yml | companions | github.event_name == 'push' && github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' && needs.companions.outputs.qualified_sha == github.sha |  |

<!-- workflow-generated:end -->

## Scripts and effects

The companions job reuses ci.yml with suite=All and packages:write. All comes from
build/companions.yml; the generic resolver selects test runners, image layers and qualification
controls. Image publication retains the reusable workflow's explicit upstream develop guard.
The previous Core/Git-specific entry workflows are replaced by this shared entry.

Superseded PR validations are cancelled within their PR concurrency group. Develop uses unique run groups and preserves qualified checkpoints. The preview job depends on the successful All output for this SHA and calls publication with that output; publication requires the same-run/same-attempt receipt instead of starting another matrix. This is the sole automatic develop preview trigger; the preview wrapper is manual only.

## Validation and limits

This deliberately requests every declared suite, preserving Core's test-only Git dependency. Core
executes before isolated parallel companions, using one build and shared image per target. Local generated fixtures establish configuration
behavior, not hosted execution. Required-check names now come from this shared workflow/job;
remote branch protection is managed separately and is not modified by repository scripts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
