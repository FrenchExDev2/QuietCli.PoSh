# release-tags.yml

<!-- workflow-source-sha256: 7F68B3EC1D35E444510608D010F02375DB6EB2E4C4D6B330BDC5088DF95B3F5B -->

## Purpose

Explicit independently versioned business-module releases. Core and Git are enabled by their existing manifests; Vagrant remains disabled. Test modules are never release targets.

## Triggers

Push tags matching FrenchExDev2.QuietCli.*.PoSh/v*. The wildcard supplies routing, not permission: the plan discovers the exact owner and requires its publication flag/version. No branch, PR or manual trigger. Only the original repository runs the plan.

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

Get-QuietReleasePlan derives module/component/version from existing workspace manifests and the script-module identity reader. Invalid, mismatching, disabled and test targets fail before qualification. The release job passes the exact module and version to publish-psgallery, which runs full All qualification with profiling, verifies the packaging build and publishes one selected immutable package after tag/package validation.

Operator-generated tags are collision-checked locally/remotely before edits, never forced, and only selected refs are pushed. Separate module tags start independent workflows; a compatible Core dependency must already be available for Git publication. This workflow does not create GitHub Releases or order independent public dependency releases.

## Validation and limits

Local tests cover dynamic targets, numeric previews, exact versions, disabled targets, local/remote collisions, no-write previews and private bare-remote pushes. GalleryPreview validates Core/Git packages and isolated imports. Hosted execution and actual Gallery availability remain separate evidence. Configure the psgallery environment to allow release tags for both enabled package namespaces (or the reviewed common FrenchExDev2.QuietCli.*.PoSh/v* pattern). Existing approval protections and PSGALLERY_API_KEY stay in that environment.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
