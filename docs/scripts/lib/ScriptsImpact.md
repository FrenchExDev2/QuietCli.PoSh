# ScriptsImpact.psm1

## Purpose and usage

Chooses which script tests and mutation targets must run after a change below `scripts/` or `test/scripts/`. Without it, every such change would rerun the whole script test suite and every mutation shard.

```powershell
$impact=Get-QuietScriptsImpact -WorkspaceRoot . -ChangedPaths @('scripts/lib/CiPlanResults.psm1')
$impact.TestFiles        # unit/lib/CiPlanResults.Tests.ps1, unit/quality/Inventory.Tests.ps1, ...
$impact.MutationTargets  # CiPlanResults
$selection=Resolve-QuietScriptsCiSelection -WorkspaceRoot . -Scope scripts -Tests '["unit/lib/CiPlanResults.Tests.ps1"]' -Targets '["CiPlanResults"]'
```

[`New-CiImpactPlan.ps1`](../New-CiImpactPlan.md) calls `Get-QuietScriptsImpact` with the plan's `ScriptPaths` (see [`CiImpact.psm1`](CiImpact.md)). It writes the selection to the `script_tests` and `script_mutation_targets` outputs. The `script-selection` job of `tooling-ci.yml` validates them with `Resolve-QuietScriptsCiSelection`.

### Exported functions

| Function | Returns |
| --- | --- |
| `Get-QuietScriptsTestFiles -TestsRoot` | Every `*.Tests.ps1` under `unit/` and `integration/`, relative to the tests root, in ordinal order. |
| `Get-QuietScriptsImpact -WorkspaceRoot -ChangedPaths` | `{SchemaVersion=1; AllTests; AllTargets; TestFiles; MutationTargets; Reasons}`. Files and targets keep their catalogue order. Each reason is `{Selection; Name; Reason}`, where `Reason` reads `<path>: <code>`. |
| `Resolve-QuietScriptsCiSelection -WorkspaceRoot -Scope -Tests -Targets` | `{AllTests; TestFiles; MutationTargets; RequiresBuild}`. `all` expands to every known test or target. |

### Selection rules

A test file is selected when one of these holds:

| Reason | Condition |
| --- | --- |
| `TestChanged` | The test file itself changed. |
| `ReachesScript` | A changed script is in the closure of the file's references. The closure is the one the mutation cache computes, via `Get-QuietScriptMutationSourceFiles`, from the file and the support modules. |
| `ReadsEveryScript` | Any script changed, and the file declares `#ScriptsImpact: AllScripts` on a line of its own. Use this for inventories and analyzers, which read every script without importing them. |

A mutation target is selected (`ReachesTarget`) when a changed path is in one of these:
- its module closure;
- one of its unit test files;
- one of its `Inputs` files.

Some changes select everything, with the reason recorded:

| Reason | Change | Selects |
| --- | --- | --- |
| `DeletedScriptInput` | A changed path no longer exists. | Every test and every target. |
| `ScriptData` | A script file that is not `.ps1` or `.psm1`. | Every test and every target. |
| `SharedTestInput` | A test-root file other than a unit or integration `*.Tests.ps1`: support, analyzer, settings, targets or inventories. | Every test and every target. |
| `TestRunnerChanged` | A file in the closure of `Invoke-ScriptsTests.ps1`. | Every test and every target. |
| `MutationEngineChanged` | A file in the closure of `Invoke-ScriptsMutation.ps1`. | Every target. |

Markdown paths select nothing.

A test file that declares `#ScriptsImpact: RequiresBuild` drives the built quiet engine (for example `Start-QuietWorkBranch.Tests.ps1`). When such a file is selected, `RequiresBuild` is true, and `script-tests` builds Core and Git before it runs.

### Errors

| Error | Cause |
| --- | --- |
| `ScriptsImpactPathInvalid` | An empty path, NUL, a backslash, a rooted path or a `..` segment. |
| `ScriptsImpactPathOutsideScripts: <path>` | A path outside the case-sensitive `scripts/` and `test/scripts/` prefixes. |
| `ToolingScopeInvalid` | A scope other than `full` or `scripts`. |
| `ToolingFullScopeSelectsAll` | Scope `full` with a selection other than `all`. |
| `ScriptsCiSelectionInvalid` | A selection that is neither `all` nor a JSON array of non-empty strings. |
| `ScriptsCiTestUnknown: <name>`, `ScriptsCiTargetUnknown: <name>` | A name outside the catalogue. Names match case-sensitively. |

## Dependencies and side effects

The module imports [`ScriptMutation.psm1`](ScriptMutation.md), which reads the targets file, and [`ScriptMutationCache.psm1`](ScriptMutationCache.md), which computes closures and `Inputs` files. It only reads files: it writes nothing and starts no process.

## Critical review

- The selection is only as precise as the reference scan of the mutation cache. That scan follows quoted `<name>.ps1`/`<name>.psm1` literals and `Import-QuietTestLibrary` names. It over-includes rather than under-includes. A dependency built from a computed name is invisible to it, so a test file that needs it must name the file literally or declare `#ScriptsImpact: AllScripts`.
- Coverage is global, so a selective run is a partial run without coverage. Coverage is measured only when every test runs: the runner, a shared input or a manual `Tooling` dispatch.
- `test/scripts/unit/lib/ScriptsImpact.Tests.ps1` covers:
  - a fixture repository with a runner, an engine, targets with `Inputs`, quoted headers and a non-test file;
  - every reason;
  - empty, unsafe and outside paths;
  - monotonicity and order invariance under a seeded property;
  - every `Resolve-QuietScriptsCiSelection` rejection, with fuzzed selections.
- `test/scripts/integration/entrypoints/New-CiImpactPlan.Tests.ps1` checks the resulting plan outputs on a real git fixture.

## Verdict

The selection is conservative: whenever it cannot bound a change, it runs every test and every target. A manual `Tooling` dispatch of `companions-ci.yml` still runs the full campaign.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Lists the *.Tests.ps1 files under unit/ and integration/ of a tests root, relative to it with '/', in ordinal order.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
