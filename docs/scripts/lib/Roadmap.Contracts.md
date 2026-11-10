# Roadmap.Contracts.psm1

The reusable planning module separates prerequisite-graph analysis, model checks, file/provenance assessment and generated Markdown views. It exports `Test-RoadmapModel`, `Get-RoadmapAssessment` and `Sync-RoadmapContractView`. Graph traversal and rendering remain private cohesive functions, without executable-specific branches or product dependencies.

```powershell
Import-Module ./scripts/lib/Roadmap.Contracts.psm1
$assessment = Get-RoadmapAssessment -WorkspaceRoot $PWD.Path
Sync-RoadmapContractView -WorkspaceRoot $PWD.Path -WhatIf
```

`Test-RoadmapModel -Model <parsed JSON> -Registry <parsed JSON> -RoadmapFiles <names>` checks a proposed baseline in memory. It returns errors, proposed topological orders, gaps and a PlanConsistent decision. `Get-RoadmapAssessment -WorkspaceRoot <path>` adds actual file inventory, managed-block freshness, unmanaged requirement-table detection, LF/content checks and the archived source hash. `Sync-RoadmapContractView -WorkspaceRoot <path> [-PlanPath <explicit.md>]` owns ShouldProcess, validates before writing, updates generated references/views and emits no incidental pipeline data. An optional mirror resolves local Markdown links against the original documentation directory. All file I/O is explicitly UTF-8; file reads/writes use asynchronous APIs with GetAwaiter().GetResult().

Dependencies: PowerShell Core 7.6 and .NET host APIs only. JSON inputs are bounded to 4 MiB, parsing depth to 64, graphs to 2,048 nodes. No engine or native CLI runs. The consumer-to-producer edge convention is explicit. Missing nodes, duplicates, unknown roadmaps/kinds/links, cycles, empty ACs/deliverables/pattern fields and inconsistent declared evidence states fail closed. Learning feedback is separate and cannot be a blocking same-revision dependency.

The model owns delivery contracts and proposed graphs; the requirements registry owns requirement/AC semantics. Views carry IDs rather than duplicate editable AC text. A planned delivery reference does not attest that a product artifact exists. Verified/Released cannot accompany NotRun evidence; Passed/Failed requires an executed test reference, artifacts and source/environment identities. These are declared-field checks, not independent verification of those artifacts.

Side effects: only the sync command writes, to classified roadmaps, generated work-item references and an optional explicitly selected plan mirror. Legacy ID/requirement tables are adopted as generated views: they are replaced by a pointer to the canonical table in the managed block. Other human prose and the historical source archive are preserved. A reapply is idempotent. There is no cross-file atomic transaction; interrupted sync is detectable as stale views. Default assessment is read-only.

Regression retained: under inherited WhatIf, `ForEach-Object Name` can suppress member enumeration. The module deliberately uses script-block property access during discovery and rendering; the owned-copy WhatIf regression checks both no mutation and a successful preview.

Critical findings and limits ([source](../../../scripts/lib/Roadmap.Contracts.psm1)): the controller enforces a bounded contract, not a complete JSON Schema or arbitrary hostile-JSON security boundary; duplicate JSON object keys are not independently rejected by this reader. Pattern fields are structurally required, but the relevance of their prose needs human review. Actual PackageReference/RequiredModules/build graphs and artifact hashes must be evaluated by future product tooling. ImplementationReady is conservatively false while versions, API decisions, budgets and recovery procedures remain open. Release evidence is never granted by this module.

Independent companion coverage is in [roadmap-tests](../../../FrenchExDev2.QuietCli.Core.Tests.PoSh/roadmap-tests/Invoke-RoadmapTests.ps1): fault controls, randomized DAG edge-order invariants, malformed object/JSON/identifier corpus, managed-view/WhatIf/idempotence checks, archive tampering and source-checked targeted mutations. The catalogue is bounded and does not claim exhaustive fuzzing, complete mutation coverage or coverage instrumentation. The visible monitor and process supervisor reuse existing tooling.

Verdict: scoped PlanConsistent tooling, with explicit semantic and product-qualification boundaries. Shared facade: [Invoke-RoadmapContract](../Invoke-RoadmapContract.md). Full local campaign: [Invoke-RoadmapTests](../Invoke-RoadmapTests.md).

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
