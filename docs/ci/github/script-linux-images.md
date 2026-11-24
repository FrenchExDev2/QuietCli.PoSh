# linux-images.yml

<!-- workflow-source-sha256: 41DE372CB9AF3C7DC5E8942C955441AEA2CF213DBEE11D78F5CAD2622D7BEFF2 -->

## Purpose

Prepares the selected Linux image chains once per RID on native Ubuntu runners. The same producer supplies product qualification, standalone CI (including Gallery qualification), and ReadyToRun. Different suite chains reuse verified parents already present on the producer.

## Triggers

Reusable `workflow_call` from companion CI, standalone qualification or ReadyToRun.

## Scripts and effects

The producer owns registry lookup, native build and BuildKit caching. The original upstream develop policy controls GHCR publication. For test runs it saves one image archive and identity receipt per RID using [Export-CiImageBundle](../../scripts/Export-CiImageBundle.md). The same-run artifact can be reused when GitHub reruns only failed consumers. Cache-only preparation warms GHCR and uploads receipts without exporting the test archive.

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
