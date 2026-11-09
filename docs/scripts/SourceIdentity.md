# SourceIdentity.ps1

## Purpose

Provides the shared primitives that give the QuietCli2 monorepo a deterministic, content-addressed
identity for its source files and compiled outputs. It answers three recurring business questions:
"what exactly did we build from" (`Get-QuietSourceFiles`, `Get-QuietManifestDigest`,
`Get-QuietBinaryInputs`), "did the compiled output actually come from those exact sources"
(`Write-QuietBuildManifest`, `Test-QuietBuildManifest`), and "what is the full, repository-aware
identity of this checkout" (`Get-QuietWorkspaceIdentity`). It is never run directly; it is dot-sourced
as a library. `Common.ps1:4` dot-sources it unconditionally, which means almost every orchestration
script in `scripts/` (build, CI, lock, package, workstation scripts) picks it up transitively through
`Common.ps1`. `Update-WorkspaceLock.ps1:10` and `Update-QuietDependencies.ps1` (via `Common.ps1`) call
`Get-QuietWorkspaceIdentity` directly to produce `repositories.lock.json`.

## Usage

This is a function library, not an invocable script — it has no top-level `param()` block and takes no
command-line arguments. It is loaded with:

```powershell
. (Join-Path $PSScriptRoot 'SourceIdentity.ps1')
```

Exported functions and their parameters:

- `Get-QuietSourceFiles -Root <string> [-ExcludeChildren <string[]>]` — `Root` (mandatory-by-convention,
  string, no default) is the directory to enumerate; `ExcludeChildren` (string array, default `@()`)
  lists top-level child names to skip.
- `Get-QuietPeMachine -Path <string>` — path to a PE (.exe/.dll) file.
- `Get-QuietManifestDigest -Files <object[]>` — manifest records with `Path`/`SHA256` properties.
- `Get-QuietBinaryInputs -WorkspaceRoot <string> -Project <string>` — workspace root and a relative
  project path (e.g. `FrenchExDev2.QuietCli.Core.PoSh/engine`).
- `Write-QuietBuildManifest -WorkspaceRoot <string> -Project <string> -Output <string> -Inputs <object[]>
  (mandatory) [-Configuration <string>='Release'] [-RuntimeIdentifier <string>='portable']
  [-PlatformTarget <string>='AnyCPU']`.
- `Test-QuietBuildManifest -WorkspaceRoot <string> -Output <string>`.
- `Read-QuietRepositoryValue -Path <string> -Arguments <string[]>` — runs one read-only `git` argument
  vector and returns trimmed stdout, or `$null` on failure.
- `Get-QuietWorkspaceIdentity -WorkspaceRoot <string> [-IncludeBinaries]`.

Example:

```powershell
. (Join-Path $PSScriptRoot 'SourceIdentity.ps1')
$identity = Get-QuietWorkspaceIdentity -WorkspaceRoot 'C:\code\...\FrenchExDev2.QuietCli.PoSh' -IncludeBinaries
```

## Dependencies

- Dot-sources `WorkspaceProjects.ps1` (line 2) for `Get-QuietWorkspaceProjects`.
- Calls `Invoke-CiProcess` (defined in `Ci.Process.ps1`) for every `git` invocation — but does not
  dot-source `Ci.Process.ps1` itself; it relies on the caller (in practice `Common.ps1`) having already
  loaded it. Calling this file standalone without `Ci.Process.ps1` already in scope will fail at
  runtime with a "command not found" error on `Invoke-CiProcess`.
- Calls `Write-WorkspaceJson` (defined in `Common.ps1`) from `Write-QuietBuildManifest` — again without
  dot-sourcing `Common.ps1`, creating the same implicit-load-order dependency.
- Calls `Get-QuietRuntimeTargets` / `Assert-QuietRuntimePublication` (defined in `RuntimeTargets.ps1`)
  from `Test-QuietBuildManifest` and `Get-QuietWorkspaceIdentity` — same implicit dependency.
- Shells out to `git` (`rev-parse`, `remote get-url`, `status --porcelain=v1`, `ls-files`).
- Filesystem assumptions: expects `global.json`, `FrenchExDev2.QuietCli.Core.PoSh/protocol.json`, and
  `Directory.Packages.props` to exist directly under `WorkspaceRoot` (line 76-79); throws uncaught
  `Get-Item`/`Get-FileHash` errors if any is missing.

## Side effects

- Read-only for `Get-QuietSourceFiles`, `Get-QuietPeMachine`, `Get-QuietManifestDigest`,
  `Get-QuietBinaryInputs`, `Test-QuietBuildManifest`, `Read-QuietRepositoryValue`,
  `Get-QuietWorkspaceIdentity` — no filesystem writes, only reads and hashing, plus read-only `git`
  calls (`rev-parse`, `remote get-url`, `status --porcelain`, `ls-files`).
- `Write-QuietBuildManifest` writes `build-manifest.json` into the given `Output` directory (line 105).
  This is the only mutating function in the file.

## Findings

- BUG: `Get-QuietSourceFiles` (line 20) special-cases a directory literally named `lib` with
  `$item.Name -eq 'lib' -and $item.FullName -ne (Join-Path $rootPath 'scripts/lib')`. This hardcodes a
  path relative to the *script's own repo layout* (`scripts/lib`) inside a generic source-enumeration
  helper that is also called with arbitrary module roots (e.g. `FrenchExDev2.QuietCli.Core.PoSh`, whose
  compiled binaries live at `<module>/lib/...` — see `Get-QuietWorkspaceIdentity` line 175-178). Any
  module whose own `lib` directory is *not* `scripts/lib` gets its entire `lib/` tree included in the
  source hash, i.e. compiled binaries get folded into "source" identity for every module except the
  orchestration scripts folder. This looks like a copy/paste special case that was never generalized,
  and it is easy to get wrong when a new module adds a `lib` folder.
- DESIGN: The file exercises an implicit dot-source order dependency on `Ci.Process.ps1`,
  `Common.ps1`, and `RuntimeTargets.ps1` without declaring or asserting it (no `Get-Command
  Invoke-CiProcess -ErrorAction SilentlyContinue` guard, no explicit dot-source of those files). This
  violates the modular-boundary principle: a reader of `SourceIdentity.ps1` in isolation cannot tell
  it needs those three other files loaded first, and the only script that happens to load them in the
  right order is `Common.ps1`. A standalone `. SourceIdentity.ps1` followed by a call to
  `Get-QuietWorkspaceIdentity` throws a late, confusing "command not found" rather than a clear
  dependency error.
- CONVENTION: Several hot loops use synchronous `Get-FileHash`/`Get-Item`/`Get-ChildItem` calls (lines
  28, 75-79, 104, 120-130) rather than async I/O with `.GetAwaiter().GetResult()` as AGENTS.md
  prescribes ("even in sync PowerShell use `.GetAwaiter().GetResult()`"). For a function that hashes
  every source file in the repository on every lock/build/CI run, this is also a potential performance
  concern (synchronous, single-threaded hashing of potentially thousands of files) though not
  incorrect.
- DESIGN: `Get-QuietBinaryInputs` (lines 70-74) hardcodes project-name pattern matches
  (`'engine-tests'`, `'recall-tools'`, `'FrenchExDev2.QuietCli.Git.Tests.PoSh/parser-tests/*'`) to decide
  which extra source roots feed a given project's build manifest. Adding a new cross-module
  "engine"-style dependency requires editing this generic identity library rather than declaring the
  extra root in the consuming project's own manifest — a DRY/SOLID violation (business knowledge about
  specific test projects leaking into a shared infrastructure file).
- Testability gap: no dedicated Pester test file under the `*.Tests.PoSh` projects exercises
  `Get-QuietSourceFiles`, `Get-QuietManifestDigest`, `Write-QuietBuildManifest`,
  `Test-QuietBuildManifest`, or `Get-QuietWorkspaceIdentity` directly (searched `*.Tests.ps1` under
  `FrenchExDev2.QuietCli.Core.Tests.PoSh` and `FrenchExDev2.QuietCli.Git.Tests.PoSh` for these names —
  no hits). These functions sit on the critical path of every lock/build/CI/package step and determine
  whether a "stale build" is correctly rejected, yet have no property, fuzz, or mutation coverage of
  their own — only indirect exercise through whichever orchestration script happens to call them.
  Given `AGENTS.md`'s mandatory property/fuzz/mutation testing strategy, this is a real coverage gap,
  not a minor one: a bug in `Get-QuietManifestDigest`'s ordering/hashing (e.g. the `lib` special case
  above) would not be caught by any existing test.
- No issues found with: the SHA-256-based manifest digest algorithm itself (sorted, ordinal, newline
  joined — deterministic as documented), the reparse-point rejection in `Get-QuietSourceFiles` (line
  23), or the atomic-rename-safe behavior of `Write-WorkspaceJson` that `Write-QuietBuildManifest`
  relies on (that safety lives in `Common.ps1`, reviewed separately).

## Verdict

Functionally solid and the core hashing/digest design is sound, but the undeclared dot-source ordering
dependency (DESIGN) and the hardcoded `scripts/lib` exception inside a generic source enumerator (BUG)
are the two issues worth fixing first — the latter because it can silently fold compiled binaries into
a module's "source" identity, defeating the stale-build detection this file exists to provide. Add a
guard or explicit dot-source list at the top of the file, and parameterize the `lib` exclusion by an
explicit "treat this directory as generated" list rather than a literal path string.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
