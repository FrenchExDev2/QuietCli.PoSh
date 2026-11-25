# CiPlanReport.psm1

<!-- script-source:begin -->
Source file: [`lib/CiPlanReport.psm1`](../../../scripts/lib/CiPlanReport.psm1)
<!-- script-source:end -->

## Purpose and usage

Writes the changed input to package to project to companion to action reason chain for PR review.

```powershell
Write-QuietCiPlanReport -Plan $plan -Base $base -Revision $revision -Directory ./artifacts/ci-plan -WhatIf
```

## Dependencies and side effects

Writes plan.json and impact.md. Optional SummaryPath appends UTF-8 Markdown to the planning check summary. Below the full and smoke suites, impact.md names the tooling scope (`Tooling: full.`, `Tooling: scripts.` or `Tooling: none.`) when the plan carries one. When the plan includes pull request options, the report lists the checked options and prints `Requested PR options: none.` for an empty selection. Output labels unselected scopes as untested.

The `-MarkdownPath` parameter set writes one standalone UTF-8 Markdown file and replaces it atomically. For the post-commit plan it also reports the script test count, mutation targets, build requirement, layout and distribution selection. `-WhatIf` leaves the destination untouched.

## Critical review

- The implementation in scripts/lib/CiPlanReport.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- script-contract:begin -->
## Execution contract

Purpose: Saves a reviewable reason chain and publishes it in the GitHub planning check summary.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
