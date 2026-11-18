# CiProjectGraph.psm1

<!-- script-source:begin -->
Source file: [`lib/CiProjectGraph.psm1`](../../../scripts/lib/CiProjectGraph.psm1)
<!-- script-source:end -->

## Purpose and usage

Reads project ownership, package declarations, project references and imported build inputs without compiling.

```powershell
Get-QuietCiProjectGraph -WorkspaceRoot $checkout
```

## Dependencies and side effects

XML readers prohibit DTDs and external entities. Literal inherited props/targets are read transitively, including their PackageReference, ProjectReference and Import declarations; conditions retain the union of possible consumers. Property-based edges use evaluation-only MSBuild when requested. Changed package comparison retains conditional declarations and referenced version properties. Get-QuietEvaluatedProjectInputs queries MSBuild items/properties without running targets; unresolved inputs must stay explicit rather than being considered unaffected.

## Critical review

- The implementation in scripts/lib/CiProjectGraph.psm1 keeps executable orchestration in entry points and helper functions in libraries; imports do not start business operations.
- WorkspaceLayout.Tests.psm1 covers generated membership, preview behavior, selective package consumption, 120-companion isolation, malformed XML and a targeted selection mutant. CompanionSmoke.Tests.psm1 exercises actual imports and native integration.
- Hosted Windows/Linux matrix and cache-transfer evidence must be read from the revision's CI artifacts; local checks do not establish unexecuted targets.

## Verdict

Explicit source-bound automation with a checked scope. Read the selected run's saved reports for qualification evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Parses inert build XML while refusing external entities and DTDs.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
