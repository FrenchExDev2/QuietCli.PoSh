# publish-psgallery.yml

<!-- workflow-source-sha256: 97D3F9EDA59B647228C15474FF247BCD03EE30EF4AB67A3A5B95D5055B1BEAD5 -->

## Purpose

Prepare one selected package or annotated batch after exact-revision qualification and optionally publish those same verified bytes for a matching tag push. A batch shares qualification and the packaging build, validates every module first, then publishes in dependency order.

## Triggers

workflow_call accepts module (alias/full name), version, publication intent, qualified_sha and the legacy Core-only generated-preview artifact mode. workflow_dispatch accepts module/version for artifacts only. Independent tag refs have independent concurrency groups, so different module/version requests do not replace one another's pending runs.

<!-- workflow-generated:begin -->
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
| checkpoint | runner ubuntu-latest | qualification, reuse-qualification | ${{ !cancelled() && (needs.qualification.result == 'success' &#124;&#124; needs.reuse-qualification.result == 'success') }} |  |
| package | runner windows-latest | checkpoint | ${{ !cancelled() && needs.checkpoint.result == 'success' && needs.checkpoint.outputs.qualified_sha == github.sha }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/Invoke-QuietGalleryRelease.ps1, ./scripts/New-QuietGalleryPackage.ps1, ./scripts/New-QuietPreviewPackage.ps1, ./scripts/Publish-QuietGallery.ps1, ./scripts/RuntimeTargets.ps1 |
| publish | runner windows-latest | checkpoint, package | ${{ !cancelled() && inputs.publish == true && inputs.preview_build != true && github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.event_name == 'push' && startsWith(github.ref, 'refs/tags/FrenchExDev2.QuietCli.') && needs.checkpoint.result == 'success' && needs.checkpoint.outputs.qualified_sha == github.sha }} | ./scripts/Get-QuietReleasePlan.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Invoke-QuietGalleryRelease.ps1, ./scripts/Publish-QuietGallery.ps1 |
| qualification | reuses ./.github/workflows/ci.yml |  | inputs.qualified_sha == '' |  |
| reuse-qualification | runner ubuntu-latest |  | inputs.qualified_sha != '' && inputs.qualified_sha == github.sha | ./scripts/Assert-QualificationReceipt.ps1, ./scripts/Initialize-CiEnvironment.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

Qualification requests All with collect_performance=true, or validates a downloaded current-run/current-attempt All receipt matching github.sha. The checkpoint normalizes the successful path before package/publish jobs.

The Windows packaging job follows global.json, builds verified Release ReadyToRun distributions, tests the exact packaging build and calls New-QuietGalleryPackage with the selected module. Package artifacts include module/version/SHA/attempt in their identity. Git includes its parser outputs and Core dependency; Core includes its RID/CLR payloads. Generated run/attempt preview artifacts remain Core-only and cannot publish.

The publish job requires original-repository push/tag context, explicit publication intent, no generated-preview mode and successful exact-revision qualification. It downloads the exact artifact, validates module/version/GUID/dependencies/binaries, re-resolves the tag against its owning source manifest and requires tag module/version to match the prepared plan. Only then does Publish-QuietGallery publish through the psgallery environment. Pull requests, branches, forks and manual dispatch cannot publish. No current develop HEAD lookup or automatic retry occurs.

## Validation and limits

Local policy tests cover event boundaries and discovered targets; GalleryPreview checks independent Core/Git packages and isolated imports/handlers. The validated release_tags input routes one annotated batch through one All qualification and packaging build. Invoke-QuietGalleryRelease validates every package before publishing any, in dependency order; followers stop after planning. Standalone tags retain their own runs. Git requires a publicly visible compatible Core dependency; indexing delay remains a boundary without retry or bypass. New targets require declarations and qualification. Environment rules/keys remain external. ValidateOnly and preparation do not publish.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
