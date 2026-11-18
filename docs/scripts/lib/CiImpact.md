# CiImpact.psm1

<!-- script-source:begin -->
Source file: [`lib/CiImpact.psm1`](../../../scripts/lib/CiImpact.psm1)
<!-- script-source:end -->

Exports Get-QuietCiImpact, Get-QuietCiDispatchImpact and Test-QuietDevelopReceipt. Import is inert; no product module or native process starts.

Get-QuietCiImpact reads the validated YAML suite catalogue. Companion changes select all suites whose transitive requirements include that product. Core changes select Core and smoke its dependents; shared or unknown changes select All plus tooling. Multiple affected suites share one matrix. Tooling.Tests belongs to its own campaign. Existing FrenchExDev application modules consume Core and separate executable companions; application membership does not qualify a CLI handler.

Test-QuietDevelopReceipt requires explicit booleans, exact tree/run/attempt identities and successful required Windows, Linux, performance, tooling and mutation outcomes. Missing fields fail closed.

## Repository scripts select only their script tests

A change below the exact, case-sensitive `scripts/` or `test/scripts/` prefix selects no product suite, smoke, image or tooling campaign. The plan lists it in `ScriptPaths` instead. [`New-CiImpactPlan.ps1`](../New-CiImpactPlan.md) then asks [`ScriptsImpact.psm1`](ScriptsImpact.md) which script test files and script mutation targets those paths reach, and only those run.

Repository scripts never ship in a companion product. So a change to a CI library, an entry point or a run profile no longer qualifies every companion, Core without Git or the run profiles on a pull request or a develop push. To qualify them after such a change, run `companions-ci.yml` manually (see below).

Look-alike paths keep the conservative full plan: `Scripts/`, `scriptsx/`, `src/<group>/scripts/` (owned by its group), `Test/scripts/` and `test/scriptsx/`. Combining a tooling path with a product or shared path unions both requirements, independently of path order.

Tests:
- `CiScalability.Tests` exercises generated profile names, look-alike prefixes, mixed scopes and a targeted resolver mutation;
- `test/scripts/unit/lib/CiImpact.Tests.ps1` covers these rows, monotonicity, order invariance and path fuzzing.

## Manual dispatch

`Get-QuietCiDispatchImpact -Suite` builds the plan of a manual `companions-ci.yml` run without reading a diff. Its input is a list of companion names or `Tooling`, as items or comma-separated, matched without case, or `all`.
- **Selection:** each requested companion is fully qualified, in catalogue order. Unselected companions that depend on one are smoked. `Tooling` selects the full tooling workflow: Core without Git, the run profiles, every script test with coverage and every script mutation target. `all` selects every companion and the full tooling.
- **Plan shape:** `RunProducts` is true when a companion is selected; `RunTooling` is true for `Tooling` or `all`. `Suite` is the single companion, `Selected` or `None`. `RunDistribution` and `ConservativeFull` are false. `ChangedPaths`, `BuildProjects` and `ScriptPaths` are empty.
- **Reasons:** each full suite, and the tooling, records `workflow_dispatch|ManualDispatch`.
- **Errors:** an empty or blank selection fails with `CiDispatchSuiteRequired`. An unknown name fails with `CiDispatchSuiteUnknown: <name>`; no prefix or wildcard is accepted.

The unit tests cover generated catalogues, spellings, duplicates, both input forms and every rejection.

## Critical review and verdict

scripts/lib/CiImpact.psm1:1 favors a conservative full matrix over guessed dependencies. The caller supplies a complete no-rename diff. Companion manifests determine build closure; the YAML determines qualification/image requirements. Tests exercise known scopes, unknown paths, compound scopes, malformed paths, every required receipt field and stale identities. Hosted API and cache transfer behavior still require GitHub execution.

<!-- script-contract:begin -->
## Execution contract

Purpose: Separates affected builds, full qualification and dependent smokes from complete old/new changed paths.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/lib/CiImpact.psm1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
