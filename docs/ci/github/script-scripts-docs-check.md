# scripts-docs-check.yml

<!-- workflow-source-sha256: 43EBA931767F844ECA4073CA14ADDEB6D25C28578E9A3780E1D81DF57D9B5E40 -->

## Purpose

All .github/actions changes now trigger the shared checks, including the Docker CI intermediate-cache action. Localhost may use Podman; GitHub execution explicitly selects Docker.

Shared automation-contract pipeline for Core test classifications, script docs, workflow docs, resources, objectives and preview support. The `diagrams` job regenerates the navigable Mermaid map, uploads it and checks the tracked copy.

## Triggers

Pull requests and pushes to `develop` use the same path filters. They cover `scripts/`, `test/scripts/`, the workflow guide, generated map and resource guide, workflow and local action YAML, and the other documentation and automation inputs declared in the workflow. Manual dispatch is also available.

## Checked scope

Runs the shared check registry of [Invoke-WorkspaceChecks](../../scripts/Invoke-WorkspaceChecks.md), from workspace solutions and companion workflows to ScriptAnalyzer, the scripts inventory, resources, script contracts and credits. Checks are read-only apart from declared consumer preparation of verified resources, the pinned test tools and the ignored `.cache/script-analysis` documents. They execute no product companion campaign and cannot establish hosted functional or ARM64 qualification. See [the script map](../README.md#script-map).

<!-- grouped-layout-review:begin -->
## Grouped source layout

Reviewed module/test paths use src/<group>/src and src/<group>/test. Module identities, source-bound integrity checks, current-run qualification requirements and publication boundaries remain unchanged. See [the companion layout contract](../../README-companion-layout-and-ci.md).
<!-- grouped-layout-review:end -->

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/scripts-docs-check.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: pull_request, push, workflow_dispatch"]
    job_check["check"]
    job_diagrams["diagrams"]
    event --> job_check
    event --> job_diagrams
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| check | runner ubuntu-latest |  | default success condition | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md) |
| diagrams | runner ubuntu-latest |  | default success condition | [`./scripts/Export-GitHubWorkflowMap.ps1`](../../scripts/Export-GitHubWorkflowMap.md) |

<!-- workflow-generated:end -->

## Scripts and effects

After checkout three caches are restored:

- `cache-resources` reuses the NuGet resource archives, keyed by OS and resource-lock hash;
- `cache-test-tools` reuses the pinned Pester and PSScriptAnalyzer archives, keyed by OS and the hash of `scripts/lib/RunToolCache.psm1`. [Initialize-TestTools](../../scripts/Initialize-TestTools.md) re-verifies each SHA-256 before extracting;
- `.cache/script-analysis/*.json` holds the per-file ScriptAnalyzer findings. A new cache is saved for each run attempt, and the newest one is restored by prefix. Each document is keyed by file path, file SHA-256 and analyzer configuration, so an older cache only costs a re-analysis of the edited files, never a stale finding.

The checks then run in registry order, including [Test-ScriptAnalysis](../../scripts/Test-ScriptAnalysis.md) and the scripts inventory ratchet. The classification gate parses every Core case/metadata declaration without importing Core or running tests; omissions and malformed classifications fail, including cases excluded by a runtime filter. Workflow parsing independently calls Ensure-QuietResource to verify/prepare the pinned YamlDotNet payload; there is no required preceding restore step. Preparation can write only the selected resource and download cache through ShouldProcess. Checks do not Apply documentation, build, stage, commit, push or access Gallery secrets; permissions are contents:read.

The shared registry also enforces RAC-PS-004: Verb-Noun entry points, no functions in scripts, libraries under scripts/lib, explicit quiet imports and System.IO.Path composition. AGENTS.md and the automation contract are included in the workflow path filters.

The `diagrams` job restores the resource cache and runs the exporter against the checked-out workflow and action YAML. It writes `docs/README-github-workflows-diagrams.md` in the job checkout and uploads it as `github-workflows-diagrams`. The job fails when the newly generated file differs from the checked-in copy or the copy was missing. [Exporter documentation](../../scripts/Export-GitHubWorkflowMap.md)

## Validation and limits

Path filters include every FrenchExDev2.QuietCli.*.Tests.PoSh project. The shared metadata gate discovers each owning companion's manifest and local .psm1/helper declarations, including independent optional registration guards and active-case completeness. No product module or SDK is needed for these checks.

The first shared gate also parses Core.Tests manifest scheduling policy: missing declarations remain sequential, while malformed modes/caps/timeouts, orphan overrides or missing reasons fail. This read-only check loads no product engine. Core/All launchers repeat validation before their build/test effects, and runtime saves the selected plan and enforces barriers and bounded isolation.

A missing/stale workflow receipt, generated graph/index, script doc, credits block or new-script ShouldProcess contract fails the job. Reviewed read-only exceptions are hash-bound. The frozen legacy script inventory is explicitly unqualified for preview support; static checks do not prove runtime side-effect safety.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
