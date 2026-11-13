# release-tags.yml

<!-- workflow-source-sha256: 8B852700266BB22A04239FF3625C671B066BEAC8B558943706E14AA6F691087D -->

## Purpose

Explicit independently versioned business-module releases. Core and Git are enabled by their existing manifests; Vagrant remains disabled. Test modules are never release targets.

Run titles include the triggering module tag. Multiple operator-created tags may produce multiple visible planning runs, but only the batch leader starts the expensive release matrix and packaging build.

## Triggers

Push tags matching FrenchExDev2.QuietCli.*.PoSh/v*. The wildcard supplies routing, not permission: the plan discovers the exact owner and requires its publication flag/version. No branch, PR or manual trigger. Only the original repository runs the plan.

## Release routing

The plan validates tag owner/version/publication eligibility and annotated batch membership. A batch leader shares one All qualification and one packaging build; other tag planning runs do not each repeat the expensive matrix. Prepared packages are published in dependency order after validation. Branch/PR/cache-only evidence cannot authorize this path. See [publication boundaries](../execution-model.md#gallery-publication) and [source-change landmarks](../README.md#source-change-landmarks).

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: push"]
    job_github_release["github-release"]
    job_plan["plan"]
    job_release["release"]
    job_plan --> job_github_release
    job_release --> job_github_release
    event --> job_plan
    job_plan --> job_release
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| github-release | runner ubuntu-latest | plan, release | needs.release.result == 'success' && needs.plan.outputs.is_leader == 'true' | ./scripts/Initialize-CiEnvironment.ps1, ./scripts/Publish-QuietGitHubRelease.ps1 |
| plan | runner ubuntu-latest |  | github.repository == 'FrenchExDev2/QuietCli.PoSh' | ./scripts/Get-QuietReleasePlan.ps1 |
| release | reuses ./.github/workflows/publish-psgallery.yml | plan | needs.plan.outputs.is_leader == 'true' |  |

<!-- workflow-generated:end -->

## Scripts and effects

Get-QuietReleasePlan derives module/component/version from existing workspace manifests and the script-module identity reader. Invalid, mismatching, disabled and test targets fail before qualification. The release job passes the exact module and version to publish-psgallery, which runs full All qualification with profiling, verifies the packaging build and publishes one selected immutable package after tag/package validation.

Operator-created annotations declare one batch and exact commit. Every tag run verifies all remote members and their manifest versions, but only its dependency-ordered leader starts qualification and packaging. The leader publishes Core before selected companions through Invoke-QuietGalleryRelease. Followers stop after planning; standalone/manual tags without batch annotations retain independent runs. Collision checks and the no-force policy remain. Git still requires a publicly visible compatible Core dependency; indexing delay can reject Git.

After the entire called Gallery workflow succeeds, github-release runs only for the batch leader. It downloads the exact package and publication-receipt artifact names exported by that workflow, retaining the publishing attempt's identity on a GitHub-only retry. Publish-QuietGitHubRelease checks all local packages and successful Gallery receipts, original repository/push/tag/SHA context and each remote tag's peeled commit. Drafts receive the unchanged nupkg, package-set.json and publication.json; uploaded sizes/SHA-256 are checked before publishing. Preview versions become prereleases and make_latest=false preserves the global latest pointer. Only this separate job requests contents:write with github.token; the called reusable workflow, packaging and Gallery jobs keep contents read-only. The Gallery key is unavailable here. Manual artifact workflows never invoke this tag-only path.

Existing drafts/releases are refused without deletion or replacement. Interrupted uploads leave a draft for deliberate recovery. Partial batch GitHub success has no rollback; Gallery publication is already complete. Inspect remote state before retrying only this job, without repeating Gallery publication. Offline lifecycle/property/malformed-response/mutation fixtures do not establish actual hosted transport or artifact extraction.

## Validation and limits

Local tests cover dynamic targets, numeric previews, exact versions, disabled targets, local/remote collisions, no-write previews and private bare-remote pushes. GalleryPreview validates Core/Git packages and isolated imports. Hosted execution and actual Gallery availability remain separate evidence. Configure the psgallery environment to allow release tags for both enabled package namespaces (or the reviewed common FrenchExDev2.QuietCli.*.PoSh/v* pattern). Existing approval protections and PSGALLERY_API_KEY stay in that environment.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
