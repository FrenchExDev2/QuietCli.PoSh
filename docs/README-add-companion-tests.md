# Add a business case to a companion test suite

The [monorepo companion generator](../readmes/README-add-companion.md) supplies a first test that checks module loading. Extend its runner with assertions for the business behavior your companion promises. This walkthrough follows an existing Vagrant parser case that runs without installing Vagrant or contacting a provider.

## Define the fixture and its expected result

The fixture is one machine-readable Vagrant record. The last field encodes a literal comma. The test keeps the expected decoded value next to the input and checks the whole event against an independent parser.

```powershell
$cases['an escaped comma in Vagrant data is correctly un-escaped'] = {
    $line = '1700000003,web,ui,detail,a%!(VAGRANT_COMMA)b'
    $actual = ConvertFrom-QuietVagrantMachineReadableLine $line
    $expected = ConvertFrom-QuietVagrantOracleLine $line
    Assert-QuietVagrantEventEqual $actual $expected
    Assert-QuietEqual $actual.Fields[1] 'a,b'
}
```

The case and oracle live in [VagrantLine.Tests.ps1](../src/Vagrant/test/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/VagrantLine.Tests.ps1#L150). The runner collects the cases from this helper. For a new companion, write the expected value from the documented format or use an independent observation of the native effect. For a mutating handler, assert the resulting state in a disposable fixture independently of the returned object.

## Register the case and declare its dependencies

Add one literal entry in the runner's `$caseMetadata` hashtable with exactly the same name as the case. This case is pure parsing with in-memory input, so the entry is:

```powershell
$caseMetadata = @{
    'an escaped comma in Vagrant data is correctly un-escaped' = @{
        TestKind = 'Unit'
        Dependencies = @()
    }
}
```

The [test manifest](../src/Vagrant/test/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh.psd1) declares the exported runner and helper sources under `PrivateData.QuietCli.TestCatalogue`. When adding a case to an existing helper, keep that helper in `Sources`. For a new helper, add its path relative to the test module's directory and load and collect its cases from the runner. Vagrant declares the following catalogue:

```powershell
@{
    Runner = 'Invoke-QuietVagrantTests'
    Sources = @('VagrantLine.Tests.ps1', 'VagrantFuzz.Tests.ps1')
}
```

Keep the runner's progress and terminal report contract when adding a case. `TestExecution` is separate from the inventory. Vagrant opts this pure case into `IsolatedProcess` with a stated reason. Keep new cases ordered unless their isolation has been reviewed. See [classification and concurrency](README-test-classification-and-concurrency.md) for the policy and [the Vagrant runner](../src/Vagrant/test/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh.psm1) for catalogue and report assembly.

## Check the catalogue and run the case

From the monorepo root in PowerShell, with [matching local build outputs](../readmes/README-qualification-local.md#local-suites), run:

```powershell
./scripts/Test-TestCaseMetadata.ps1 -Suite Vagrant
./scripts/Invoke-WorkspaceCi.ps1 -Suite Vagrant -SkipBuild `
    -Case 'an escaped comma in Vagrant data is correctly un-escaped'
```

The first command validates the suite's catalogue before execution. The second uses the local visible monitor. In the run directory printed by the launcher, open `summary.json` for the run result and `vagrant-suite.json` for the case details. Check the named entry in `Cases` for `State = Passed`. Expect `Passed = 1`, `Failed = 0`, `Partial = true` and `Incomplete = false` for this successful focused run. If the case is absent, compare the filter with the literal catalogue name. If it fails, read its error and the worker diagnostics beside the report. See [local reports](../readmes/README-qualification-local.md#read-the-local-reports).

## Interpret the evidence

| Check | Evidence it provides |
| --- | --- |
| Generated module-loading test | The selected checkout can load the companion and Core. |
| Focused business case | The selected behavior holds for its stated fixture and assertions. |
| Dependent smoke | Selected import and integration checks run when an upstream dependency changes. |
| Hosted qualification | The selected suite completed its required targets and evidence checks for the tested revision and reported scope. Vagrant fixture evidence does not establish real-provider coverage. |

Use the [hosted qualification guide](../readmes/README-qualification-github.md) for job and receipt checks and the [Vagrant provider smoke procedure](../readmes/README-qualification-local.md#real-provider-and-interactive-console-checks) for the separate opt-in real-provider run.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of all softwares which have QuietCli companions
<!-- credits:end -->
