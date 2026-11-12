# MutationShards.psm1

## Purpose and usage

Exports `Get-QuietMutationShard`, `Get-QuietRunProfileMutationIdentity` and `Assert-QuietMutationShards`. Import is inert and has no product-engine dependency. Ordered catalogue entries are partitioned by ordinal modulo shard count; defaults select the full catalogue.

The aggregator requires exactly the expected shards, disjoint complete names, a green baseline for each, matching source hashes/revision and the qualification seed/iterations (61207/120). Only Killed is accepted; a score or successful process exit alone is insufficient. Source identity covers all copied libraries, subjects, tests and execution helpers.

## Dependencies and side effects

PowerShell Core and .NET hashing; the trusted source-controlled catalogue is an inert data file. Partition/validation are pure; identity reads local files. No native execution, writes, network or product import occurs.

## Critical review and verdict

`scripts/lib/MutationShards.psm1:1` centralizes partitioning and completion without sharing workers or sandboxes. `MutationShards.Tests.ps1` independently checks complete/disjoint generated partitions, damaged/missing receipts, a partition mutant and exporter previews. Actual mutants remain independently asserted by their existing test suite. Hosted timing and cross-runner transfer require CI evidence.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Partitions an ordered, uniquely named catalogue without omitting or repeating a mutant.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
