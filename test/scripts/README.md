# Script tests (`test/scripts`)

Pester 6 tests for the automation in [`scripts/`](../../scripts). Run them with [`Invoke-ScriptsTests.ps1`](../../docs/scripts/Invoke-ScriptsTests.md), never with a global `Invoke-Pester`: the runner imports the pinned Pester 6.2.0, and Windows PowerShell also ships Pester 3.4.0.

```powershell
./scripts/Initialize-TestTools.ps1                  # pinned Pester + PSScriptAnalyzer into .cache/test-tools
./scripts/Invoke-ScriptsTests.ps1                   # unit + integration, visible monitor
./scripts/Invoke-ScriptsTests.ps1 -Kind Unit -Path unit/lib/CiImpact.Tests.ps1 -Seed 61207
```

## Layout

| Path | Content |
| --- | --- |
| `unit/` | Pure tests of `scripts/lib/*.psm1` exports: no process, no network, writes only to `$TestDrive`, doubles through `Mock -ModuleName`. `unit/lib/<Library>.Tests.ps1` mirrors `scripts/lib/<Library>.psm1`. `unit/support` and `unit/mutation` test the test tools themselves. |
| `integration/` | Real entry points run in a child `pwsh` (`Invoke-QuietTestScript`) against fixture workspaces in `$TestDrive`, plus workflow contracts. |
| `support/` | Shared helpers, no business logic: `TestWorkspace` (paths, library import, fixture files, child processes), `Generators` (seeded generators), `Property` (property runner). |
| `coverage.targets.psd1` | Libraries measured by `-Coverage`, with the minimum line coverage `Threshold` (raise it, never lower it). |

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
