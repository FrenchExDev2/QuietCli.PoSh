# RunEncoding.psm1 (lib)

## Purpose

Centralizes the single text-encoding policy for the run-profile tooling, with two deliberately distinct contracts documented at the top of the file (lines 6–11): files on disk are always strict UTF-8 without BOM with LF line endings (no silent replacement of malformed bytes), while the console/process boundary encoding is a separate, explicit, configurable choice (`utf-8` or `oem`) because a mismatch there must be a deliberate decision, not a hardcoded default. It solves the "which encoding wins" ambiguity that otherwise causes mojibake or silently-corrupted profile files across different terminal code pages. It underlies every other `lib/*.psm1` file that touches text: `RunLog.psm1` imports it directly (`Import-Module (Join-Path $PSScriptRoot 'RunEncoding.psm1')`, that file's line 12) for its `FileLogSink`, and `RunProfileStore.psm1`/`RunProfiler.psm1` are plausible further consumers given the shared `lib/` naming convention (not individually confirmed by direct grep in this review).

## Usage

Exported functions (`Export-ModuleMember`, line 96): `Read-RunTextFile`, `Write-RunTextFile`, `Add-RunTextLine`, `ConvertTo-RunLf`, `Resolve-RunConsoleEncoding`, `Set-RunConsoleEncoding`.

Key signatures:
- `Read-RunTextFile -Path <string>` — reads strictly as UTF-8 (`[Text.UTF8Encoding]::new($false, $true)`, line 14 — the second `$true` enables throw-on-invalid-bytes); throws rather than substituting replacement characters on malformed input.
- `Write-RunTextFile -Path <string> -Text <string>` — writes UTF-8 without BOM, normalizing all line endings to LF first via `ConvertTo-RunLf`.
- `Add-RunTextLine -Path <string> -Line <string>` — appends one LF-terminated line, UTF-8 without BOM.
- `ConvertTo-RunLf -Text <string>` — normalizes CRLF and lone CR to LF.
- `Resolve-RunConsoleEncoding -Name <string>` — maps `'utf-8'` or `'oem'` (case-insensitive) to an `[Text.Encoding]`; throws `RunConsoleEncodingUnknown` for anything else.
- `Set-RunConsoleEncoding -Name <string>` — applies the resolved encoding to `[Console]::OutputEncoding` and `$global:OutputEncoding` (affecting how native command output is decoded) and returns it.

Example:
```powershell
Import-Module ./scripts/lib/RunEncoding.psm1
Set-RunConsoleEncoding -Name 'utf-8'
Write-RunTextFile -Path './profile.json' -Text $json
```

## Dependencies

- No dot-sourcing or `Import-Module` of other repository files — purely built on `[Text.UTF8Encoding]`, `[IO.File]`, `[Console]`, and `[Globalization.CultureInfo]`.
- No external tool or network dependency.

## Side effects

- `Write-RunTextFile`/`Add-RunTextLine` mutate the target file on disk (full overwrite or append, respectively).
- `Set-RunConsoleEncoding` mutates process-global state: `[Console]::OutputEncoding` and `$global:OutputEncoding` — this affects every subsequent native-command pipe decode in the current session, which is process-wide and persists until changed again or the process exits.

## Findings

- No bug found: both module-level encoding fields (`$script:Utf8Strict`, `$script:Utf8Writer`, lines 14–15) are correctly configured as BOM-less, and the strict reader's `throwOnInvalidBytes: $true` second constructor argument is exactly what the module's own doc comment promises ("malformed bytes are an error, never replacement characters").
- DESIGN: `$script:Utf8Strict` and `$script:Utf8Writer` are constructed identically (both `[Text.UTF8Encoding]::new($false, $true)`, lines 14–15) — there is no functional difference between them, so having two separately named script-scoped fields for the same configuration is a very minor duplication (two names, one concept) rather than a real issue; a single `$script:Utf8` would be equally correct and slightly clearer about intent (reader vs. writer use is already expressed by which functions use which field, not by the encoding itself differing).
- CONVENTION: Exemplary use of the async-then-block pattern throughout — `[IO.File]::ReadAllTextAsync(...).GetAwaiter().GetResult()` (line 25), `[IO.File]::WriteAllTextAsync(...).GetAwaiter().GetResult()` (line 49), `[IO.File]::AppendAllTextAsync(...).GetAwaiter().GetResult()` (line 62) — this file is the model implementation of AGENTS.md's "even in sync PowerShell use `.GetAwaiter().GetResult()`" rule, and other files in this review (e.g. `DevelopmentWorkstation.psm1`'s `Invoke-WebRequest` call) could be held to this same standard.
- Testability: No test file specifically named for `RunEncoding.psm1` was found, but its functions are plausibly exercised indirectly by the `RunProfiles.*` suites (which depend on `RunLog.psm1`, which imports this module) — direct, dedicated unit tests for `Resolve-RunConsoleEncoding`'s unknown-name throw path or `ConvertTo-RunLf`'s mixed-line-ending normalization were not found as named test cases.
- No input validation gap found: `Resolve-RunConsoleEncoding`'s `default` branch correctly rejects any unrecognized name rather than silently falling back to a guessed encoding (line 77).

## Verdict

This module is a clean, well-isolated, convention-compliant encoding policy with no bugs found; it is in fact the best example in this review of the repository's own async-I/O and UTF-8 rules being followed to the letter, so no rework is needed.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Single text-encoding policy of the run-profile tooling.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
