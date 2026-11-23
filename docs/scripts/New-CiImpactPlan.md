# New-CiImpactPlan.ps1

<!-- script-source:begin -->
Source file: [`New-CiImpactPlan.ps1`](../../scripts/New-CiImpactPlan.ps1)
<!-- script-source:end -->

Plans CI for an immutable Base/Revision pair using the complete `git diff --no-renames --name-only -z` path set. Native orchestration uses Ci.Process. With an output path, it writes `artifacts/ci-plan/plan.json`, `artifacts/ci-plan/impact.md` and the job outputs.

Use `-MarkdownPath` to write a standalone Markdown forecast, independently of the standard job outputs and report bundle. Relative paths are resolved from `-WorkspaceRoot`. In revision mode, `-SourceRoot` optionally selects a materialized tree of the specified revision for reading definitions while Git history remains in `-WorkspaceRoot`. [Automatic post-commit plan](Commit-Workspace.md)

For both `pull_request` and `push`, the planner selects affected suites from the diff and declared dependencies. Shared or unknown paths select every companion. Mixed paths combine their requirements.

With `-Event pull_request`, pass the Markdown description as `-PullRequestBody`. The plan merges the checked options with the mandatory diff scope and exposes the companion campaign matrix. Selecting mutation and profiling for the same companion profiles a single mutation run.

The root and nested `.gitignore` files remain visible in the plan's changed paths and have no effect on job selection. For a working-tree preview, Git still applies its ignore rules when deciding which untracked paths enter the diff.

### Preview the local branch

Use [New-CiImpactPlanFile.ps1](New-CiImpactPlanFile.md) to generate a temporary output file using the merge base with `origin/develop`:

```powershell
./scripts/New-CiImpactPlanFile.ps1 -GetContent
```

To call the planner directly from the repository root, supply the base and select the working tree:

```powershell
$base = git merge-base origin/develop HEAD
$outputs = [IO.Path]::GetTempFileName()
./scripts/New-CiImpactPlan.ps1 -Base $base -WorkingTree -OutputPath $outputs
Get-Content ./artifacts/ci-plan/impact.md -Encoding utf8
Get-Content $outputs -Encoding utf8
```

`-WorkingTree` compares the files on disk with `-Base`. The plan includes branch commits, staged and unstaged differences, and non-ignored untracked files. Git applies `.gitignore`, `.git/info/exclude` and its global excludes to untracked files. Tracked paths remain eligible for selection. The plan exposes `ScriptTests`, `ScriptMutationTargets` and `ScriptTestsRequireBuild`. The preview leaves the Git index alone and writes only its reports and output file.

Pass `-Revision (git rev-parse HEAD)` to plan a committed diff. GitHub uses the PR base SHA and its synthetic merge commit. `-WhatIf` skips calculation and writes.

Use `-AsObject` to return the same plan object with an omitted or null `-OutputPath`. This skips the job output file, the plan reports and the GitHub step summary. Supplying a path still writes those outputs as before.

```powershell
$plan = ./scripts/New-CiImpactPlan.ps1 -Base $base -WorkingTree -AsObject -OutputPath $null
$plan.ScriptTests
```

Use `-AsYaml` to return the plan as YAML. An omitted or null output path skips file output. An explicit path still receives the GitHub job outputs in their usual format. Choose one of `-AsObject` and `-AsYaml`.

```powershell
./scripts/New-CiImpactPlan.ps1 -Base $base -WorkingTree -AsYaml
```

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
| Only script paths that reach at least one test or target | `scripts` | A targeted selection, or `all` for shared inputs such as the test runner |
| Anything else | `none` | `[]` |

The planner reads the baseline mutation catalogue from Git when that file changes. A comparable addition or edit selects the affected mutation shard and its unit tests. A missing or unusable baseline, or a removed target, retains the shared-input selection. The report records the reason for each selection.

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
| `CiImpactOutputPathRequired` | An omitted or empty output path without `-AsObject` or `-AsYaml` |
| `CiImpactOutputFormatConflict` | Both `-AsObject` and `-AsYaml` |
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

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->

<!-- grouped-layout-review:begin -->
## Grouped workspace contract

Reviewed source: scripts/New-CiImpactPlan.ps1:1. Module identities are resolved through the catalogue while physical source/test paths live below src/<group>/. Dependencies remain explicit and imports do not execute business operations.

Build-Workspace supports verified reuse and explicit affected Project paths. New-CiImpactPlan emits separate build/full/smoke selections and reason chains. Cache presence never replaces source, payload, configuration and target verification. The global release check name and publication requirements remain unchanged.

See the [layout and selective-CI contract](
../README-companion-layout-and-ci.md
).
<!-- grouped-layout-review:end -->

## Pull request body

Pass the raw description with `-PullRequestBody` to include its checked options. This parameter also works in `-WorkingTree` mode. See [the checklist contract](../README-pull-request-ci.md).
