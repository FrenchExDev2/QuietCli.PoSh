# preview-psgallery.yml

<!-- workflow-source-sha256: 0FD7BFBF40052BA89480836750AF7070CA6081F92452120DE86609339C7C09F4 -->

## Purpose

Manual uniquely versioned develop prerelease delivery through qualified Gallery publication.

## Triggers

Manual dispatch only, defaulting publish=false. Repository/ref condition rejects forks and other branches. Automatic develop delivery belongs to companions-ci.yml after its All qualification, preventing a duplicate matrix.

<!-- workflow-generated:begin -->
## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_dispatch"]
    job_preview["preview"]
    event --> job_preview
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| preview | reuses ./.github/workflows/publish-psgallery.yml |  | ${{ github.repository == 'FrenchExDev2/QuietCli.PoSh' && github.ref == 'refs/heads/develop' }} |  |

<!-- workflow-generated:end -->

## Scripts and effects

The preview job reuses publish-psgallery.yml with preview_build=true. Dispatch publishes only when its boolean input is true. This wrapper supplies no reusable qualification, so the manual path executes All. It contains no API key and does not publish directly.

## Validation and limits

The reusable workflow qualifies All and validates the prepared checkpoint and bytes. A later develop head does not invalidate a previously successful checkpoint. Stable versions are not published by this wrapper.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
