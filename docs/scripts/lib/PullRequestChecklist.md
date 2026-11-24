# PullRequestChecklist.psm1

<!-- script-source:begin -->
Source file: [`lib/PullRequestChecklist.psm1`](../../../scripts/lib/PullRequestChecklist.psm1)
<!-- script-source:end -->

`Read-QuietPullRequestChecklist` parses the versioned Markdown block used by GitHub's PR template. Options are returned in canonical order. The parser ignores fenced examples and rejects malformed, duplicate or unknown choices. The `script-mutation-no-input-cache` row is optional when reading older descriptions.

`New-QuietPullRequestBody` composes a description, the standard checklist and an optional footer without changing input files. An explicit option array overrides the checks in the supplied description.

`Expand-QuietPullRequestTemplate` generates unchecked profiling rows for every declared companion and mutation rows for companions that declare a campaign. The generator keeps the Markdown outside those generated rows and uses the catalogue names to form stable checkbox identifiers.

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
