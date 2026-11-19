# MutationShards.psm1

<!-- script-source:begin -->
Source file: [`lib/MutationShards.psm1`](../../../scripts/lib/MutationShards.psm1)
<!-- script-source:end -->

## Purpose and usage

Exports `Get-QuietMutationShard`, `Get-QuietRunProfileMutationIdentity`, `Assert-QuietMutationShard` and `Assert-QuietMutationShards`. Import is inert and has no product-engine dependency. Ordered catalogue entries are partitioned by ordinal modulo shard count; defaults select the full catalogue.

The aggregator requires exactly the expected shards, disjoint complete names, a green baseline for each, matching source hashes/revision and the qualification seed/iterations (61207/120). Only Killed is accepted; a score or successful process exit alone is insufficient. Source identity covers all copied libraries, subjects, tests and execution helpers.

`Assert-QuietMutationShard` validates one independently expected index/count against the authoritative catalogue, source hash/revision, green baseline, seed/iterations and exact Killed-only names. The report must retain its real Partial flag. Both the GitHub intermediate entry and complete aggregator use this validator, so accepting a partition does not waive the complete-union gate. Real-entry child-process regressions use synthetic worker reports and reject stale/damaged receipts, partial products and guard mutants.

## Dependencies and side effects

PowerShell Core and .NET hashing; the trusted source-controlled catalogue is an inert data file. Partition/validation are pure; identity reads local files. No native execution, writes, network or product import occurs.

## Critical review and verdict

`scripts/lib/MutationShards.psm1:1` centralizes partitioning and completion without sharing workers or sandboxes. `MutationShards.Tests.ps1` independently checks complete/disjoint generated partitions, damaged/missing receipts, a partition mutant and exporter previews. Actual mutants remain independently asserted by their existing test suite. Hosted timing and cross-runner transfer require CI evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Partitions an ordered, uniquely named catalogue without omitting or repeating a mutant.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Read-only property projections use script blocks so metadata remains available during WhatIf; mutating operations retain their existing operation guards.

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/MutationShards.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
