# publish-psgallery.yml

<!-- workflow-source-sha256: F3258417C4A3941AF794C1BDFFE90AA106CD4C59DF716DE9E3D2F7D0629192BC -->

## Purpose

Prepare one verified public QuietCli nupkg, then optionally publish those exact bytes to PSGallery.

## Triggers

workflow_call accepts exact version, publish intent and artifact-only preview_build; workflow_dispatch accepts an exact version for artifacts only. Public publication is requested by release-tags.yml for a matching tag push and enforced again by job conditions and tag validation.


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
| publish | runner windows-latest | checkpoint, package | ${{ !cancelled() && inputs.publish == true && inputs.preview_build != true && github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.event_name == 'push' && startsWith(github.ref, 'refs/tags/QuietCli/v') && needs.checkpoint.result == 'success' && needs.checkpoint.outputs.qualified_sha == github.sha }} | ./scripts/Get-QuietReleasePlan.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Publish-QuietGallery.ps1 |
| qualification | reuses ./.github/workflows/ci.yml |  | inputs.qualified_sha == '' |  |
| reuse-qualification | runner ubuntu-latest |  | inputs.qualified_sha != '' && inputs.qualified_sha == github.sha | ./scripts/Assert-QualificationReceipt.ps1, ./scripts/Initialize-CiEnvironment.ps1 |

<!-- workflow-generated:end -->

## Scripts and effects

Fresh All qualification explicitly requests collect_performance=true. Reused current-run receipts must include successful required matrix performance evidence; an older/unprofiled receipt cannot bypass the report gate.

The optional workflow-call qualified_sha input is accepted only with a downloaded All receipt from this exact run, attempt and revision. Assert-QualificationReceipt rejects mismatches before emitting an output. Without it, qualification still calls ci.yml(All). The checkpoint job normalizes the successful path; package/publish explicitly override skipped-ancestor propagation while requiring that successful exact-SHA checkpoint. The caller's SHA alone never authorizes packaging. Resource/host archives and NuGet are cached with their full lock inputs, and all existing exact-package and psgallery environment checks remain required.

The package preparation job uses the shared optional archive cache before Initialize-Workspace. The cache key includes OS and resource-lock hash; resource hashes are verified independently. Publication consumes the exact prepared artifact without querying current develop HEAD. The publish job requires an original-repository push under refs/tags/QuietCli/v, publish=true, preview_build=false and successful exact-revision qualification. Manual dispatch and branch pushes cannot publish, including through reusable callers. Get-QuietReleasePlan validates the tag against the checked-out source manifest again and requires its version to equal the downloaded package version before the secret-bearing publication step.

The Windows x64 package job checks out the accepted checkpoint revision, builds Release ReadyToRun for six RIDs and CLR 10/11, verifies All, and prepares a package with RequireReadyToRun. Publication downloads the artifact, validates its SHA/version/checkpoint and uses Publish-PSResource -NupkgPath. Only the publish job receives PSGALLERY_API_KEY from the psgallery environment. Failure diagnostics are redacted and retained separately.

## Validation and limits

One public Core nupkg embeds every RID; Git and Vagrant remain nonpublishable. Packaging rebuilds from the qualified source, rather than merging matrix binaries. Both stable and prerelease publication require a module-specific tag push matching the full source manifest version. The generated-preview path and workflow dispatch are artifact-only. The psgallery environment must allow the QuietCli/v* tag namespace; no repository setting is changed by these files. Pull requests cannot reach the public publication job. ValidateOnly performs no public publication.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
