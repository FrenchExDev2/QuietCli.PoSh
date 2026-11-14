# ToolingResults.psm1

## Purpose and usage

`Get-QuietToolingResults -NeedsJson $json` reads the four authoritative GitHub needs
entries: core-independence, tooling, run-profiles-mutation and mutation-complete.
It returns FunctionalResult, MutationResult and CompletionResult without I/O.

## Contract and dependencies

Functional aggregation prioritizes failure, cancellation, then skipped over success.
The two mutation fields remain independent, so failed execution differs from failed
catalogue verification. Unknown, empty, incorrectly typed or missing results become
failure. JSON input is limited to 65,536 characters and depth 16. No product module
or external dependency is loaded; import defines functions only.

## Review and validation

This helper trusts the needs object supplied by GitHub; it does not authenticate
caller-authored JSON. The qualification gate also requires the overall reusable
workflow to succeed, preserving setup and artifact failures. ToolingResults.Tests.ps1
owns generated status properties, malformed inputs and source-checked mutations.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Separates authoritative functional, mutation and completeness job results without accepting missing evidence.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
