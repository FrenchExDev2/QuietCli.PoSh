# linux-images.yml

<!-- workflow-source-sha256: A40D8C5672F8DE4C7F8C800846B9C533A5B1DB12F3825BFE298678CEBD6051E2 -->

## Purpose

Provides the selected Linux image chains once per RID on native Ubuntu runners. The same producer supplies product qualification, standalone CI (including Gallery qualification), and ReadyToRun. Different suite chains reuse verified parents already present on the producer.

## Triggers

Reusable `workflow_call` from companion CI, standalone qualification or ReadyToRun.

## Scripts and effects

For test runs, the producer fingerprints the exact image recipes selected per RID. A verified Actions archive supplies a current-run receipt and cache key. On a miss, the producer supplies GHCR digests if every required image came from GHCR. It uploads an archive only after a local build. [Export-CiImageBundle](../../scripts/Export-CiImageBundle.md) prepares the handoff. A PR renewal skips all cache reads and saves a new archive key scoped to the run and attempt. Cache-only preparation checks GHCR and uploads receipts without exporting the test archive.

Trusted runs publish an image to GHCR when its fingerprint tag is missing. The workflow reuses the original restore key to save intermediate BuildKit layers after successful preparation, when the exact key missed and the local cache indexes changed.

## Validation and limits

Consumers depend on successful preparation and validate the run, revision, RID, archive hash or registry digest, suite fingerprint and loaded image. See [Linux CI images](../linux-images.md).

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
