# WorkspaceProjects.psm1

## Library boundary

Located at `scripts/lib/WorkspaceProjects.psm1`. Load with `Import-Module ([IO.Path]::Combine($root,'scripts/lib/WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop`. Import defines functions and explicit dependencies without running business operations. Paths use `System.IO.Path`. Effects remain owned by the calling operation and its preview contract.

Explicit export surface:

```powershell
Export-ModuleMember -Function 'Get-QuietWorkspaceProjects','Get-QuietWorkspaceBuildProjects','Get-QuietWorkspaceDotNetHost','Get-QuietWorkspaceBuildSelection','Get-QuietWorkspaceTestSuites','Get-QuietWorkspacePackages','Get-QuietWorkspaceSuiteNames','New-QuietWorkspaceSuiteParameter','Get-QuietWorkspaceSuiteSelection'
```


Get-QuietWorkspaceDotNetHost only reads an existing private SDK receipt for the global.json version, matching the native RID and the stable framework declared by the fixture BuildProjects entry. Test workers use that host without installation or profile changes. Each owning test manifest's TestCatalogue.Runner takes precedence over naming conventions; the YAML must agree.

## Qualification coverage

When the CI catalogue exists, every discovered business module must declare its owning suite, test module and runner there. Undeclared newly generated companions fail before suite execution; All cannot silently omit them. Dedicated integration-only test projects remain supported.

## Scoped CI execution

Get-QuietWorkspaceBuildSelection resolves inert test manifests and transitive RequiredModules, rejecting missing local dependencies. Core selects only Core/Core.Tests. The Module parameter set resolves exact package roots and their dependencies through that same closure; Core packaging never requires Git outputs. Distribution selects its own private test manifest and Core.Tests. Tooling and public package campaigns retain the complete build; RunProfiles selects Core helpers only. Tooling is an orchestration mode, separate from product All.

When build/companions.yml exists, suite names and runner selection come from its independent
suite declarations through lib/CiCompanions.psm1. Integration suites can name a dedicated exported
runner and require multiple products without reverse product dependencies. Manifest discovery
remains available for package/build inventory and fixtures without the YAML.

## Purpose

The foundational project-discovery library for the entire `scripts/` orchestration layer: it answers
"what modules exist in this monorepo, in what dependency order, which are test companions of which
business module, and which are allowed to be published" purely by reading each project directory's
`.psd1` manifest as inert data — explicitly *never* importing any module code during discovery (the
fixture comment in its own test, "Creates an inert manifest and a module that would fail if discovery
imported it," underscores how deliberate this is). This is the business problem of a multi-package
monorepo needing a safe, side-effect-free way to enumerate "FrenchExDev2.QuietCli.*.PoSh" project
directories, build their dependency DAG, and classify publishability — without ever executing
untrusted or not-yet-built module code just to find out what exists. It is imported, directly or
transitively via `Common.ps1`, by nearly every script in this folder that needs the project catalogue:
confirmed direct imported sites include `Sync-Credits.ps1:40`, `Test-WorkspacePackage.ps1:96`,
`SourceIdentity.ps1:2` (making it transitively available through `Common.ps1` to everything that loads
that), and it is the subject of a dedicated, substantial Pester test file,
`FrenchExDev2.QuietCli.Core.Tests.PoSh\WorkspaceProjects.Tests.ps1`.

## Usage

This is a pure function library with no top-level `param()` — it is loaded via imported:

```powershell
Import-Module (Join-Path $PSScriptRoot 'WorkspaceProjects.psm1') -DisableNameChecking -ErrorAction Stop
```

Exported functions:

- `Get-QuietWorkspaceBuildProjects -WorkspaceRoot <string>` — returns declared portable `Package`, `Project`, `TargetFramework` and `Output` rows from `PrivateData.QuietCli.BuildProjects`. The shared solution build and binary identity consume this same function. Missing declarations mean a pure PowerShell package with no compiled outputs. Invalid paths, frameworks absent from the project XML, duplicate/overlapping outputs, links and DTDs fail. See [compiled distributions](../../README-workspace-projects.md#compiled-distributions) for a new-consumer example and the RAC-BUILD-001 contract.
- `Get-QuietWorkspaceProjects -WorkspaceRoot <string> (mandatory)` — discovers, order-validates
  (topological sort by `RequiredModules`), and returns every `FrenchExDev2.QuietCli.*.PoSh` project
  directory under `WorkspaceRoot` as a `[pscustomobject]` with `Name`, `IsTest`, `Suite`,
  `TestsModule`, `TestCommand`, `RequiredModules`, `Dependencies`, `Manifest`.
- `Get-QuietWorkspaceTestSuites -WorkspaceRoot <string> (mandatory)` — resolves each business module
  to its declared test companion and exported runner command name.
- `Get-QuietWorkspacePackages [-WorkspaceRoot <string>] [-Publishable] [-NonPublishable]` —
  `WorkspaceRoot` optional (defaults to the script's own parent directory); `Publishable`/
  `NonPublishable` switches are mutually exclusive (throws `WorkspacePackageFiltersAreExclusive` if
  both given).
- `Get-QuietWorkspaceSuiteNames -WorkspaceRoot <string> (mandatory) [-Scope <'Host'|'Container'>='Host']`.
- `New-QuietWorkspaceSuiteParameter -WorkspaceRoot <string> (mandatory) [-Scope <'Host'|'Container'>='Host']`
  — builds a dynamic `Suite` parameter with native `ValidateSet` tab-completion for a calling launcher
  script.
- `Get-QuietWorkspaceSuiteSelection -WorkspaceRoot <string> (mandatory) [-Suite <string>='All']`.

Example:

```powershell
Import-Module (Join-Path $PSScriptRoot 'WorkspaceProjects.psm1') -DisableNameChecking -ErrorAction Stop
$projects = Get-QuietWorkspaceProjects -WorkspaceRoot 'C:\code\...\FrenchExDev2.QuietCli.PoSh'
```

## Dependencies

- No imported files and no external process — entirely self-contained PowerShell using only
  `Get-ChildItem`, `Import-PowerShellDataFile`, and `[IO.File]::ReadAllTextAsync`.
- Filesystem assumption: every discovered project directory must contain a `.psd1` manifest named
  exactly `<DirectoryName>.psd1` (line 18-19) with a valid, UTF-8, strict (`[Text.UTF8Encoding]::new($false,$true)`,
  line 22) encoding; a reparse-point (symlinked) project directory or manifest file is explicitly
  rejected (lines 16, 20).

## Side effects

- None — this is a pure, read-only discovery library. It never writes a file, never imports a module,
  never shells out. The strongest guarantee it makes (and the one its own test fixture is specifically
  designed to verify) is that discovery cannot accidentally execute a project's module code.

## Findings

- No bugs found in the topological sort (`Get-QuietWorkspaceProjects`, lines 39-47): it correctly
  detects and throws `WorkspaceProjectDependencyCycle` when no progress can be made in a full pass,
  rather than looping forever or silently returning a partial/incorrectly-ordered list.
- DESIGN: `Get-QuietWorkspaceProjects` infers whether a project is a test companion purely from a
  naming convention — `$directory.Name.EndsWith('.Tests.PoSh', ...)` (line 26) — rather than from any
  explicit manifest declaration. This is a reasonable, simple convention, but it means renaming a
  project in a way that happens to end in `.Tests.PoSh` (or not) silently changes its classification
  with no manifest-level override available; a module that is a test companion but doesn't follow the
  naming convention (or vice versa) would be misclassified with no way to correct it short of
  renaming the directory.
- DESIGN: `Suite` is derived by string-slicing the directory name
  (`$directory.Name.Substring('FrenchExDev2.QuietCli.'.Length, ...)`, line 27) — this assumes every
  non-test project name begins with the exact literal prefix `FrenchExDev2.QuietCli.` and ends with
  the exact literal suffix `.PoSh`, both hardcoded as string literals (also repeated, separately, in
  the companion `-notlike 'FrenchExDev2.QuietCli.*.PoSh'` filter at line 15). The prefix/suffix
  convention is duplicated as two independent literals rather than defined once — a minor DRY
  violation; if the project naming convention ever changed, both spots would need updating in lockstep.
- No issue found with `Get-QuietWorkspacePackages`'s publishability classification (lines 86-100): the
  explicit `Publishable` boolean-type check (line 92: throws `WorkspacePublishableMustBeBoolean` if
  present but not a bool) and the mutually-exclusive filter switches are both correctly guarded, and
  the package-name format is validated by regex (line 96) before being trusted downstream.
- CONVENTION: this file does use the async-read pattern for manifest-encoding validation
  (`ReadAllTextAsync(...).GetAwaiter().GetResult()`, line 22), consistent with AGENTS.md — one of the
  few scripts in this batch that is fully compliant with that specific rule throughout its body.
- Testability: this is the best-tested script in the entire batch. `WorkspaceProjects.Tests.ps1`
  defines `New-QuietWorkspaceFixtureProject` (synthetic manifests whose `.psm1` deliberately
  `throw`s if ever imported — directly proving discovery never executes module code) and
  `Test-QuietWorkspaceProjects`, which the function/parameter names (`Properties`, `FuzzInputs`,
  explicit `Seed=44183`) strongly indicate is a genuine property-based/fuzz test with a fixed,
  reproducible seed, plus "targeted mutants" per its own doc comment — i.e. this script already has
  exactly the property+fuzz+mutation coverage AGENTS.md's testing strategy calls for, unlike every
  other script in this review batch. No further coverage gap was identified here.
- No security concern: all inputs are local, trusted repository manifests; the explicit
  reparse-point/symlink rejection (lines 16, 20) is itself a thoughtful defensive measure against a
  manifest directory being swapped out via a symlink between discovery passes.

## Verdict

This is the best-designed and best-tested script in the entire review batch — no bug, no missing test
coverage, and it is the one file that actually gets the property/fuzz/mutation testing strategy
AGENTS.md mandates. The only improvement worth making is low-priority: centralize the
`FrenchExDev2.QuietCli.` / `.PoSh` naming-convention literals (currently duplicated at lines 15 and 27)
into one constant so the convention only needs updating in one place if it ever changes.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

## .NET tooling review

Get-QuietWorkspaceSuiteNames exposes DotNet as a host-only focused automation suite. It is not a new business module or Gallery package and is not silently added to Core/All release qualification. Source suite-name validation continues to reject a companion manifest colliding with a reserved focused suite name.

<!-- script-contract:begin -->
## Execution contract

Purpose: Discovers inert module manifests and orders local projects by their declared dependencies.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

Read-only property projections use script blocks so metadata remains available during WhatIf; mutating operations retain their existing operation guards.
