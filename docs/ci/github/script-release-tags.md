# release-tags.yml

<!-- workflow-source-sha256: 77A8295E92B181AE1924FA9DEBEA3D5B05658CCE05E8A8D39DC5F6EFB27CE9B2 -->

## Purpose

Explicit, independently versioned module release requests. Core publication is available; Git and Vagrant namespaces remain reserved behind their existing publication capability boundaries.

## Triggers

Tag pushes matching `FrenchExDev2.QuietCli.Core.PoSh/v*`, `FrenchExDev2.QuietCli.Git.PoSh/v*` or `FrenchExDev2.QuietCli.Vagrant.PoSh/v*`. No branch push, PR or manual dispatch trigger. Only the original repository runs the plan. Pushing a tag requests publication; creating a local tag does not.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: push"]
    job_plan["plan"]
    job_release["release"]
    event --> job_plan
    job_plan --> job_release
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| plan | runner ubuntu-latest |  | github.repository == 'FrenchExDev2/QuietCli.PoSh' | ./scripts/Get-QuietReleasePlan.ps1 |
| release | reuses ./.github/workflows/publish-psgallery.yml | plan | default success condition |  |

<!-- workflow-generated:end -->

## Scripts and effects

`Get-QuietReleasePlan.ps1` validates the exact tag against its owning manifest and public packaging capability before emitting the version. Invalid and currently unavailable companion tags fail before the expensive qualification workflow. Successful plans invoke `publish-psgallery.yml` with the exact version and publication intent. That workflow runs full All qualification with matrix profiling, rebuilds and checks the packaging build, uploads immutable prepared bytes, revalidates the tag/package identity and publishes through the `psgallery` environment.

## Validation and limits

Local tests check malformed tags, independent manifest versions, blocked companions, no-write preview and publication event boundaries. Hosted qualification/publication is separate evidence. This workflow does not create GitHub Releases or push tags. It does not modify environment policies: configure a **tag** deployment rule matching `FrenchExDev2.QuietCli.Core.PoSh/v*` and retain `PSGALLERY_API_KEY` in that environment. Existing approval protections still apply. Legacy `v<version>-preview<timestamp>` tags remain outside the release filters.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
