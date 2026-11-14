# GitHubRelease.psm1

## Purpose and usage

`Publish-QuietGitHubRelease -Tag <module/vVersion> -Version <Version> -Revision <sha> -Assets <paths>` implements the GitHub release lifecycle. The owning Publish-QuietGitHubRelease entry point supplies validated Gallery packages/receipts and checks workflow context; direct library use alone does not establish qualification or Gallery publication.

## Dependencies and effects

Import declares functions only. Calls use PowerShell REST APIs with ephemeral GH_TOKEN, explicit UTF-8 JSON and streamed binary InFile uploads. There is no native CLI, engine, rebuild, retry or dependency installation. Standard WhatIf validates local file metadata/hashes but makes no HTTP request or writes. Endpoints are fixed to FrenchExDev2/QuietCli.PoSh; returned upload URLs are not trusted or followed. The existing tag is verified, including up to four annotated tag indirections. Authentication/network failures remain failures; only a release lookup's HTTP 404 means absent.

Draft creation precedes uploads and final publication. Uploaded name, size, state and GitHub SHA-256 digest must match the local file. At most ten distinct non-link files smaller than 2 GiB are accepted. Versions containing a prerelease suffix become GitHub prereleases. make_latest=false avoids choosing one independently versioned module as the repository-wide latest product.

## Critical findings and verdict

`scripts/lib/GitHubRelease.psm1` refuses existing releases/drafts and never deletes/replaces assets. Interrupted uploads leave an unpublished draft; manual inspection is required before recovery. Multi-module publication is ordered but non-atomic, with no rollback. Offline state-machine fixtures assert draft/upload/publish ordering, tag identity, preview/stable policy, no-network WhatIf, failure propagation, malformed assets and mutation counterexamples. They do not qualify real GitHub transport, permissions or hosted artifact extraction. API contracts: [releases](https://docs.github.com/en/rest/releases/releases), [assets](https://docs.github.com/en/rest/releases/assets).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Sends one authenticated GitHub request without retries or credential output.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
