# preview-psgallery.yml

<!-- workflow-source-sha256: F94491A0663031F6807150A1BDD23006972566F193220EEE9BD3B57D2DADFE61 -->

## Purpose

Manual generated-preview artifacts after full qualification, without Gallery publication.

## Triggers

Manual dispatch only. Repository/ref condition rejects forks and other branches. This wrapper always supplies publish=false; branch pushes do not call it.

## Qualification and effects

Calls the shared publication/preparation workflow with publication disabled. Full exact-source qualification precedes the generated preview package; its artifact-only version does not modify source manifests or create a release tag. Local unpushed commits are outside a remotely selected ref. Required tooling includes [validated shard execution and complete aggregation](script-tooling-ci.md#shard-execution-boundary).

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

The preview job reuses publish-psgallery.yml with preview_build=true and publish=false. There is no publication input. This wrapper supplies no reusable qualification, so the manual path executes All with matrix profiling. It contains no API key and only prepares artifacts.

## Validation and limits

The reusable workflow qualifies All and validates the prepared checkpoint and bytes. A later develop head does not invalidate a previously successful checkpoint. No version is published by this wrapper; module release tag pushes use release-tags.yml.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
