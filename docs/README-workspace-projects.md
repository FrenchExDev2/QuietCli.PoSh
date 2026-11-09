# Workspace projects, suites and package eligibility

[`scripts/WorkspaceProjects.ps1`](../scripts/WorkspaceProjects.ps1) is an engine-independent, reusable
PowerShell script. Dot-source it to inspect the selected source workspace without importing business
modules, starting native tools or publishing anything:

```powershell
. ./scripts/WorkspaceProjects.ps1

Get-QuietWorkspaceProjects -WorkspaceRoot $PWD.Path
Get-QuietWorkspaceSuiteNames -WorkspaceRoot $PWD.Path -Scope Container
Get-QuietWorkspaceSuiteSelection -WorkspaceRoot $PWD.Path -Suite All

# Inspect all packages or either eligibility group.
Get-QuietWorkspacePackages -WorkspaceRoot $PWD.Path
Get-QuietWorkspacePackages -WorkspaceRoot $PWD.Path -Publishable
Get-QuietWorkspacePackages -WorkspaceRoot $PWD.Path -NonPublishable
```

The package result contains `Name`, `PackageName`, `Publishable`, `Reason`, `IsTest`, `Path` and
`ManifestPath`. It returns objects for filtering and reporting. `Publishable` and `NonPublishable`
are mutually exclusive filters.

## Projects are actual source modules

Discovery reads immediate `FrenchExDev2.QuietCli.*.PoSh` directories and their matching `.psd1`
manifests as inert UTF-8 data. Generated directories and archived/extracted modules below them are
outside this search. Linked project directories/manifests, duplicate names and missing manifests
are rejected. `RequiredModules` supplies local dependency edges; external module dependencies stay
external. Results are ordered by dependency, with deterministic ordering among independent projects.
A cycle fails explicitly instead of returning a partial graph. No module `.psm1` runs during discovery.

Source identity, workspace locking, initialization, local ZIP verification and container staging use
this catalogue. Local workspace ZIPs include companion tests for offline verification; those archives
are separate from publicly installable Gallery packages.

## Suites are execution selections

Each business module declares `PrivateData.QuietCli.TestsModule`. Its test companion must depend on
that module and export `Invoke-Quiet<Suite>Tests`, where `<Suite>` is the business directory's middle
name (`Core`, `Git`, `Vagrant`, or a newly added companion). Missing or inconsistent declarations fail
explicitly. The runner is selected through its own module-qualified command.

`All` expands to the discovered companions in dependency order. It is an execution mode, **not a
module or package**. `Import`, `Integration`, native `Mutation` and the other focused host modes are
also orchestration modes. Host and container launchers expose their supported modes separately;
discovering a new project does not invent an implementation for an unsupported mode.

`New-QuietWorkspaceSuiteParameter` constructs a PowerShell dynamic parameter containing the current
`ValidateSetAttribute`, so binding rejects unknown names and tab completion offers discovered suites.
The four host/container launchers call the same function. A new companion with a valid manifest and
runner needs no edit to those launchers' suite lists.

## Public package eligibility is explicit

Business manifests declare eligibility separately from test selection:

```powershell
PrivateData = @{
    QuietCli = @{
        TestsModule = 'FrenchExDev2.QuietCli.Core.Tests.PoSh'
        Publishable = $true
        PackageName = 'QuietCli'
    }
}
```

`Publishable` must be a boolean. Missing declarations deny publication. Test companions, identified
by the `.Tests.PoSh` suffix without case sensitivity, always return `Publishable = $false`, even if
their metadata asks for publication. The reasons are:

| Reason | Meaning |
| --- | --- |
| `ExplicitlyPublishable` | A business module explicitly declares `$true` |
| `PublicationDisabled` | A business module explicitly declares `$false` |
| `PublicationNotDeclared` | Eligibility is absent and defaults to false |
| `TestProject` | A test companion is excluded |

Currently only the public `QuietCli` Core package is eligible. Git and Vagrant explicitly declare
`$false`; every test companion is excluded. The existing Gallery preparer/verifier still permits
exactly the public Core package. Changing metadata does not authorize publication or extend that
publisher's supported package set; its qualification and explicit publication gates remain required.

## Validation

```powershell
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -SkipBuild -Case '*workspace project*'
```

This focused, partial development run checks inert manifests, a newly added companion, actual dynamic
parameter binding/completion metadata, package filters, forced test exclusion, dependency cycles,
32 generated dependency graphs, malformed/invalid UTF-8 data and six targeted source mutants. It
does not publish packages or replace the unfiltered `All` regression gate.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
