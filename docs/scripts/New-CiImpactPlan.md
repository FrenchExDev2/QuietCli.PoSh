# New-CiImpactPlan.ps1

Plans CI for an immutable Base/Revision pair using the complete `git diff --no-renames --name-only -z` path set. Native orchestration uses Ci.Process, without the product engine. It writes artifacts/ci-plan/plan.json and suite/run_products/run_tooling GitHub outputs.

For pull_request, lib/CiImpact selects affected suites through declared transitive dependencies. Shared/unknown sources require All. Multiple impacted companions share one All matrix. Documentation-only PR changes avoid product runs. Unknown paths retain All. Mixed paths union requirements. For push, Get-DevelopQualification must verify identical-tree PR evidence before product replay is removed; a miss requires All.

Outputs are written once each, in a stable order:

| Output | Content |
| --- | --- |
| `suite`, `run_products`, `matrix` | The product qualification. |
| `run_tooling` | Whether `tooling-ci.yml` runs at all. |
| `image_suites` | The compact JSON array of the fully qualified suites. The `images` warm-up job of `companions-ci.yml` passes it to `New-CiSuiteImage.ps1`, so every chain of the run is prepared once per RID before qualification. |
| `run_distribution` | The distribution campaign. |
| `run_layout` | Whether `layout-tests` runs. It is false only when script tests are the whole plan. |
| `run_smokes`, `smoke_suites` | The dependent smokes. |
| `script_mutation_targets`, `script_tests` | `all`, or the compact JSON array of the selected names. |
| `tooling_scope` | `full`, `scripts` or `none`. |

The test file `test/scripts/integration/entrypoints/New-CiImpactPlan.Tests.ps1` runs the script on a fresh Git copy of the working tree. It covers each companion, documentation, script tests, repository scripts, the test runner, an unknown shared input, manual dispatches and every parameter rejection.

## Repository scripts select only their script tests

Repository scripts (`scripts/**`) and their tests (`test/scripts/**`) select no product, smoke, image or layout work. [CiImpact](lib/CiImpact.md) lists them in `ScriptPaths`, and [ScriptsImpact](lib/ScriptsImpact.md) selects the script test files and mutation targets they reach.

| Plan | `tooling_scope` | `script_tests`, `script_mutation_targets` |
| --- | --- | --- |
| A tooling, shared or unknown path, or a manual `Tooling` or `all` dispatch | `full` | `all` |
| Only script paths that reach at least one test or target | `scripts` | The selection, or `all` when the runner, a shared test input, a data file or a deletion changed |
| Anything else | `none` | `[]` |

The report gains a `Tooling: <scope>.` line and one `Scripts` row per selected test or target, with its reason. `test/scripts/integration/entrypoints/New-CiImpactPlan.Tests.ps1` runs the script on a fresh Git copy of the working tree. It covers each companion, documentation, script tests, repository scripts, an unknown shared input, manual dispatches and every parameter rejection.

## Manual dispatch

With `-Event workflow_dispatch`, the plan reads no diff, and `-Base` is rejected. `-Suite` is a list of companion names or `Tooling`, as items or comma-separated, or `all`. [Get-QuietCiDispatchImpact](lib/CiImpact.md#manual-dispatch) turns it into a full qualification of those companions, with smokes of their dependents and without distribution. `Tooling` adds the full tooling campaign, and `all` selects every companion plus the full tooling. The report records `Base: manual-dispatch`.

`companions-ci.yml` passes its `suites` input, which defaults to `all`. To qualify every companion on a pushed branch, run this from the workspace root:

```powershell
./scripts/Invoke-RemoteWorkflow.ps1 -Repository FrenchExDev2/QuietCli.PoSh -Workflow companions-ci.yml -Ref <branch>
```

For a subset such as `Core,Git`, or `Tooling` after a change to qualification scripts, use the **Run workflow** form of *QuietCli2 Companions* in GitHub Actions. [Invoke-RemoteWorkflow](Invoke-RemoteWorkflow.md) exposes no workflow inputs.

| Rejection | Cause |
| --- | --- |
| `CiImpactDispatchTakesNoBase` | `-Base` with `workflow_dispatch` |
| `CiImpactBaseRequired` | `pull_request` or `push` without `-Base` |
| `CiImpactSuiteRequiresDispatch` | `-Suite` outside `workflow_dispatch` |
| `CiDispatchSuiteRequired`, `CiDispatchSuiteUnknown: <name>` | an empty or unknown selection |

Every rejection happens before any output is written.

## Critical review and verdict

scripts/New-CiImpactPlan.ps1:1 fails on incomplete/failed diffs instead of claiming no changes. Both rename sides remain visible. WhatIf performs no native/network/filesystem work. No branch protections or publications are changed. Zero/deleted bases fail rather than silently skipping qualification; normal develop updates use an existing before commit.

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [CiImpact.psm1](lib/CiImpact.md), [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Writes an explained selective PR/develop CI plan from the complete Git diff and XML dependencies.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/New-CiImpactPlan.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->
