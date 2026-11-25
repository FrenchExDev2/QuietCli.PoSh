# Script tests (`test/scripts`)

Pester 6 tests for the automation in [`scripts/`](../../scripts). Run them with [`Invoke-ScriptsTests.ps1`](../../docs/scripts/Invoke-ScriptsTests.md), never with a global `Invoke-Pester`: the runner imports the pinned Pester 6.2.0, and Windows PowerShell also ships Pester 3.4.0.

```powershell
./scripts/Initialize-TestTools.ps1                  # pinned Pester + PSScriptAnalyzer into .cache/test-tools
./scripts/Invoke-ScriptsTests.ps1                   # unit + integration, visible monitor
./scripts/Invoke-ScriptsTests.ps1 -MaxConcurrency 4 # isolated file workers, live counts
./scripts/Invoke-ScriptsTests.ps1 -Kind Unit -Path unit/lib/CiImpact.Tests.ps1 -Seed 61207
```

## Layout

| Path | Content |
| --- | --- |
| `unit/` | Pure tests of `scripts/lib/*.psm1` exports: no process, no network, writes only to `$TestDrive`, doubles through `Mock -ModuleName`. `unit/lib/<Library>.Tests.ps1` mirrors `scripts/lib/<Library>.psm1`. `unit/support` tests the test helpers themselves; the mutation engine is a library, so its tests are `unit/lib/ScriptMutation.Tests.ps1` and `unit/lib/ScriptMutators.Tests.ps1`. |
| `unit/quality/` | Repository-wide rules run as tests, such as the export inventory ratchet (`Inventory.Tests.ps1`). |
| `integration/` | Real entry points run in a child `pwsh` (`Invoke-QuietTestScript`) against fixture workspaces in `$TestDrive`, plus workflow contracts. |
| `support/` | Shared helpers, no business logic: `TestWorkspace` (paths, library import, fixture files, child processes), `Generators` (seeded generators), `Property` (property runner), `CiFixtures` (fixture catalogues and plans for the CI libraries). |
| `coverage.targets.psd1` | Libraries measured by `-Coverage`, with the minimum line coverage `Threshold` (raise it, never lower it). |
| `mutation.targets.psd1` | Targets of [Invoke-ScriptsMutation.ps1](../../docs/scripts/Invoke-ScriptsMutation.md): library, functions, unit test files and minimum score `Break` (raise it, never lower it). |
| `coverage.inventory.json` | Shrink-only list of legacy `scripts/lib` exports that no test names yet. The blocking [ScriptsInventory check](../../docs/scripts/Test-ScriptsInventory.md) fails on any new untested export. After you add a test, run `./scripts/Test-ScriptsInventory.ps1 -UpdateBaseline` to prune the entry. |
| `ScriptAnalyzerSettings.psd1`, `analyzer/`, `ScriptAnalyzer.baseline.json` | Settings, repository rules and shrink-only baseline of the blocking [ScriptAnalyzer check](../../docs/scripts/Test-ScriptAnalysis.md). |

## Writing a test

- **Rule for code placement.** When the logic lives in a library, test the library and its exported functions. Entry points only orchestrate (RAC-PS-003), so they get an integration test, not a unit test.
- **Imports.** Import libraries through `Import-QuietTestLibrary -Name <Library>`. It reads `QUIETCLI_SCRIPTS_ROOT`, which the runner sets and which mutation testing points to a mutated copy. Never import `scripts/lib` through a hard-coded relative path.
- **File shape.** A `*.Tests.ps1` file holds only `BeforeAll`, `BeforeDiscovery`, `Describe` and `AfterAll` blocks at top level. The ScriptShouldProcess check classifies such a file as a test container. Any other top-level statement makes the file an executable script that needs ShouldProcess.
- **Errors.** Assert typed error codes (`Should -Throw -ExpectedMessage 'CiImpactPathInvalid*'`), not localized messages.

## Property and fuzz tests

```powershell
$seed = Get-QuietTestSeed           # QUIETCLI_TEST_SEED from the runner, 61207 when unset
Invoke-QuietProperty -Name 'order invariance' -Seed $seed -Count 200 `
    -Generator { param($random) <# build one case from $random only #> } `
    -Property  { param($case) <# return $false or throw on violation #> } `
    -Shrink    { param($case) <# smaller candidate cases #> }
```

- **Randomness.** Generators must draw only from the `[Random]` they receive, so a case is reproducible from its seed.
- **Failures.** A failure throws `PropertyFailed: <name> seed=<seed> case=<i> caseSeed=<n> shrinks=<k> counterexample=<json>`. Replay it with `-Seed <seed>`.
- **Fuzzing.** Fuzz with hostile inputs (`New-QuietFuzzPath`, malformed objects) and assert that only the library's typed errors can occur.

## Mutation testing

```powershell
./scripts/Invoke-ScriptsMutation.ps1                       # every target of mutation.targets.psd1, visible monitor
./scripts/Invoke-ScriptsMutation.ps1 -Target ScriptsTests  # one target
./scripts/Invoke-ScriptsMutation.ps1 -NoInputCache           # replay every mutant and save fresh outcomes
./scripts/Invoke-ScriptsMutation.ps1 -NoCache                # cold campaign: every mutant runs
```

Each mutant of a target library is run against the target's `UnitTestFiles` only, in an isolated copy of `scripts/`. A surviving mutant means that no assertion detects that change: add the missing assertion, or show that the mutant is equivalent. Declare an equivalent mutant in the target's `Equivalent` list of `mutation.targets.psd1`: `{Function, Mutator, Original, Replacement, Reason}`, plus `Platform` when it is only equivalent on one OS. The reason must explain why no observable behavior can change. An entry that no longer matches a mutant fails the campaign. Mutation runs only unit tests, so a target's unit tests must exercise its behavior without any integration test. See [Invoke-ScriptsMutation.md](../../docs/scripts/Invoke-ScriptsMutation.md).

### Incremental cache and `Inputs`

Outcomes are cached in `.cache/script-mutation`. A mutant's key covers the engine, the target library and every scripts file its closure or its tests name, the target's unit test files, every file of this directory outside `unit/` and `integration/` (except the bookkeeping files), and the mutant itself. A second campaign therefore reruns only the mutants of targets whose observable inputs changed. A passing baseline is cached too, under a key that adds the machine identity: the same machine skips it, while another machine (a CI runner) reruns it. The cache is local and never committed.

Two rules keep the cache sound:
- **Import by literal file name.** The closure scan follows quoted `<name>.psm1`/`<name>.ps1` literals and `Import-QuietTestLibrary <name>`. A library name built at run time is not seen.
- **Declare repository reads in `Inputs`.** A unit test that reads a file outside `scripts/` and `test/scripts/` (the companion catalogue, a lock file, a workflow) must name it in its target's `Inputs` globs. Otherwise an edit of that file would reuse stale outcomes. Prefer a `$TestDrive` fixture when the test does not need the real file.

Over-inclusion only costs reuse, so a broad glob is safer than a missing one. Keep globs away from ignored build outputs such as `obj/`, which make the fingerprint unstable.

## In CI

[tooling-ci.yml](../../docs/ci/github/script-tooling-ci.md) runs these tests in one of two scopes.
- In the full scope (a tooling or shared change, or a manual `Tooling` or `all` dispatch), everything runs.
- In the `scripts` scope (only `scripts/` or `test/scripts/` changed), only the test files and targets that the change reaches run. [ScriptsImpact.psm1](../../docs/scripts/lib/ScriptsImpact.md) selects them.

The jobs are:
- `script-tests` runs on Windows and on Linux, with the pinned tools restored by the `cache-test-tools` action. It runs `Invoke-ScriptsTests.ps1 -Headless -Coverage` for every test, or `-Headless -Path <selected files>` for a selection, without coverage.
- `script-mutation` runs one job per selected target of `mutation.targets.psd1`, with `-PruneCache`. Each job restores the newest cache of its own target by default and saves it afterwards, even after a failure. The PR cache refresh checkbox skips the restore, runs the baseline and mutants afresh with `-NoInputCache`, and still saves fresh outcomes.
- `script-mutation-complete` then requires every selected target exactly once, at or above its break, through [Assert-ScriptMutationShards](../../docs/scripts/Assert-ScriptMutationShards.md) `-Target`.

The selection follows the same literal references as the mutation cache, plus two headers, each on a line of its own near the top of a test file:
- `#ScriptsImpact: AllScripts` selects the file for any script change. Use it for a test that reads every script without naming it, such as an inventory or an analyzer.
- `#ScriptsImpact: RequiresBuild` makes `script-tests` build Core and Git first. Use it for a test that drives the built `quiet` engine.

A change to the test runner, to a file outside `unit/` and `integration/`, to a data file or a deletion selects everything.

A new target needs no workflow edit: the matrix is the `script-selection` output.
