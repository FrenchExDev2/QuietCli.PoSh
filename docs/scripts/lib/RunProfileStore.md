# RunProfileStore.psm1

## Purpose

Defines and enforces the file format for "run profiles": named, data-only `<Name>.profile.ps1` files that bind a target script (under `scripts/`) to a default parameter set, so that a benchmarking run (for example, `scripts/Invoke-RunProfile.ps1`) can be launched by name instead of by repeating a long argument list. The core safety property is that a profile file can never execute code — it is parsed in PowerShell's restricted language mode — so a malicious or corrupted `.profile.ps1` cannot do anything beyond declare data. This module is the schema/validation/IO layer; `scripts/New-RunProfile.ps1` is presumably the CLI front-end that calls `Write-RunProfile`/`ConvertTo-RunProfileSource`, and `scripts/Invoke-RunProfile.ps1` is the consumer that calls `Read-RunProfile`/`Merge-RunProfileArguments`/`Resolve-RunProfileTarget`. It is exercised directly by `RunProfiles.Tests.ps1` and targeted by multiple entries in `RunProfiles.Mutation.ps1`.

## Usage

Exported functions (all take an optional `-Directory` override; default profile directory is `scripts/RunProfiles`, default script directory is `scripts/`):
- `Get-RunProfileDirectory([string] $Directory)` / `Get-RunScriptDirectory([string] $Directory)` — path resolvers.
- `Test-RunProfileName([string] $Name)` — `$true` iff `$Name` matches `^[a-z0-9][a-z0-9-]{0,63}\z` (case-sensitive).
- `Get-RunProfilePath([string] $Name, [string] $Directory)` — Mandatory `$Name`; throws `RunProfileInvalidName` if invalid.
- `Get-RunProfileNames([string] $Directory)` — lists valid profile names found in a directory (empty array if the directory doesn't exist).
- `Test-RunProfileValue($Value)` — `$true` for string/bool/int/long, finite double, or (recursively) arrays of those.
- `Assert-RunProfile($Profile, [string] $ExpectedName)` — validates schema: must be a `[hashtable]`, keys restricted to `SchemaVersion, Name, Description, Script, Parameters`, `SchemaVersion` must equal `1`, `Name` must be a valid profile name (and match `$ExpectedName` if given), `Script` must match `^[A-Za-z0-9][A-Za-z0-9._-]*\.ps1\z`, `Parameters` must be a hashtable with valid parameter names/values.
- `Read-RunProfile([string] $Path)` (Mandatory) — reads text via `RunEncoding`, requires the file name to end in `.profile.ps1`, parses with `[scriptblock]::Create` + `CheckRestrictedLanguage` (no commands, only `$true/$false/$null` variables allowed), requires exactly one yielded hashtable value, validates it.
- `ConvertTo-RunProfileLiteral($Value)` / `ConvertTo-RunProfileSource([hashtable] $Profile)` — render a profile back to deterministic, sorted, culture-invariant PowerShell source text.
- `Write-RunProfile([hashtable] $Profile, [string] $Directory, [switch] $Force)` — writes the file, throws `RunProfileExists` unless `-Force`.
- `Merge-RunProfileArguments([hashtable] $Profile, [hashtable] $Arguments)` — caller arguments override profile defaults.
- `Resolve-RunProfileTarget([hashtable] $Profile, [string] $ScriptDirectory)` — throws `RunProfileTargetNotFound` if the declared `Script` doesn't exist under the script directory.
- `Assert-RunTargetParameters([string] $TargetPath, [hashtable] $Parameters)` (Mandatory both) — throws `RunProfileUnknownParameter` if a parameter key isn't declared by the target script.

Example:
```powershell
Import-Module ./scripts/lib/RunProfileStore.psm1
$profile = Read-RunProfile ./scripts/RunProfiles/coldstart-100.profile.ps1
$args = Merge-RunProfileArguments -Profile $profile -Arguments @{ Runs = 50 }
$target = Resolve-RunProfileTarget -Profile $profile
Assert-RunTargetParameters -TargetPath $target -Parameters $args
& $target @args
```

## Dependencies

- Imports `RunFormat.psm1` (for `ConvertTo-RunSingleQuoted`) and `RunEncoding.psm1` (for `Read-RunTextFile`/`Write-RunTextFile`), both siblings in `scripts/lib/`.
- Uses `[scriptblock]::Create` + `CheckRestrictedLanguage` (a .NET/PowerShell API, not an external tool) as its sole security boundary for untrusted profile content.
- `Assert-RunTargetParameters` calls `Get-Command -Name $TargetPath -CommandType ExternalScript`, which requires the target `.ps1` to be loadable/parseable by PowerShell itself.
- Filesystem-only; no network, no git, no native process.

## Side effects

- `Write-RunProfile` creates the profile directory if missing and writes/overwrites a `.profile.ps1` file (guarded by `-Force` unless the file doesn't already exist).
- All other exported functions are read-only / pure.

## Findings

- No bug found after review of the restricted-language parsing path (`Read-RunProfile`, lines 138-146): the combination of `CheckRestrictedLanguage` and a strict schema `Assert-RunProfile` is a reasonable defense against a `.profile.ps1` running arbitrary code, and the code correctly rejects more or less than one yielded value (line 144).
- DESIGN: `Test-RunProfileValue` (lines 86-99) accepts `[int]`/`[long]` but not `[int32]`/`[uint32]`/`[decimal]`; a profile author passing e.g. a `[byte]` count would get `RunProfileUnsupportedValue` with no indication in the error message of *why* (the thrown message at line 157 of `ConvertTo-RunProfileLiteral` reports `$Value.GetType().FullName`, which helps, but `Assert-RunProfile`'s own `RunProfileUnsupportedValue: $key` at line 122 does not report the offending type).
- CONVENTION: `Get-RunProfileNames` (lines 69-84) does `[IO.Path]::GetFileName($file).Substring(0, ...)` twice per iteration instead of computing it once into a local — a minor duplication, not a bug.
- DESIGN: `Assert-RunTargetParameters` (lines 242-256) resolves `Get-Command -CommandType ExternalScript` every call; for a profile-running loop over many profiles this re-parses the target script's `param()` block repeatedly with no caching, though this is unlikely to matter at the scale this tooling runs at (dozens of profiles, not thousands).
- Encoding/line-ending discipline is correctly delegated to `RunEncoding.psm1` throughout (`Read-RunProfile` via `Read-RunTextFile`, `Write-RunProfile` via `Write-RunTextFile`), consistent with repo convention.
- Testability: well covered — `RunProfiles.Tests.ps1` imports this module directly, and `RunProfiles.Mutation.ps1` carries mutation cases that touch the schema/parsing paths of this family (though the specific mutation list excerpt captured during this review names `RunStatistics.psm1`/`RunToolCache.psm1` entries more explicitly than `RunProfileStore.psm1` ones — a full audit of mutation coverage per-function was not performed here).

## Verdict

Solid, deliberately defensive design (restricted-language parsing is the right call for a file format that must never execute); no rework needed, and the only worthwhile improvement is enriching `RunProfileUnsupportedValue`/`RunProfileInvalidParameterName` error messages with the actual offending type/value for faster diagnosis.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Standard for run profiles: named, data-only PowerShell files that bind a script to a set of default arguments.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
