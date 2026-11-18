# scripts-docs-check.yml

<!-- workflow-source-sha256: 05E5BCF3617BFD9869CF4FADACCE101467CF14532FC0179E3AF60990EC623E8B -->

## Purpose

All .github/actions changes now trigger the shared checks, including the Docker CI intermediate-cache action. Localhost may use Podman; GitHub execution explicitly selects Docker.

Shared automation-contract pipeline for complete Core test classifications, script docs, workflow docs, resources, objectives and preview support.

## Triggers

PR/develop path filters cover scripts, test/scripts, all Core test-project sources, docs/scripts, docs/ci/github, docs/resources, README-resources.md, Core resource declarations, every shared action, the ShouldProcess policy and every .github/workflows file; manual dispatch is also available.

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
    event --> job_check
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| check | runner ubuntu-latest |  | default success condition | [`./scripts/Invoke-WorkspaceChecks.ps1`](../../scripts/Invoke-WorkspaceChecks.md) |

<!-- workflow-generated:end -->

## Scripts and effects

After checkout three caches are restored:

- `cache-resources` reuses the NuGet resource archives, keyed by OS and resource-lock hash;
- `cache-test-tools` reuses the pinned Pester and PSScriptAnalyzer archives, keyed by OS and the hash of `scripts/lib/RunToolCache.psm1`. [Initialize-TestTools](../../scripts/Initialize-TestTools.md) re-verifies each SHA-256 before extracting;
- `.cache/script-analysis/*.json` holds the per-file ScriptAnalyzer findings. A new cache is saved for each run attempt, and the newest one is restored by prefix. Each document is keyed by file path, file SHA-256 and analyzer configuration, so an older cache only costs a re-analysis of the edited files, never a stale finding.

The checks then run in registry order, including [Test-ScriptAnalysis](../../scripts/Test-ScriptAnalysis.md) and the scripts inventory ratchet. The classification gate parses every Core case/metadata declaration without importing Core or running tests; omissions and malformed classifications fail, including cases excluded by a runtime filter. Workflow parsing independently calls Ensure-QuietResource to verify/prepare the pinned YamlDotNet payload; there is no required preceding restore step. Preparation can write only the selected resource and download cache through ShouldProcess. Checks do not Apply documentation, build, stage, commit, push or access Gallery secrets; permissions are contents:read.

The shared registry also enforces RAC-PS-004: Verb-Noun entry points, no functions in scripts, libraries under scripts/lib, explicit quiet imports and System.IO.Path composition. AGENTS.md and the automation contract are included in the workflow path filters.

## Validation and limits

Path filters include every FrenchExDev2.QuietCli.*.Tests.PoSh project. The shared metadata gate discovers each owning companion's manifest and local .psm1/helper declarations, including independent optional registration guards and active-case completeness. No product module or SDK is needed for these checks.

The first shared gate also parses Core.Tests manifest scheduling policy: missing declarations remain sequential, while malformed modes/caps/timeouts, orphan overrides or missing reasons fail. This read-only check loads no product engine. Core/All launchers repeat validation before their build/test effects, and runtime saves the selected plan and enforces barriers and bounded isolation.

A missing/stale workflow receipt, generated graph/index, script doc, credits block or new-script ShouldProcess contract fails the job. Reviewed read-only exceptions are hash-bound. The frozen legacy script inventory is explicitly unqualified for preview support; static checks do not prove runtime side-effect safety.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
