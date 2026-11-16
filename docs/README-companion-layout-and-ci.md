# Companion layout and selective CI

## Source tree and solutions

All product and test groups live below the repository's src directory:

~~~text
Quietly.slnx
Directory.Build.props
Directory.Packages.props
global.json
src/
  Core/
    Core.slnx
    src/FrenchExDev2.QuietCli.Core.PoSh/
    test/FrenchExDev2.QuietCli.Core.Tests.PoSh/
  Git/
    Git.slnx
    src/FrenchExDev2.QuietCli.Git.PoSh/
    test/FrenchExDev2.QuietCli.Git.Tests.PoSh/
  Vagrant/
    Vagrant.slnx
    src/FrenchExDev2.QuietCli.Vagrant.PoSh/
    test/FrenchExDev2.QuietCli.Vagrant.Tests.PoSh/
  Tooling/
    Tooling.slnx
    test/FrenchExDev2.QuietCli.Tooling.Tests.PoSh/
  Distribution/
    Distribution.slnx
    test/FrenchExDev2.QuietCli.Distribution.Tests.PoSh/
~~~

Module names, GUIDs and Gallery identities do not depend on directory locations.
PrivateData.QuietCli.SolutionGroup associates each inert manifest with its group.
A group can contain several source modules and several test modules. Register every
test runner in build/companions.yml; runners declaring the same group are selected
together when that product group is qualified. Module RequiredModules still controls
technical dependency order, and BuildProjects declares compiled distributions.

The global and local solutions reference the same files. CSharp projects are Project
entries; PowerShell scripts, modules, manifests and Markdown are File entries.
No artificial CSharp wrapper is required for a PowerShell-only module.

~~~powershell
./scripts/Sync-WorkspaceSolutions.ps1
./scripts/Sync-WorkspaceSolutions.ps1 -Apply -WhatIf
./scripts/Sync-WorkspaceSolutions.ps1 -Apply
~~~

## Individual workflows and automatic selection

GitHub workflow files remain under the root .github/workflows directory:

| Group | Individual entry point | Solution |
|---|---|---|
| Core | core-ci.yml | src/Core/Core.slnx |
| Git | git-ci.yml | src/Git/Git.slnx |
| Vagrant | vagrant-ci.yml | src/Vagrant/Vagrant.slnx |
| Tooling | tooling-component-ci.yml | src/Tooling/Tooling.slnx |
| Distribution | distribution-ci.yml | src/Distribution/Distribution.slnx |

Each entry point explicitly passes suite, solution_path, source_path, test_path and
qualification_mode through uses/with. Modes are full, smoke and build. Individual
entry points support workflow_call and workflow_dispatch; automatic PR/develop work
uses a matrix of the shared engine from those same generated profiles.

This keeps product requirements readable while avoiding a caller tree containing
one unique reusable workflow for every future companion. GitHub limits such a tree
to 50 unique reusable workflows. The automatic matrix calls the same engine for
each selected profile instead.

~~~powershell
./scripts/Sync-CompanionWorkflows.ps1
./scripts/Sync-CompanionWorkflows.ps1 -Apply -WhatIf
./scripts/Invoke-ComponentCheck.ps1 -Suite Git -QualificationMode smoke
~~~

## Impact rules and review evidence

The planner reads the complete no-rename diff, module declarations, CSharp project
references, package consumers and inherited build inputs. Central package XML is
compared semantically: changing an unused PackageVersion selects no product.
Direct package consumers and CSharp dependents determine affected projects.
Runtime dependency edges select short integration smokes rather than every
dependent's complete campaign.

| Changed input | Full qualification | Additional work |
|---|---|---|
| Git implementation | Git | Required technical dependencies |
| Core implementation | Core | Git/Vagrant integration smokes |
| Git and Vagrant | Git and Vagrant | Union of their technical dependencies |
| Spectre.Console central version | Core | Compiled Core consumers and dependent smokes |
| Unused central package entry | None | Source/layout checks |
| Shared compiler/SDK input | Its consumers | Required dependent smokes |
| Unknown shared automation | All registered product groups | Tooling, with an explicit reason |

The planning check publishes impact.md and plan.json. Every reason identifies the
changed input, package where applicable, consumer project/module, companion and
requested action. build_projects_json carries explicit affected project paths into
the reusable build workflow.

Literal imports and references are inspected directly. Property-based references
and explicit imports use evaluation-only MSBuild queries without executing targets.
Conditions are retained conservatively across supported target environments;
unresolved evaluation widens the plan with its named reason. Arbitrary custom
target side effects are not inferred from XML alone.
Transitive central pinning without a proven resolved consumer graph conservatively
selects importers; such a package is never silently classified as unused.

The final QuietCli required CI check always runs, including documentation-only PRs.
It requires successful planning, source/layout checks and every selected campaign.
Missing, cancelled, failed or wrongly skipped jobs reject the result. This exact
check name is also consumed by the release facade.

## Build configuration and caches

Root Directory.Build.props, Directory.Packages.props, global.json and NuGet
configuration provide the common policy. A local Directory file must explicitly
import the parent policy when inheritance is intended; a nearby file does not
automatically merge every ancestor's declarations.

Cache keys include selected compiled closures, effective package declarations,
build-policy sources, SDK pin, configuration mode and target RID. Raw package-file
provenance is retained separately from the effective dependency hash. Local
inherited inputs and explicit literal imports remain part of freshness validation.

Cache restoration alone is not evidence: payload hashes, source fingerprints,
configuration and requested ReadyToRun slots are checked. ReuseVerifiedBuild
rebuilds stale distributions and explicit affected projects without republishing
unaffected outputs. Missing dependencies on a cold runner still require preparation.
Unpublished projects can be passed explicitly with Build-Workspace -Project.

Verified binary reuse still restores the complete selected solution before returning or narrowing
compilation. Cold runners have no intermediate `project.assets.json` files in the binary cache;
container staging needs these assets to transfer the package closure into its networkless guest.
A documentation-only rebuild must therefore retain the cached product projects in the restore graph,
while compilation remains limited to stale or unpublished projects. Restore failure blocks reuse.

~~~powershell
./scripts/Build-Workspace.ps1 -Suite Git -RuntimeIdentifier win-x64 -ReuseVerifiedBuild
./scripts/Get-CompanionBuildKey.ps1 -Suite Git -RuntimeIdentifier win-x64
./scripts/Build-Workspace.ps1 -SolutionOnly
~~~

## Qualification and maintenance

~~~powershell
./scripts/Invoke-WorkspaceChecks.ps1
./scripts/Invoke-WorkspaceCi.ps1 -Suite WorkspaceLayout -SkipBuild
./scripts/Invoke-WorkspaceCi.ps1 -Suite CompanionSmoke -SmokeSuitesJson '["Core","Git","Vagrant"]' -SkipBuild
~~~

Local suites retain their dedicated visible monitor and saved terminal reports.
WorkspaceLayout covers 120-companion selection, XML properties/malformed inputs,
generation previews, multiple modules per group and targeted selection mutations.
Smokes check actual imports and native integration, and are recorded as smokes.

Source policy changes require their affected regression/property/fuzz/mutation
campaigns. A selective success does not establish global or publication
qualification. Publication retains the exact-revision, current-run All evidence
and explicit tag requirements.

Workflow documentation remains authored and reviewed. The workflow generator does
not refresh source-SHA review receipts. After reviewing the matching document,
regenerate the workflow graphs/index and run the shared gates.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
