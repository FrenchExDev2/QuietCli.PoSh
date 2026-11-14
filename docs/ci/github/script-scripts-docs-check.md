# scripts-docs-check.yml

<!-- workflow-source-sha256: 76F3925DB488AF46072D6DEDE289320B79096E51447F9D974AC243DDD25F26A0 -->

## Purpose

All .github/actions changes now trigger the shared checks, including the Docker CI intermediate-cache action. Localhost may use Podman; GitHub execution explicitly selects Docker.

Shared automation-contract pipeline for complete Core test classifications, script docs, workflow docs, resources, objectives and preview support.

## Triggers

PR/develop path filters cover scripts, all Core test-project sources, docs/scripts, docs/ci/github, docs/resources, README-resources.md, Core resource declarations, the shared archive-cache action, the ShouldProcess policy and every .github/workflows file; manual dispatch is also available.

## Checked scope

Runs the shared eight-check registry: case metadata, scripts index, workflow receipts/graphs/index, ShouldProcess policy, resources, script contracts, documentation credits and aggregate credits. Checks are read-only apart from declared consumer preparation of verified resources. They execute no product companion campaign and cannot establish hosted functional or ARM64 qualification. See [the script map](../README.md#script-map).

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

After checkout the optional shared cache action reuses NuGet resource archives, keyed by OS and resource-lock hash. Invoke-WorkspaceChecks first runs TestCaseMetadata, then ScriptsReadme, GitHubWorkflowDocs, ScriptShouldProcess, Resources, ScriptContracts, DocsCredits and Credits. The classification gate parses every Core case/metadata declaration without importing Core or running tests; omissions and malformed classifications fail, including cases excluded by a runtime filter. Workflow parsing independently calls Ensure-QuietResource to verify/prepare the pinned YamlDotNet payload; there is no required preceding restore step. Preparation can write only the selected resource and download cache through ShouldProcess. Checks do not Apply documentation, build, stage, commit, push or access Gallery secrets; permissions are contents:read.

The shared registry also enforces RAC-PS-004: Verb-Noun entry points, no functions in scripts, libraries under scripts/lib, explicit quiet imports and System.IO.Path composition. AGENTS.md and the automation contract are included in the workflow path filters.

## Validation and limits

Path filters include every FrenchExDev2.QuietCli.*.Tests.PoSh project. The shared metadata gate discovers each owning companion's manifest and local .psm1/helper declarations, including independent optional registration guards and active-case completeness. No product module or SDK is needed for these checks.

The first shared gate also parses Core.Tests manifest scheduling policy: missing declarations remain sequential, while malformed modes/caps/timeouts, orphan overrides or missing reasons fail. This read-only check loads no product engine. Core/All launchers repeat validation before their build/test effects, and runtime saves the selected plan and enforces barriers and bounded isolation.

A missing/stale workflow receipt, generated graph/index, script doc, credits block or new-script ShouldProcess contract fails the job. Reviewed read-only exceptions are hash-bound. The frozen legacy script inventory is explicitly unqualified for preview support; static checks do not prove runtime side-effect safety.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
