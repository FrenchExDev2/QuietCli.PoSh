# companions-ci.yml

<!-- workflow-source-sha256: 06E5ABB238EA24ED727026989AEB98220696C3C0FBEE72A9BC8D1BA95D9AA0DA -->

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

The All call explicitly sets collect_performance=true. Core profiling and standalone HTML/Markdown/JSON reporting cover all ten selected matrix environments; the returned qualified_sha depends on the combined performance report. Preview publication remains develop-push-only, so a PR preview skip is intentional.

The companions job reuses ci.yml with suite=All and packages:write. All comes from
build/companions.yml; the generic resolver selects test runners, image layers and qualification
controls. Image publication retains the reusable workflow's explicit upstream develop guard.
The previous Core/Git-specific entry workflows are replaced by this shared entry.

Superseded PR validations are cancelled within their PR concurrency group. Develop uses unique run groups and preserves qualification reports. There is no Gallery packaging/publication job in this caller: merging runs All with profiling and may populate the GHCR toolchain cache. Explicit module tag pushes use the separate release-tags workflow.

## Validation and limits

This deliberately requests every declared suite, preserving Core's test-only Git dependency. Core
executes before isolated parallel companions, using one build and shared image per target. Local generated fixtures establish configuration
behavior, not hosted execution. Required-check names now come from this shared workflow/job;
remote branch protection is managed separately and is not modified by repository scripts.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
