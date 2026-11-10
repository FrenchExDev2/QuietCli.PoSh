# Script effect and preview inventory

## Usage

Dot-source and call `Get-QuietScriptReview -WorkspaceRoot <root>`.

## Dependencies and effects

Inspects every scripts/**/*.ps1 and *.psm1 with the PowerShell AST; classifies executable, library, profile and read-only boundaries. Returns purpose from comment-based help and declared preview APIs without executing inspected code.

## Critical review and verdict

Source: [ScriptReview.ps1:14](../../scripts/ScriptReview.ps1:14). Static guard presence is not behavioral qualification. Library functions retain their own effect boundaries; an unguarded internal function is not independently qualified for direct mutating use.

Verdict: suitable within the documented boundary; qualification evidence belongs in the companion test reports.

<!-- script-contract:begin -->
## Execution contract

Purpose: Reviews every automation script and its declared effect boundary using the PowerShell AST.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
