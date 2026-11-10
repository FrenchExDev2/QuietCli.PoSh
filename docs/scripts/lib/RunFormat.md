# RunFormat.psm1 (lib)

## Purpose

Shared presentation helpers for the run-profile tooling: compact human-readable durations and data sizes, Unicode box-drawing table rendering with dynamic column shrinking, a counters-to-table convenience wrapper, and safe PowerShell single-quoted string-literal generation. It solves "every script that prints a report or a table should look the same and not duplicate the same padding/truncation/box-drawing logic." It directly backs the repository's mandated terminal-table conventions (literal `│`/`┌`/`┬`/etc. box-drawing characters, a `Duration`-style compact-unit column) and is imported by `Invoke-RunProfile.ps1` (confirmed: that script's line 59 imports `RunFormat` from `lib/`) for its `-List` table and final counters table.

## Usage

Exported functions (`Export-ModuleMember`, line 136): `Format-RunDuration`, `Format-RunDataSize`, `Format-RunTable`, `Format-RunCounters`, `ConvertTo-RunSingleQuoted`.

Key signatures:
- `Format-RunDuration -Milliseconds <double>` — compact units (`12ms`, `1s`, `1m30s`, `2h5m`); returns `'-'` for `$null`/`NaN`.
- `Format-RunDataSize -Bytes <double> [-Signed]` — MiB with two decimals, `'-'` for `$null`/`NaN`, optional leading `+` for non-negative signed deltas.
- `Format-RunTable -Headers <string[]> [-Rows <object[]>] [-RightAligned <int[]>] [-Width <int>]` — renders a box-drawing table; `Width` defaults to the console width (falling back to 110 when redirected or unavailable), and shrinks the widest non-first column down to a floor of 4 characters when the table would overflow.
- `Format-RunCounters -Counters <IDictionary> [-Width <int>]` — renders a `Counter`/`Value` table, formatting any key ending in `.ms` as a compact duration.
- `ConvertTo-RunSingleQuoted -Value <string>` — produces a PowerShell single-quoted literal; throws `RunLiteralControlCharacter` if the value contains any C0 control character or DEL.

Example:
```powershell
Import-Module ./scripts/lib/RunFormat.psm1
Format-RunTable -Headers @('Profile','Script') -Rows @(@('coldstart-100','Measure-ColdStart.ps1'))
Format-RunDuration -Milliseconds 125000   # '2m5s'
```

## Dependencies

None — no dot-sourcing or `Import-Module` of other files; relies only on `[Console]`, `[Math]`, `[Globalization.CultureInfo]`, and `[regex]`.

## Side effects

None — every function is a pure formatter that returns a string or string array; no filesystem, process, or environment mutation. `Format-RunTable`'s only interaction with the environment is a *read* of `[Console]::WindowWidth`/`IsOutputRedirected`/`IsErrorRedirected` (lines 80–82), guarded by its own `try/catch` that falls back to 110 on any failure.

## Findings

- No bug found in the core duration/size formatting math (lines 15–44) — boundary at `999.5` ms (line 19) correctly rounds up to `1s` rather than displaying `1000ms`, and the hour/minute/second composition (lines 21–26) correctly omits a zero component (e.g. `2h` alone when minutes are zero, not `2h0m`).
- DESIGN: `Format-RunTable`'s column-shrinking loop (lines 91–96) only ever shrinks columns with index `$c -ge 1` (`for ($c = 1; $c -lt $count; $c++)`, line 93) — the first column (index 0) is explicitly exempt from shrinking. This is a deliberate choice (presumably to keep the leftmost identifying column, like a profile name, intact) but it is not documented in the function's own `.PARAMETER`/`.SYNOPSIS` comment, so a caller cannot tell from the docstring that column 0 is special-cased and will never be truncated even if it is the widest column and the only one keeping the table within budget — a table with one enormous first-column value and a narrow terminal would still overflow its stated `Width`, silently violating the "no automatic line wrapping / adapt without desync" expectation in AGENTS.md's UTF-8/table rules.
- DESIGN: The shrink loop's floor of `-le 4` (line 94, `if ($widths[$widest] -le 4) { break }`) stops shrinking any column once it reaches 4 characters, but does not then try shrinking a different (narrower but still shrinkable) column — once the single widest remaining column hits the floor, the loop breaks entirely rather than moving to the next-widest. In a pathological case with many fixed-at-floor columns and one still-too-wide table, this means `Format-RunTable` can still render wider than the requested `$Width`, with the function silently accepting that outcome rather than truncating further or falling back to a vertical/compact presentation — which AGENTS.md's table-rendering rules explicitly ask for ("use a vertical presentation when the terminal becomes too narrow"). This module implements the box-drawing/duration-formatting half of that rule well, but not the narrow-terminal vertical-fallback half.
- CONVENTION: Matches the UTF-8 box-drawing character requirement exactly (`┌┬┐├┼┤└┴┘─│`, lines 97–100) — fully compliant with the mandated box characters.
- Testability: Plausibly covered indirectly through the `RunProfiles.*` test suites (given `Invoke-RunProfile.ps1`'s direct dependency on this module), but no test file named specifically for `RunFormat.psm1` was found, and the two shrinking-loop edge cases noted above (first-column exemption, floor-then-break-rather-than-continue) are exactly the kind of boundary behavior that would benefit from a dedicated property/fuzz test asserting the rendered table's line width never exceeds the requested `Width` for arbitrary header/row content — no such property test was found.
- `ConvertTo-RunSingleQuoted`'s control-character rejection (line 132) and typographic-quote doubling (line 133, matching `['‘’‚‛]`) were reviewed and found correct for its stated purpose (keeping generated profile files line-oriented and syntactically valid).

## Verdict

The formatting primitives themselves (duration, size, quoting) are correct and convention-compliant, but `Format-RunTable`'s column-shrinking algorithm has two real edge cases — the undocumented first-column exemption and the break-instead-of-continue floor behavior — that can let a rendered table exceed its requested width, which is the opposite of what the shrinking logic exists to prevent; fixing the break-vs-continue behavior (try the next-widest shrinkable column before giving up) is the highest-priority improvement.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Presentation helpers shared by the run-profile tooling: compact durations, Unicode tables, counter tables and PowerShell literals.

Boundary: **Library**. Preview API: **Unclassified**. Guarded functions: 0.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
