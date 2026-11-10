# Roadmap.Progression.psm1

LocalNuGet/LocalPSResource/LocalBoth recipes must include the matching feed nodes in their transitive delivery closure. A feed producer may provide its own channel from the explicit bootstrap; consumers may not silently omit the required registry. Independent regression rejects a mixed package whose PSResource prerequisite is absent.

Exports `Get-RoadmapExecutionPlan -Model <object> -Execution <object> [-Target <id>]`. The [facade](../Get-RoadmapExecutionPlan.md) reads the repository models; code consumers call the function directly. Target membership follows configuration and is revalidated at invocation.

The library validates the bounded prerequisite graph, exact one-to-one recipe coverage, command-name grammar, resource presence and lifecycle contract, then computes deterministic ready batches with disjoint exclusive resources. Every output carries PlanningOnly, ProductExecution=NotRun, lifecycle and preview policy. Recipe status Available means that specific command pair exists, not that its product passed acceptance. The implementation never invokes recipe names.

Dependencies: PowerShell Core 7.6+ and sibling Roadmap.Contracts.psm1. Code uses an already loaded exact source module when present. Side effects: only importing these local planning functions, with no engine/build/network/config mutation.

Critical findings: [source](../../../scripts/lib/Roadmap.Progression.psm1:24) validates graph/recipes before scheduling; locks are declared model resources and do not discover unknown filesystem contention. The model is trusted local authoring input, not a generic untrusted-JSON gateway. Independent properties and malformed cases run in the existing test companion. Verdict: a production-contract planner; actual package lifecycle execution remains explicitly Proposed.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
