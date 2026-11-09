# Update-QuietDependencies.ps1

## Purpose

Establishes (or refreshes) `FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json` — a
content-addressed record binding every shipped native/managed resource file (sqlite native library,
ML tokenizer DLLs, the PTY transport binary) to the exact third-party NuGet package/version it came
from, plus a copy of that package's license text. The business problem is supply-chain provenance:
the repository ships pre-built third-party binaries (not restored from NuGet at build time for some of
these), so there needs to be an explicit, auditable record of "this exact file, by this hash, is
claimed to be this exact package version, and here is its license" — without ever downloading anything
itself (the doc comment and the returned object's `Downloaded=$false` field both emphasize this). It
is a manually-invoked maintenance operation: "Updates and advisory review are explicit maintenance
operations" is written directly into the lock file's own `Policy` field (line 50). No other script in
`scripts/` calls it, and no CI workflow or test file was found referencing it — it is presumably run
by a maintainer by hand whenever a new reference module (passed via `-ReferenceRoot`) needs its
resources re-attributed into this repository's `FrenchExDev2.QuietCli.Core.PoSh` module.

## Usage

```
[CmdletBinding()]param([Parameter(Mandatory)][string]$ReferenceRoot,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
```

- `ReferenceRoot` (string, mandatory) — an existing source module containing
  `resources/dependencies.json` (the trusted source manifest) and a `third_party/` directory with
  license files.
- `WorkspaceRoot` (string, optional) — this QuietCli2 workspace; defaults to the script's parent
  directory. The target module is hardcoded as `FrenchExDev2.QuietCli.Core.PoSh` under it (line 14).

Example:

```powershell
./scripts/Update-QuietDependencies.ps1 -ReferenceRoot C:\path\to\some\reference\module
```

## Dependencies

- Dot-sources `Common.ps1` (line 12), which transitively provides `Write-WorkspaceJson` (used at line
  50) plus `Invoke-CiProcess`/`SourceIdentity.ps1`/`RuntimeTargets.ps1`, none of which this script
  otherwise uses directly.
- No external process is shelled out to.
- Filesystem assumptions: `ReferenceRoot/resources/dependencies.json` must exist and be valid JSON
  with `Files` and `Packages` properties (line 13); `WorkspaceRoot/FrenchExDev2.QuietCli.Core.PoSh/resources`
  must exist and contain the resource files to be attributed (line 16); for each resource file
  encountered, `ReferenceRoot/third_party/<package-or-'transport'>/` must exist and contain its
  license file(s) (line 40, 41) — an `ItemNotFoundException` is thrown uncaught if any of these are
  missing, with no script-level validation or friendlier error message first.

## Side effects

- Creates/overwrites `FrenchExDev2.QuietCli.Core.PoSh/third_party/<package>/` directories, copying and
  LF-normalizing (`\r\n`→`\n`, `\r`→`\n`, line 41) each discovered license file into them, using UTF-8
  without BOM (line 42).
- Overwrites `FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json` entirely (line 50),
  via `Write-WorkspaceJson` (atomic rename).
- Returns a `[pscustomobject]` summary (`Resources`, `Packages`, `Downloaded=$false`) to the pipeline.
- No network calls, no package downloads — purely a local file-copy/hash/attribution pass, as
  documented.

## Findings

- BUG: The `switch` statement mapping a managed resource file name to its NuGet package id (lines
  24-30) has a hardcoded, closed list of exactly four known DLL names
  (`Microsoft.Bcl.Memory.dll`, `Microsoft.ML.Tokenizers.dll`, two tokenizer-data DLLs) with a
  `default {throw 'UnknownManagedResource'}` fallback. Any new managed dependency added to
  `resources/tokenizers/` in the future *must* have this switch edited by hand, or the entire script
  aborts with an opaque error for every file, not just the new one — this is a maintenance trap and a
  DRY violation (the mapping duplicates information that, in principle, could be read from the
  resource's own assembly metadata or from `dependencies.json` itself, rather than re-encoded as a
  parallel, hand-maintained lookup table in this script).
- DESIGN: resource classification is done by fragile string-matching on relative *path* prefixes
  (`resources/runtime/*` → `sqlitepclraw.lib.e_sqlite3`, `resources/transport/*` →
  `quietcli-pty`, line 23) combined with the filename `switch` above for everything else. There is no
  single authoritative mapping file read into the script; the mapping is scattered across path
  conventions and a hardcoded switch, making this script to that extent the single point of truth for
  "which package does this file belong to" — fragile if the directory layout under `resources/` is
  ever reorganized.
- DESIGN: line 18's `$original=$relative.Replace('resources/tokenizers/','resources/runtime/')`
  renames the comparison path specifically to match how the *reference* manifest apparently names
  these same files (under `resources/runtime/` instead of `resources/tokenizers/`), silently bridging
  a naming inconsistency between the reference module and this one. This kind of silent, name-specific
  patch is exactly the sort of implicit coupling that breaks quietly when either side's layout changes
  — a comment explaining *why* the rename is needed would help, but there isn't one.
- CONVENTION: all file I/O in the license-copy loop uses the async
  `ReadAllTextAsync(...).GetAwaiter().GetResult()` / `WriteAllTextAsync(...).GetAwaiter().GetResult()`
  pattern (lines 41-42) correctly, consistent with AGENTS.md's async-even-in-sync rule. The hashing
  calls (`Get-FileHash`, lines 19, 44) remain synchronous, as they do throughout this entire scripts
  folder (no script in this batch uses an async hashing API) — a minor, repository-wide inconsistency
  rather than one specific to this file.
- Testability gap: no Pester test anywhere in the two `*.Tests.PoSh` projects references
  `Update-QuietDependencies.ps1` (confirmed by grep — zero hits across the whole repository outside
  this script's own content). Given this script directly produces a provenance/license record that
  downstream consumers may treat as authoritative (the lock file's own `Provenance` field says
  "Content matches the inspected local source manifest; package author authenticity is not inferred
  from a checksum" — i.e. it is explicitly *not* a strong authenticity guarantee), the complete absence
  of any test (not even a smoke test confirming the generated JSON schema) for the one script that
  produces this record is a real coverage gap, and the hardest one to retrofit safely since it touches
  licensing/compliance data.
- No other security concern beyond the explicitly-acknowledged-and-documented one above (hash does not
  authenticate authorship) — this script does not download anything, so there's no supply-chain
  download-time attack surface here, only the "garbage in" risk that `-ReferenceRoot` points at
  something untrustworthy, which is the caller's responsibility per the doc comment's warning.

## Verdict

A reasonable manual-maintenance tool for its narrow purpose, but it has zero automated test coverage
and its package-classification logic (the hardcoded filename `switch`) is a maintenance trap that will
throw an opaque `UnknownManagedResource` the moment a new managed dependency is added — the
highest-priority fix is making that mapping data-driven (read from the reference manifest or an
explicit mapping file) instead of a hardcoded switch inside this script.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
