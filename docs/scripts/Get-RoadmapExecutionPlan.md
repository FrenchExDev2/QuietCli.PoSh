# Get-RoadmapExecutionPlan.ps1

Returns a typed read-only plan from the delivery graph and execution recipes. It delegates to [Get-RoadmapExecutionPlan](lib/Roadmap.Progression.md).

```powershell
$plan = ./scripts/Get-RoadmapExecutionPlan.ps1 -Target CON
$plan.Waves | ForEach-Object { $_.Nodes.Node -join ', ' }
```

`WorkspaceRoot` selects the source model. `Target` is an exact configured node, validated against that model rather than a fixed ValidateSet. Omit it to schedule all branches. No command string is evaluated. Dependencies are ordered before consumers; exclusive resource names cannot overlap within a wave. Structural parallelism does not estimate team capacity or certify an artifact.

Dependencies: PowerShell 7.6+, canonical roadmap/execution JSON and the reusable contract/progression modules. No native executable or network. Side effects: none. Proposed recipe commands remain unavailable until implemented and qualified.

Critical review: validation of the graph and recipe identity lives in [the library](../../scripts/lib/Roadmap.Progression.psm1:24). Scheduling is conservative between whole waves; real package publication and distributed locks are future runtime responsibilities. The complete monitored roadmap suite tests edge ordering, conflicting resources and missing recipes. Verdict: suitable for planning, not a product dispatcher.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
