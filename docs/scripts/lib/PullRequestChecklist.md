# PullRequestChecklist.psm1

<!-- script-source:begin -->
Source file: [`lib/PullRequestChecklist.psm1`](../../../scripts/lib/PullRequestChecklist.psm1)
<!-- script-source:end -->

`Read-QuietPullRequestChecklist` parses the GitHub task-list items in the managed Markdown block and returns options in canonical order. The parser ignores fenced examples and rejects malformed, duplicate or unknown choices. The `script-mutation-no-input-cache` item is optional when reading older checklists.

`New-QuietPullRequestBody` composes a description, the standard checklist and an optional footer without changing input files. An explicit option array overrides the checks in the supplied description. Pass `-GuideUrl` to pin links inside the checklist to a published revision.

`Expand-QuietPullRequestTemplate` emits a GitHub task-list item for each supported target and effect. Each item displays the target, links to the effect guide and carries a stable CI identifier in a Markdown comment. The generator preserves Markdown outside the managed block. [PR CI guide](../../README-pull-request-ci.md)

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
