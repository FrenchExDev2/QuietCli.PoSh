# publish-psgallery.yml

<!-- workflow-source-sha256: C6A19D7C531BDE4110565BF5B5D3BF4215CBE440B1A9B4495D99B6450C55E23C -->

## Purpose

Prepare one selected package or annotated batch after exact-revision qualification and optionally publish those same verified bytes for a matching tag push. A batch shares qualification and the packaging build, validates every module first, then publishes in dependency order.

## Triggers

workflow_call accepts module (alias/full name), version, publication intent, qualified_sha and the legacy Core-only generated-preview artifact mode. workflow_dispatch accepts module/version for artifacts only. Independent tag refs have independent concurrency groups, so different module/version requests do not replace one another's pending runs.

## Qualification, preparation and publication

Current-run/current-attempt All evidence must match the exact source revision; otherwise the workflow runs All. Develop same-tree reuse cannot substitute for release evidence. Windows builds the required ReadyToRun RID/CLR distributions and validates packaging outputs before preparing the selected package or batch.

Workspace initialization validates discovered manifests and pinned external resources. Internal
sources require no committed workspace lock. Package manifests and package-set.json retain
actual source identities with available Git revision/tree and dirty state, while existing binary
and exact-revision qualification checks remain required.

Publication downloads those prepared nupkg files and verifies versions, hashes and the qualified checkpoint without rebuilding. Only a matching original-repository module-tag release with publication intent can use the protected PSGallery environment. Manual dispatch and generated-preview requests create artifacts. Batch members are validated first, then published in dependency order. Core/Git eligibility comes from manifests; tests and disabled Vagrant are excluded. See the [publication diagram](../execution-model.md#gallery-publication).

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/publish-psgallery.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_call, workflow_dispatch"]
    job_checkpoint["checkpoint"]
    job_package["package"]
    job_publish["publish"]
    job_qualification["qualification"]
    job_reuse_qualification["reuse-qualification"]
    job_qualification --> job_checkpoint
    job_reuse_qualification --> job_checkpoint
    job_checkpoint --> job_package
    job_checkpoint --> job_publish
    job_package --> job_publish
    event --> job_qualification
    event --> job_reuse_qualification
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| checkpoint | runner ubuntu-latest | qualification, reuse-qualification | <code>&#36;{{ !cancelled() &#38;&#38; (needs.qualification.result == 'success' &#124;&#124; needs.reuse-qualification.result == 'success') }}</code> |  |
| package | runner windows-latest | checkpoint | <code>&#36;{{ !cancelled() &#38;&#38; needs.checkpoint.result == 'success' &#38;&#38; needs.checkpoint.outputs.qualified&#95;sha == github.sha }}</code> | [`./scripts/Initialize-Workspace.ps1`](../../scripts/Initialize-Workspace.md), [`./scripts/Initialize-PowerShellHost.ps1`](../../scripts/Initialize-PowerShellHost.md), [`./scripts/lib/RuntimeTargets.psm1`](../../scripts/lib/RuntimeTargets.md), [`./scripts/Build-Workspace.ps1`](../../scripts/Build-Workspace.md), [`./scripts/Invoke-GitHubCi.ps1`](../../scripts/Invoke-GitHubCi.md), [`./scripts/Invoke-QuietGalleryRelease.ps1`](../../scripts/Invoke-QuietGalleryRelease.md), [`./scripts/New-QuietPreviewPackage.ps1`](../../scripts/New-QuietPreviewPackage.md), [`./scripts/New-QuietGalleryPackage.ps1`](../../scripts/New-QuietGalleryPackage.md), [`./scripts/Publish-QuietGallery.ps1`](../../scripts/Publish-QuietGallery.md), [`./scripts/Export-CiFailureDiagnostics.ps1`](../../scripts/Export-CiFailureDiagnostics.md) |
| publish | runner windows-latest | checkpoint, package | <code>&#36;{{ !cancelled() &#38;&#38; inputs.publish == true &#38;&#38; inputs.preview&#95;build != true &#38;&#38; github.repository == 'FrenchExDev2/QuietCli.PoSh' &#38;&#38; github.event&#95;name == 'push' &#38;&#38; startsWith(github.ref, 'refs/tags/FrenchExDev2.QuietCli.') &#38;&#38; needs.checkpoint.result == 'success' &#38;&#38; needs.checkpoint.outputs.qualified&#95;sha == github.sha }}</code> | [`./scripts/Initialize-PowerShellHost.ps1`](../../scripts/Initialize-PowerShellHost.md), [`./scripts/Invoke-QuietGalleryRelease.ps1`](../../scripts/Invoke-QuietGalleryRelease.md), [`./scripts/Publish-QuietGallery.ps1`](../../scripts/Publish-QuietGallery.md), [`./scripts/Get-QuietReleasePlan.ps1`](../../scripts/Get-QuietReleasePlan.md) |
| qualification | reuses ./.github/workflows/ci.yml |  | <code>inputs.qualified&#95;sha == ''</code> |  |
| reuse-qualification | runner ubuntu-latest |  | <code>inputs.qualified&#95;sha != '' &#38;&#38; inputs.qualified&#95;sha == github.sha</code> | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Assert-QualificationReceipt.ps1`](../../scripts/Assert-QualificationReceipt.md) |

<!-- workflow-generated:end -->

## Scripts and effects

Qualification requests All with collect_performance=true, or validates a downloaded current-run/current-attempt All receipt matching github.sha. The checkpoint normalizes the successful path before package/publish jobs.

The Windows packaging job follows global.json, builds verified Release ReadyToRun distributions, tests the exact packaging build and calls New-QuietGalleryPackage with the selected module. Package artifacts include module/version/SHA/attempt in their identity. Git includes its parser outputs and Core dependency; Core includes its RID/CLR payloads. Generated run/attempt preview artifacts remain Core-only and cannot publish.

The publish job requires original-repository push/tag context, explicit publication intent, no generated-preview mode and successful exact-revision qualification. It downloads the exact artifact, validates module/version/GUID/dependencies/binaries, re-resolves the tag against its owning source manifest and requires tag module/version to match the prepared plan. Only then does Publish-QuietGallery publish through the psgallery environment. Pull requests, branches, forks and manual dispatch cannot publish. No current develop HEAD lookup or automatic retry occurs.

The reusable workflow exports the exact package artifact name and the publication receipt artifact name from the job/attempt that actually published Gallery packages. The tag-only caller uses these outputs for its separate github-release job; retrying that job alone does not substitute a newer attempt number for an existing artifact. This reusable workflow keeps contents read-only, including for manual artifact callers. The tag caller's GitHub job alone requests contents:write. No build or Gallery publication is repeated.

Existing releases/drafts are refused without replacement. Interrupted uploads leave a draft and fail the GitHub job; Gallery remains published. Inspect existing remote state before retrying only the GitHub job. Partial multi-module GitHub success has no rollback. Offline lifecycle/property/malformed-response/mutation fixtures do not establish real transport or hosted artifact layout.

## Validation and limits

Local policy tests cover event boundaries and discovered targets; GalleryPreview checks independent Core/Git packages and isolated imports/handlers. The validated release_tags input routes one annotated batch through one All qualification and packaging build. Invoke-QuietGalleryRelease validates every package before publishing any, in dependency order; followers stop after planning. Standalone tags retain their own runs. Git requires a publicly visible compatible Core dependency; indexing delay remains a boundary without retry or bypass. New targets require declarations and qualification. Environment rules/keys remain external. ValidateOnly and preparation do not publish.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
