# GitHubActionReleases.psm1

<!-- script-source:begin -->
Source file: [`lib/GitHubActionReleases.psm1`](../../../scripts/lib/GitHubActionReleases.psm1)
<!-- script-source:end -->

## Purpose and usage

The release source of [Update-GitHubActions.ps1](../Update-GitHubActions.md). It answers one question, "what is the latest release of `owner/repository`, as a tag and a commit?", from one of two interchangeable sources: the GitHub REST API or a reviewed JSON catalog. Callers receive the same `{Action, Status, Tag, Sha, Source}` object from both. Import is inert.

| Export | Contract |
| --- | --- |
| `Invoke-QuietGitHubActionApi` | One read-only `GET https://api.github.com/repos/…`. The path must start with `/repos/`, use only `[A-Za-z0-9._/%-]` and never contain `..`, else `GitHubActionApiPathInvalid` is thrown before anything is sent. It sends API version `2022-11-28`, a fixed user agent, a 30 s timeout and 2 retries. The bearer token comes from `GH_TOKEN`, else `GITHUB_TOKEN`; blank tokens are not sent. It returns `{Status, Body}`, and `Body` is parsed only for 2xx. A transport failure throws `GitHubActionApiUnavailable`, an invalid 2xx JSON body `GitHubActionApiResponseInvalid`. |
| `Get-QuietGitHubActionLatestRelease` | Reads `/releases/latest`, which GitHub defines as the newest non-draft, non-prerelease release. It then peels the tag ref to a commit through at most four annotated tag objects. HTTP 404 on the release is `Status NoRelease`. Any other non-200 status, an invalid tag, an invalid object id, or a chain that does not end on a commit throws `GitHubActionReleaseUnknown`. A rate limit or outage therefore never reads as "no release". |
| `Assert-QuietGitHubActionTag` | A tag must fit a `uses:` ref and a comment: `[A-Za-z0-9][A-Za-z0-9._+-]{0,127}`. Anything else throws `GitHubActionReleaseUnknown`. |
| `Read-QuietGitHubActionReleaseCatalog` | Reads strict UTF-8 JSON mapping `owner/repository` to `{"Tag", "Sha"}` or to `null` into an ordinal dictionary with `Source Catalog`. A null entry becomes `NoRelease`. Invalid encoding, JSON, shape, key, tag or id throws `GitHubActionCatalogInvalid`. |
| `Resolve-QuietGitHubActionReleases` | Resolves each distinct action once, from the catalog when one is given, else from the API. An action missing from the catalog throws `GitHubActionReleaseUnknown`: a catalog is never silently mixed with the network. |

## Dependencies and side effects

`Invoke-WebRequest` with `-SkipHttpErrorCheck` (PowerShell 7.4 or later), and the `GH_TOKEN`/`GITHUB_TOKEN` environment variables, which are read only. No file is written. The catalog reader only reads its file.

## Critical review and verdict

The "latest release" is GitHub's own definition. A repository that publishes prereleases only, or that tags without releases, resolves to `NoRelease` and is left alone. That is conservative and visible in the report. Peeling uses the git refs API rather than the release's `target_commitish`, which can name a branch. Anonymous calls are limited to 60 per hour, about 20 actions at three calls each, so a token is recommended for this repository. Verdict: correct and fail-closed. The catalog keeps reviews and tests offline and reproducible.

## Tests

- [`unit/lib/GitHubActionReleases.Tests.ps1`](../../../test/scripts/unit/lib/GitHubActionReleases.Tests.ps1) runs with `Invoke-WebRequest` and `Invoke-QuietGitHubActionApi` mocked. It covers:
  - request shape and headers, token order, blank tokens, the 2xx boundary, transport and JSON errors, refused paths;
  - lightweight and annotated tags, chains of four and five objects, invalid object ids;
  - `NoRelease` and the HTTP statuses that must not read as it;
  - catalog parsing and exact refusals, resolution and deduplication;
  - a tag fuzz test.
- Mutation target `GitHubActionReleases`, `Break` 80.

<!-- script-contract:begin -->
## Execution contract

Purpose: Sends one bounded GET to the GitHub REST API and returns {Status, Body}, Body being the parsed JSON or null.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
