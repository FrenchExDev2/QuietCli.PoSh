# preview-psgallery.yml

<!-- workflow-source-sha256: 5EA64B3770964382509380E1D5408E8F0384CD48CC6D887853EA803674FC3DA5 -->

## Purpose

Automatic uniquely versioned develop prerelease delivery through qualified Gallery publication.

## Triggers

Applicable develop pushes matching the declared Core/scripts/build/SDK/lock/workflow paths. Manual dispatch defaults publish=false. Repository/ref condition rejects forks and other branches.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: push, workflow_dispatch"]
    job_preview["preview"]
    event --> job_preview
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| preview | reuses ./.github/workflows/publish-psgallery.yml |  | ${{ github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' }} |  |

<!-- workflow-generated:end -->

## Scripts and effects

The preview job reuses publish-psgallery.yml with preview_build=true. Push publishes after qualification; manual dispatch publishes only when its boolean input is true. This wrapper contains no API key and does not publish directly.

## Validation and limits

The reusable workflow qualifies All and validates the prepared checkpoint and bytes. A later develop head does not invalidate a previously successful checkpoint. Stable versions are not published by this wrapper.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
