# publish-psgallery.yml

<!-- workflow-source-sha256: 1EB6069ACFCD5C56704E16030C633938849CC578D32BB1F34359AE21878F61B7 -->

## Purpose

Prepare one verified public QuietCli nupkg, then optionally publish those exact bytes to PSGallery.

## Triggers

workflow_call and workflow_dispatch. Version, publish and preview_build inputs control stable/manual or reusable preview delivery; job-level conditions enforce qualification and publication scope.


## .NET SDK source pin

The reviewed setup-dotnet steps read the checked-out global.json through global-json-file, so the CI, publication preparation and manual ReadyToRun jobs follow the selected SDK instead of embedding an old RC string. This source review does not establish hosted execution or full matrix qualification.

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
| package | runner windows-latest | checkpoint | ${{ !cancelled() && needs.checkpoint.result == 'success' && needs.checkpoint.outputs.qualified_sha == github.sha }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-QuietGalleryPackage.ps1, ./scripts/New-QuietPreviewPackage.ps1, ./scripts/Publish-QuietGallery.ps1, ./scripts/RuntimeTargets.ps1 |
| publish | runner windows-latest | checkpoint, package | ${{ !cancelled() && inputs.publish == true && github.repository == 'FrenchExDev2/QuietCli.PoSh' && (github.event_name == 'push' &#124;&#124; github.event_name == 'workflow_dispatch') && github.event.pull_request.draft != true && needs.checkpoint.result == 'success' && needs.checkpoint.outputs.qualified_sha == github.sha }} | ./scripts/Assert-GalleryCheckpoint.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Publish-QuietGallery.ps1 |
| qualification | reuses ./.github/workflows/ci.yml |  | inputs.qualified_sha == '' |  |
| reuse-qualification | runner ubuntu-latest |  | inputs.qualified_sha != '' && inputs.qualified_sha == github.sha | ./scripts/Assert-QualificationReceipt.ps1, ./scripts/Initialize-CiEnvironment.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

The optional workflow-call qualified_sha input is accepted only with a downloaded All receipt from this exact run, attempt and revision. Assert-QualificationReceipt rejects mismatches before emitting an output. Without it, qualification still calls ci.yml(All). The checkpoint job normalizes the successful path; package/publish explicitly override skipped-ancestor propagation while requiring that successful exact-SHA checkpoint. The caller's SHA alone never authorizes packaging. Resource/host archives and NuGet are cached with their full lock inputs, and all existing exact-package and psgallery environment checks remain required.

The package preparation job uses the shared optional archive cache before Initialize-Workspace. The cache key includes OS and resource-lock hash; resource hashes are verified independently. Publication still consumes the exact prepared artifact and has no dependency on a current develop HEAD check. The publish job accepts only push or workflow_dispatch events and explicitly rejects draft pull-request payloads, including when this reusable workflow is called from another workflow.

The Windows x64 package job checks out the accepted checkpoint revision, builds Release ReadyToRun for six RIDs and CLR 10/11, verifies All, and prepares a package with RequireReadyToRun. Publication downloads the artifact, validates its SHA/version/checkpoint and uses Publish-PSResource -NupkgPath. Only the publish job receives PSGALLERY_API_KEY from the psgallery environment. Failure diagnostics are redacted and retained separately.

## Validation and limits

One public Core nupkg embeds every RID; Git stays internal. Packaging rebuilds from the qualified source, rather than merging matrix binaries. Automatic previews require develop but never compare its current remote HEAD to the checkpoint. Pull requests, including drafts, cannot reach the public publication job. ValidateOnly performs no public publication; stable publication remains explicit.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
