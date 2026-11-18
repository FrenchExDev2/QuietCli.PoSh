# Update-Packages.psm1

<!-- script-source:begin -->
Source file: [`lib/Update-Packages.psm1`](../../../scripts/lib/Update-Packages.psm1)
<!-- script-source:end -->

Implements [Update-Packages.ps1](../Update-Packages.md). Exports only "Invoke-QuietScriptUpdatePackages". Imported without name checking; import defines the command without running the operation.

## Purpose

Keeps `Directory.Packages.props` (NuGet Central Package Management) current without proposing a
version that a target framework cannot restore. The repository pins some packages per framework with
a `Condition`, for example:

```xml
<PackageVersion Include="System.Management.Automation" Version="7.6.10" Condition="'$(TargetFramework)' == 'net10.0'" />
<PackageVersion Include="System.Management.Automation" Version="7.7.0"  Condition="'$(TargetFramework)' == 'net11.0'" />
```

System.Management.Automation 7.7.0 only ships `net11.0` assets, so moving the `net10.0` pin to 7.7.0
fails restore with NU1202. The module therefore reasons per **package x target framework**: one row
per pin and framework, and a proposal only when the newer version has assets for that framework.

## Usage

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = <parent of scripts/>,
    [string]$PropsPath = '',                 # <WorkspaceRoot>/Directory.Packages.props
    [switch]$Apply,
    [switch]$IncludePrerelease,
    [ValidateRange(1, 32)][int]$ParallelMax = 4,
    [switch]$NoRestore
)
```

- **No switch:** prints the table, lists the proposals and asks which ones to write (`1,3`, `all`,
  `none`; empty means all).
- **`-WhatIf`:** runs the whole analysis (MSBuild and nuget.org), selects every proposal, prints each
  one as `What if: Id [tfm] current -> latest` and writes nothing. It never prompts, so it works in CI.
- **`-Apply`:** selects every proposal without prompting, writes, then runs the restore check.
- **`-IncludePrerelease`:** also considers pre-release versions. A pin that is already a pre-release
  always considers them.
- **`-NoRestore`:** skips the restore check after writing.
- **`-ParallelMax`:** bounds concurrent MSBuild evaluations and nuget.org requests.

Example output (`-WhatIf`):

```
  Version  Status              Package [tfm]
  ───────  ──────────────────  ──────────────────────────────────────────
  0.57.2   ✓                   Spectre.Console [net10.0]
  0.57.2   ✓                   Spectre.Console [net11.0]
  7.6.10   ✓ (7.7.0: net11.0)  System.Management.Automation [net10.0]
  7.7.0    ✓                   System.Management.Automation [net11.0]
```

The gray note says that a newer version exists, but only for the listed frameworks.

## How it resolves

1. **Inventory (MSBuild).** It lists every tracked `*.csproj` (`git ls-files`, falling back to a scan
   that skips `.dotnet`, `.git`, `artifacts`, `bin` and `obj`). It then evaluates each project once per
   target framework:

   ```
   dotnet msbuild <proj> -nologo -getItem:PackageVersion -getItem:PackageReference -getProperty:TargetFramework -p:TargetFramework=<tfm>
   ```

   Each `Condition` resolves exactly as restore resolves it. Only `PackageVersion` items whose
   `DefiningProjectFullPath` is `PropsPath` are kept. `dotnet` comes from the repository-local SDK
   listed in `global.json` `sdk.paths` when it exists, else from `PATH` (CI with `setup-dotnet`).
2. **Rows.** Each `<PackageVersion>` element is matched to the evaluated pins by `Id` and `Version`.
   It gets one row per framework that references it. If nothing references it, every framework where
   it is defined gets a row, marked `(unreferenced)`.
3. **Versions.** One `v3-flatcontainer/{id}/index.json` request per distinct id.
4. **Frameworks of a candidate.** The module reads `registration5-gz-semver2/{id}/{version}.json`,
   then its `catalogEntry` leaf. The frameworks come from the `lib/<tfm>/`, `ref/<tfm>/` and
   `runtimes/*/lib/<tfm>/` paths in `packageEntries`. When there are none, it uses
   `dependencyGroups[].targetFramework`. Results are cached per id/version. The newest candidate of
   every element is prefetched in parallel.
5. **Compatibility.**
   - `netX.Y` and `netcoreappX.Y` are compatible with a target of the same or a later version.
   - A platform-specific framework (`net10.0-windows`) needs the same platform on the target.
   - `netstandard*` is compatible.
   - .NET Framework (`net4*`) is not.
   - A package with no recognized framework (tools, analyzers, content only) is treated as compatible.
     The restore check stays authoritative.
6. **Latest per row.** It walks the newer versions in descending SemVer order and stops at the first
   compatible one.
7. **Proposal per element.** It takes the lowest `Latest` across the element's rows, so a pin shared
   by several frameworks stays restorable for all of them. The proposal exists only if that version is
   newer than the current pin.

## Statuses

| Status | Meaning |
| --- | --- |
| `✓` | The pin is the newest compatible version (a gray note may name newer versions for other frameworks). |
| `↑ x.y.z` | `x.y.z` is newer and compatible with that framework. |
| `ambiguous` | Two elements share `Id` and `Version` under different conditions; they cannot be told apart from the evaluation, so nothing is proposed. |
| `no tfm` | No evaluated framework defines this pin (its condition matches none of them). |
| `fetch error` | nuget.org version list unavailable after three attempts. |
| `lookup error` | Catalog leaf unavailable for a candidate. |

Projects that fail evaluation are listed as `eval error <project>: <message>` after the table.

## Effects

- **Report:** reads the props file and the `.csproj` files, runs MSBuild evaluations (no build, no
  restore) and calls `api.nuget.org`. When `GITHUB_STEP_SUMMARY` is set, it appends the same table
  to the job summary in Markdown.
- **Write (behind `ShouldProcess`):**
  - only the `Version` attribute of the targeted elements changes. An element is targeted only when
    its `Include`, current `Version` and `Condition` all match, whatever the attribute order. Comments
    are skipped.
  - the UTF-8 BOM is preserved when the file had one.
  - it throws `PackageVersionRewriteMismatch` if the number of rewritten elements differs from the
    selection.
- **Restore check:** runs `dotnet restore` on every project that references an updated pin (this
  writes their `obj/` assets).
  - On any failure, it writes the original file back, prints the NU codes (for example NU1202) and
    throws `PackageRestoreFailed`.
  - `-NoRestore` skips the check.

## Findings

- **Report job stays green on errors.** `eval error`, `fetch error` and `lookup error` are printed,
  but the function still returns normally (lines 593-597). It throws only for a missing props file
  or project, a rewrite mismatch, or a failed restore. A dispatched `-WhatIf` can therefore succeed
  while some rows were never checked. The yellow "Some rows could not be checked" line (line 595) is
  the only signal.
- **Rollback leaves the obj/ assets behind.** A failed restore check rewrites the props file
  (line 652), but the `obj/project.assets.json` files of the projects that did restore keep the
  rejected versions until the next restore. That is harmless for the file in git, but a local build
  run right after a rollback without a restore can see the stale assets.
- **The compatibility rules are an approximation of NuGet's.** `Test-QuietTfmCompatible`
  (lines 31-54) does not model fallbacks such as `netcoreapp` to `netstandard2.1` priority,
  `portable-*` frameworks or `native`. It errs toward "compatible", and the restore check catches
  the rest. Packages with only `build/` or `analyzers/` content are always "compatible" (line 62).
- **Ambiguity by `Id` + `Version`.** Two elements with the same id and version under different
  conditions cannot be distinguished from MSBuild's output (lines 480-481) and are reported as
  `ambiguous` rather than guessed. Distinct versions per condition, the case this module exists for,
  are unaffected.
- **Synchronous file I/O.** The module uses `ReadAllBytes`, `ReadAllText`, `WriteAllText` and
  `AppendAllText` (lines 460-463, 590, 635, 652), not the async `.GetAwaiter().GetResult()`
  convention. The props file is small, so there is no practical impact, but it is inconsistent with
  the stated convention, like `Sync-Credits.psm1`.
- **`ForEach-Object <MemberName>` is unsafe under `-WhatIf`.** That form honors `ShouldProcess` and
  returns nothing under `-WhatIf`. The module uses scriptblocks (`ForEach-Object { $_.Tfm }`) for this
  reason. Any future edit must keep that form, or `-WhatIf` silently yields empty id lists.
- **Network trust.** Only `api.nuget.org` is contacted, over HTTPS, and responses are parsed as JSON.
  No secret is read or sent. Private feeds from `nuget.config` are not consulted, so a package
  published only there shows `fetch error`.
- **Test coverage.** No Pester test covers the internal helpers. They were checked manually:
  - TFM rules, for example net11 to net10 false and netstandard2.0 true;
  - SemVer ordering;
  - targeted rewrite across attribute orders and commented-out elements;
  - an end-to-end `-WhatIf` run and an `-Apply` run on a lowered pin.

## Verdict

Fit for purpose: it resolves CPM conditions the way restore does and never proposes a version a
framework cannot use. Any heuristic gap is caught by the restore check, with rollback. The
highest-priority improvement is to make the report fail, or at least exit non-zero, when rows could
not be checked, so a dispatched report cannot hide a nuget.org or evaluation outage. Pester coverage
of `Test-QuietTfmCompatible` and `Set-QuietPackageVersion` comes next.

<!-- script-contract:begin -->
## Execution contract

Purpose: Parses a NuGet or MSBuild target framework moniker into a family, a version and an optional platform.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
