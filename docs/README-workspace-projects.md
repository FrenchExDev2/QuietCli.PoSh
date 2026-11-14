# Workspace projects, suites and package eligibility

[`scripts/lib/WorkspaceProjects.psm1`](../scripts/lib/WorkspaceProjects.psm1) is an engine-independent, reusable
PowerShell script. Dot-source it to inspect the selected source workspace without importing business
modules, starting native tools or publishing anything:

```powershell
. ./scripts/lib/WorkspaceProjects.psm1

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

CI suite selection additionally reads [build/companions.yml](../build/companions.yml) through
[CiCompanions](scripts/lib/CiCompanions.md). Its suite declarations can name dedicated integration
test projects independently of product dependencies. Manifest discovery remains the source/build
inventory; fixtures without the YAML retain manifest-based suite selection.

Discovery reads immediate `FrenchExDev2.QuietCli.*.PoSh` directories and their matching `.psd1`
manifests as inert UTF-8 data. Generated directories and archived/extracted modules below them are
outside this search. Linked project directories/manifests, duplicate names and missing manifests
are rejected. `RequiredModules` supplies local dependency edges; external module dependencies stay
external. Results are ordered by dependency, with deterministic ordering among independent projects.
A cycle fails explicitly instead of returning a partial graph. No module `.psm1` runs during discovery.

Source identity, workspace locking, initialization, local ZIP verification and container staging use
this catalogue. Local workspace ZIPs include companion tests for offline verification; those archives
are separate from publicly installable Gallery packages.

## Scoped builds and private tooling

Build-Workspace -Suite selects the test manifest and transitive RequiredModules, then builds an owned scoped solution with cross-project reference validation. Core selects Core/Core.Tests only. Tooling.Tests owns repository automation and has its own metadata; it is never a public package or product All member. Existing application modules consume Core plus separately generated native companions.

## Compiled distributions

`Get-QuietWorkspaceBuildProjects -WorkspaceRoot $PWD.Path` is the common read-only function for portable build outputs. The build and `Get-QuietWorkspaceIdentity -IncludeBinaries` use the same catalogue; no launcher maintains a second project/output list. Each returned row contains `Package`, `Project`, `TargetFramework` and `Output`, with workspace-relative paths. Pure PowerShell packages omit `BuildProjects` and produce no compiled rows.

For a new compiled consumer such as Packer, add the `.csproj` to `Quietly.slnx` and declare its portable outputs in the consumer's manifest:

```powershell
PrivateData = @{
    QuietCli = @{
        BuildProjects = @(
            @{
                Project = 'engine/QuietCli.Packer.Parser.csproj'
                Outputs = @{
                    'net10.0' = 'lib/parser/net10.0'
                    'net11.0' = 'lib/parser/net11.0'
                }
            }
        )
    }
}
```

Project and output paths are relative to that package. Projects must exist, declared frameworks must match the project XML, outputs must be distinct non-overlapping paths under `lib/`, and links, traversal, DTDs, unknown declaration fields and malformed values fail explicitly. Existing suite/dependency/publication declarations remain independent. This example does not create or qualify a Packer module or authorize publication. A dedicated GitHub caller still defines which changes trigger that consumer's suite.

`Build-Workspace.ps1` compiles the solution once, then uses `dotnet publish --no-build` to prepare each declared distribution and its integrity receipt. Source identity follows explicit `ProjectReference` edges and linked `Compile Include` paths, rather than consumer names, and hashes `Directory.Build.props` with the SDK/package/protocol inputs. Dynamic MSBuild expressions and wildcard includes in those explicit edges are not supported by this input resolver and fail rather than silently dropping evidence. Core's architecture-specific ReadyToRun publications retain their separate RID policy.

Local `Invoke-WorkspaceCi.ps1`, GitHub `Invoke-GitHubCi.ps1` and direct workflow build steps already delegate to this shared script. Container staging carries the solution and warning policy as well as the manifests and distributions. Workflow path filters include solution and shared build/package properties.

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

Core and Git explicitly declare publication eligibility; Vagrant remains disabled and every test companion is excluded. Package identity follows the root .psm1/matching manifest through [Get-ModulePackageName](scripts/Get-ModulePackageName.md). GalleryRelease reuses this workspace discovery for release aliases, full names and All; no duplicate publication YAML is introduced. Each prepared artifact contains exactly one selected business module with validated identity, dependencies and declared compiled outputs. The existing build/companions.yml still declares the CI suites/images that must qualify a new companion before publication.

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
