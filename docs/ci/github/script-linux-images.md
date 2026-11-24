# linux-images.yml

<!-- workflow-source-sha256: 2D2B8B0C34BBCF239485AE0FBED888DBC4E929423F5D4CCE8EC02B7789827BDD -->

## Purpose

Provides the selected Linux image chains once per RID on native Ubuntu runners. The same producer supplies product qualification, standalone CI (including Gallery qualification), and ReadyToRun. Different suite chains reuse verified parents already present on the producer.

## Triggers

Reusable `workflow_call` from companion CI, standalone qualification or ReadyToRun.

## Scripts and effects

For test runs, the producer fingerprints the exact image recipes selected per RID and restores the final archive with an exact GitHub Actions cache key. On a hit it verifies the receipt and archive SHA-256, then binds the receipt to the current run. On a miss it starts Docker, resolves or builds the required images with the existing GHCR and BuildKit policies, and saves the archive for reuse. Both paths upload a current-run bundle using [Export-CiImageBundle](../../scripts/Export-CiImageBundle.md). Failed consumers can reuse the same-run artifact on rerun. Cache-only preparation warms GHCR and uploads receipts without exporting the test archive.

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
