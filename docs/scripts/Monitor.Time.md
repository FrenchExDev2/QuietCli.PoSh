# Monitor.Time.ps1

## Purpose

Provides culture-independent elapsed-time computation and formatting for QuietCli2's read-only monitoring windows, so that a run's displayed duration (`1s`, `2m5s`, `1h5m`) is identical regardless of the terminal's current culture (French, English, etc.) and regardless of whether the timestamp came from a live `[DateTimeOffset]`, a `[DateTime]`, or a persisted ISO-8601 string read back out of a run's `status.json`. It is the business logic behind the `Duration`-style columns that the repo's UI conventions (AGENTS.md "Terminal UI" section) require, and is dot-sourced directly by `scripts/Watch-Tests.ps1` (line 10) to compute how long a watched test run has been active, and is asserted by a dedicated test case in `FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1` (`'monitor duration preserves November timestamps in French and English cultures'`, lines 605-621).

## Usage

Exported functions (plain dot-sourced script; no module manifest, no `Export-ModuleMember`):
- `ConvertTo-QuietMonitorTimestamp($Value)` — Mandatory, untyped. Passes through `[DateTimeOffset]` unchanged, wraps a `[DateTime]` in `[DateTimeOffset]::new(...)`, otherwise parses `[string]$Value` with `InvariantCulture` and `RoundtripKind`.
- `Get-QuietMonitorDuration` — `-StartedUtc` (Mandatory, untyped — accepts the three forms above), `-FinishedUtc` (optional, untyped; when `$null`/empty, the run is treated as still active), `-Now` (`[DateTimeOffset]`, default `[DateTimeOffset]::UtcNow`, injectable for deterministic tests). Returns a compact string: `"{h}h{m}m"` if ≥ 1 hour, `"{m}m{s}s"` if ≥ 1 minute, else `"{s}s"`.

Example:
```powershell
. ./scripts/Monitor.Time.ps1
Get-QuietMonitorDuration -StartedUtc '2026-11-04T20:00:00Z' -FinishedUtc '2026-11-04T20:02:05Z'   # '2m5s'
Get-QuietMonitorDuration -StartedUtc $status.StartedUtc -Now ([DateTimeOffset]::UtcNow)            # live/active run
```

## Dependencies

- No imports, no external tools; pure `[DateTimeOffset]`/`[Math]` logic over base class library types.
- Implicit contract: callers (e.g. `Watch-Tests.ps1`) supply `$StartedUtc`/`$FinishedUtc` values that originate from a run's persisted JSON status (parsed with `ConvertFrom-Json`, which yields plain `[string]` properties) or from live `[DateTimeOffset]` values — this module must handle both, and does.

## Side effects

- None; purely computational, no filesystem/process/network interaction.

## Findings

- No bug found: the culture-independence goal is correctly achieved by always parsing with `[Globalization.CultureInfo]::InvariantCulture` (line 12) regardless of `[Globalization.CultureInfo]::CurrentCulture`, and the dedicated test (lines 605-621 of the test module) explicitly exercises this under both `fr-FR` and `en-US`, which is exactly the right kind of targeted regression test for a culture bug class.
- CONVENTION: the file has no `#requires -Version` directive, unlike almost every other file reviewed in this set (`RunStatistics.psm1`, `RunEncoding.psm1`, etc. all declare `#requires -Version 7.6`). This is a minor consistency gap — if this script relies on any PowerShell 7+-only syntax or type behavior, there's no guard preventing it from being dot-sourced under an older/incompatible host.
- DESIGN: `Get-QuietMonitorDuration`'s active-run branch (line 27) checks `$null -ne $FinishedUtc -and ![string]::IsNullOrEmpty([string]$FinishedUtc)` — casting an arbitrary `$FinishedUtc` to `[string]` before the empty check is slightly unusual (it would coerce a non-string, non-null, non-DateTime/DateTimeOffset value, e.g. an empty array, into some string representation rather than rejecting it outright), but in practice the only values ever passed are `$null`, empty string, `[DateTime]`, or `[DateTimeOffset]`, so this is a latent looseness rather than an observed bug.
- No French/English comment issue: the file header is itself in French ("Objectif : Calculer les durées du moniteur indépendamment de la culture du terminal.", line 1) — this directly contradicts the repo's explicit "Language: Always write code and comments in english" rule in both `AGENTS.md` and `CLAUDE.md`. CONVENTION: this is a clear, specific violation (file-level comment on line 1 of `scripts/Monitor.Time.ps1`), even though every function's own `.SYNOPSIS`/parameter documentation inside the file is correctly written in English.
- Testability: the one existing test is solid (covers both cultures, both single-value and `Now`-based duration calculation, and JSON round-trip of ISO timestamps), but there is no test for the hour-formatting branch (`≥ 3600` seconds, line 29) or for malformed/unparseable `$StartedUtc` strings (which would currently bubble up as an unhandled `[FormatException]` from `[DateTimeOffset]::Parse`, with no guard or friendlier error message) — a missing-coverage gap for the boundary and failure paths.

## Verdict

Correct and appropriately tested for its primary culture-independence goal, but needs two small fixes: translate the French file-header comment to English per the repo's language rule, and add the (missing) `#requires -Version 7.6` directive for consistency with every sibling file.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
