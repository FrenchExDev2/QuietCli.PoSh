# PullRequestChecklist.psm1

<!-- script-source:begin -->
Source file: [`lib/PullRequestChecklist.psm1`](../../../scripts/lib/PullRequestChecklist.psm1)
<!-- script-source:end -->

`Read-QuietPullRequestChecklist` parses the versioned Markdown block used by GitHub's PR template. Options are returned in canonical order for both the CI table and earlier task lists. The parser ignores fenced examples and rejects malformed, duplicate or unknown choices. The `script-mutation-no-input-cache` row is optional when reading older descriptions.

`New-QuietPullRequestBody` composes a description, the standard checklist and an optional footer without changing input files. An explicit option array overrides the checks in the supplied description.

`Expand-QuietPullRequestTemplate` generates a column for each declared companion plus `Scripts`. Rows describe effects, and the marked cells carry stable option identifiers. A dash indicates an unavailable combination. The parser validates row width, effect links and cell identities. It accepts trailing whitespace on table rows. The generator preserves Markdown outside the managed block and links each effect to the [PR CI guide](../../README-pull-request-ci.md).

<!-- script-contract:begin -->
## Execution contract

Purpose: Reads the single delimited CI checklist and returns its selected identifiers and source range.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
