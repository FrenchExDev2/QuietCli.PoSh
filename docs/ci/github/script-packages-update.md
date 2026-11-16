# packages-update.yml

<!-- workflow-source-sha256: 210E3A1360EA9E1CAF7CC9A5BF7990044F3AB34D1B550003833D5FB2110987A1 -->

## Purpose

Report, per package and target framework, which Directory.Packages.props pins have a newer nuget.org version compatible with that framework, honoring CPM conditions; on explicit request, write those versions, check them with dotnet restore, then commit/push.

## Triggers

Manual workflow_dispatch only, with two boolean inputs: `apply` (default false) and `prerelease` (default false). No automatic PR/push trigger.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_dispatch"]
    job_apply["apply"]
    job_report["report"]
    job_report --> job_apply
    event --> job_report
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| apply | runner ubuntu-latest | report | ${{ inputs.apply }} | ./scripts/Update-Packages.ps1 |
| report | runner ubuntu-latest |  | default success condition | ./scripts/Update-Packages.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

The report job always runs `./scripts/Update-Packages.ps1 -WhatIf` (plus `-IncludePrerelease` when `prerelease` is true) with contents:read and no persisted credentials. It prints one row per package x framework in the log, appends the same table to the job summary and writes nothing. The apply job runs only when `apply` is true, after the report job: `./scripts/Update-Packages.ps1 -Apply -Confirm:$false` writes the compatible versions, runs dotnet restore on the referencing projects and restores the original file (failing the job) on NU1202 or any other restore error. The final bot step stages Directory.Packages.props only, commits if it changed and pushes to the dispatched branch using contents:write and persisted credentials. See [Update-Packages.psm1](../../scripts/lib/Update-Packages.md) for the resolution rules.

## Validation and limits

The report job succeeds even when some rows show `eval error`, `fetch error` or `lookup error`; read the log or the summary. Only nuget.org is consulted, so private feeds are not covered. The apply job recomputes the proposals on its own checkout, so a package published between the two jobs can be applied without having been shown in the report. The restore check covers restore compatibility, not a build or tests: run the CI workflow on the pushed commit. A no-change dispatch creates no commit.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
