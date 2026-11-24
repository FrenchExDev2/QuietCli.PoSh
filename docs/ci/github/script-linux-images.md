# linux-images.yml

<!-- workflow-source-sha256: 517E2CCF7397C43E11774047A33D3CF6A766BA670111423C2CFAF5F632DA1C5A -->

## Purpose

Provides the selected Linux image chains once per RID on native Ubuntu runners. The same producer supplies product qualification, standalone CI (including Gallery qualification), and ReadyToRun. Different suite chains reuse verified parents already present on the producer.

## Triggers

Reusable `workflow_call` from companion CI, standalone qualification or ReadyToRun.

## Scripts and effects

For test runs, the producer fingerprints the exact image recipes selected per RID and restores the final archive with an exact GitHub Actions cache key. On a hit it verifies the receipt and archive SHA-256, then binds the receipt to the current run. On a miss it starts Docker and resolves or builds the required images. The producer saves a new archive to the Actions cache only when it built a required image. Both paths upload a current-run bundle using [Export-CiImageBundle](../../scripts/Export-CiImageBundle.md). Failed consumers can reuse the same-run artifact on rerun. Cache-only preparation checks GHCR and uploads receipts without exporting the test archive.

Trusted runs publish an image to GHCR when its fingerprint tag is missing. The workflow reuses the original restore key to save intermediate BuildKit layers after successful preparation, when the exact key missed and the local cache indexes changed.

## Validation and limits

Consumers depend on successful preparation and validate the run, revision, RID, archive hash, suite fingerprint and loaded image. See [Linux CI images](../linux-images.md).

<!-- workflow-generated:begin -->

[Workflow source](../../../.github/workflows/linux-images.yml)

## Jobs and dependencies

Generated from the workflow by Sync-GitHubWorkflowsReadme.ps1. Conditions can skip jobs; edges express declared needs.

~~~mermaid
flowchart TD
    event["Triggers: workflow_call"]
    job_prepare["prepare"]
    event --> job_prepare
~~~

| Job | Execution | Needs | Condition | Script entry points |
| --- | --- | --- | --- | --- |
| prepare | <code>runner &#36;{{ matrix.runner }}</code> |  | default success condition | [`./scripts/Initialize-CiEnvironment.ps1`](../../scripts/Initialize-CiEnvironment.md), [`./scripts/Export-CiImageBundle.ps1`](../../scripts/Export-CiImageBundle.md), [`./scripts/New-CiSuiteImage.ps1`](../../scripts/New-CiSuiteImage.md) |

<!-- workflow-generated:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
