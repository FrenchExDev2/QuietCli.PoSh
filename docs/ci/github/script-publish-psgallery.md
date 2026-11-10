# publish-psgallery.yml

<!-- workflow-source-sha256: A68C81690128BEEDA9DBC4BADEF7DDC5F01D00343D2F1E319DE86D37B9914D9E -->

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
    job_package["package"]
    job_publish["publish"]
    job_qualification["qualification"]
    job_qualification --> job_package
    job_qualification --> job_publish
    job_package --> job_publish
    event --> job_qualification
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| package | runner windows-latest | qualification | ${{ needs.qualification.result == 'success' && needs.qualification.outputs.qualified_sha == github.sha }} | ./scripts/Build-Workspace.ps1, ./scripts/Export-CiFailureDiagnostics.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Initialize-Workspace.ps1, ./scripts/Invoke-GitHubCi.ps1, ./scripts/New-QuietGalleryPackage.ps1, ./scripts/New-QuietPreviewPackage.ps1, ./scripts/Publish-QuietGallery.ps1, ./scripts/RuntimeTargets.ps1 |
| publish | runner windows-latest | qualification, package | ${{ inputs.publish == true && github.repository == 'FrenchExDev2/QuietCli.PoSh' && needs.qualification.result == 'success' && needs.qualification.outputs.qualified_sha == github.sha }} | ./scripts/Assert-GalleryCheckpoint.ps1, ./scripts/Initialize-PowerShellHost.ps1, ./scripts/Publish-QuietGallery.ps1 |
| qualification | reuses ./.github/workflows/ci.yml |  | default success condition |  |

<!-- workflow-generated:end -->

## Scripts and effects

The package preparation job uses the shared optional archive cache before Initialize-Workspace. The cache key includes OS and resource-lock hash; resource hashes are verified independently. Publication still consumes the exact prepared artifact and has no dependency on a current develop HEAD check.

qualification reuses ci.yml with All. The Windows x64 package job checks out the qualified revision, builds Release ReadyToRun for six RIDs and CLR 10/11, verifies All, and prepares a package with RequireReadyToRun. Publication downloads the artifact, validates its SHA/version/checkpoint and uses Publish-PSResource -NupkgPath. Only the publish job receives PSGALLERY_API_KEY from the psgallery environment. Failure diagnostics are redacted and retained separately.

## Validation and limits

One public Core nupkg embeds every RID; Git stays internal. Packaging rebuilds from the qualified source, rather than merging matrix binaries. Automatic previews require develop but never compare its current remote HEAD to the checkpoint. ValidateOnly performs no public publication; stable publication remains explicit.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
