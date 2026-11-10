# Roadmap engineering and local Manager delivery planning

Date: 10 November 2026. Scope: planning and its independent PowerShell tooling. The user explicitly selected a verifiable plan with deliverables and dependencies; i3 provisioning is outside this pass.

## Delivered contract

The [master roadmap](../ROADMAP-Ecosystem-Generator.md) makes `C:/code/FrenchExDev/FrenchExDev_i3` the required work-environment delivery target. The [dedicated recipe](../ROADMAP-Delivery-FrenchExDev-i3.md) distinguishes workspace, installed Manager deployment and Manager development checkout, and defines eight acceptance scenarios. The directory was observed present and empty before this change; its presence is not an installation result.

The [requirements registry](../requirements/software-ecosystem-factory.requirements.json) contains 77 proposed requirements and 68 planned work items. The [roadmap model](../requirements/software-ecosystem-factory.roadmaps.json) classifies all 19 ROADMAP files, defines four delivery artifacts per kind, proposed delivery/runtime graphs, pattern decisions and engineering review fields. Requirement statements and ACs have one editable source; Markdown tables and delivery blocks are generated projections. The dated original-plan archive and its SHA-256 remain unchanged.

The roadmap contract defines roadmap/backlog/design/schedule separately, applies local SOLID/DRY/modular review questions, and distinguishes POSA analysis, design patterns and orthogonal design/impl/test/obs kinds. Official ISO 29148, ISO 42010 and ISO 25010 summaries and primary POSA/Ports-and-Adapters references are linked in the [common contract](../ROADMAP-Requirements-As-Code.md). This is a scoped engineering policy, not an ISO certification claim or a clause-by-clause conformity audit.

## Dependency decisions

The minimum proposed chain is B0/FAC → G0/DOG0 → HOST0/GP0 → SM0 → I3, with MIG0 assessing the selected i2 inputs before I3. SM0 has only HOST/GP component dependencies at runtime. It must work offline. NuGet registry, complete generators, remote discovery, Result/Builder, FSM, IEC, brokers and new Core pipelines do not become prerequisites of this local slice.

Existing source inspection found the legacy PowerShell Requirements module and .NET Result/Builder/Requirements/FSM/IEC directories. Their presence does not establish transferable packages or future Manager availability. Future artifact versions and exact closure remain unresolved. Current QuietCli has its own pinned SDK and built-engine requirements; these are not imposed on a PowerShell-first Manager unless its selected implementation actually consumes them.

Generation, runtime imports, build/pack prerequisites and qualification must remain distinct. The two proposed component/lot graphs and requirement graph are checked for missing references, duplicates and cycles. Actual future manifest/package graphs still need extraction and validation before ImplementationReady. Self-hosting uses pinned active N and isolated candidate N+1; learning feedback across revisions is separate from same-revision dependencies. Unresolved package/build/startup cycles block execution. Event feedback limits belong to IEC/Core and do not justify a cyclic bootstrap.

## Validation record

The complete independent planning-tooling campaign ran through `scripts/Invoke-RoadmapTests.ps1`, with the existing visible read-only monitor, external owned fixtures, saved terminal status and automatic monitor closure. The final unfiltered campaign passed **212 checks, zero failures**: 26 example/fault controls, 161 property checks, 21 malformed/boundary corpus controls and four targeted source mutants killed. Seed: 20261110. The [validation receipt](2026-11-10-roadmap-contracts.validation.json) records source identities and the external run path. No product campaign, product acceptance or publication is inferred from this campaign.

Run directory: `C:/Users/serard/AppData/Local/Temp/QuietCli2/874a99c9b658/tests/roadmaps-20261110-060743-db73fe`. Reopen its saved state with `pwsh -File ./scripts/Watch-Tests.ps1 -RunDirectory '<run-directory>'`. Final inspection found no monitor process for that run. Full per-case results, fixtures, the initial failure diagnostics and mutants remain external; the committed receipt keeps only bounded metadata. There is no coverage-instrumentation or exhaustive-fuzzing claim.

The first campaign exposed a real WhatIf regression: shorthand PowerShell member enumeration was suppressed under inherited WhatIf, losing the file inventory. Script-block enumeration fixed it; the owned-copy WhatIf check retains the reproducer. Failure diagnostics remain in the first external run. A subsequent full run passed before the final documentation/coverage refinements.

## Gates and outstanding decisions

PlanConsistent is a structural and provenance assessment of this baseline. ImplementationReady is withheld: owners remain Unassigned; future versions, public API/configuration contracts, per-language campaign budgets and recovery procedures need decisions. Product ACs remain NotRun. I3Accepted requires eight real acceptance scenarios on exact artifacts and an explicit acceptance decision. ReleaseReady separately requires the full promised platform/consumer matrix.

No Manager was installed, no source was migrated, and no remote, secret, public package, container or VM was created for this plan. Existing unrelated work must remain excluded from its checkpoint.

The generated replacement for the external Claude plan is prepared as `master-plan.candidate.md` in the final run directory. Automatic approval review rejected overwriting the original external file because a generated mirror could remove unique content and replacement authorization was judged insufficient. The original remains intact; replacement awaits explicit approval. This does not block use of the updated canonical roadmaps.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
