# Audit 2026-11-07: run profiles (tests and mutation)

Scope: `scripts/New-RunProfile.ps1`, `scripts/Invoke-RunProfile.ps1`, `scripts/Measure-ColdStart.ps1`,
`scripts/lib/Run*.psm1`, profiles `coldstart-100` and `coldstart-1000`.
How the tooling works: [../README-run-profiles.md](../README-run-profiles.md).

## Launch commands

Run from the repository root (`FrenchExDev2.QuietCli.PoSh`), PowerShell 7.6+, each in a visible `pwsh` window.

| Evidence | Command |
|---|---|
| Test suite | `pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1` |
| Mutation campaign | `pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1 -Mutation` |
| One mutant | `pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.ps1 -MutantName <name>` |
| Console encoding other than UTF-8 | add `-ConsoleEncoding oem` to the suite or the campaign (default `utf-8`) |
| Profile smoke | `./scripts/Invoke-RunProfile.ps1 -List` |

Parameters used: seed `61207`; suite iterations 300 per property case; mutation campaign iterations 120 per
property case, profiler and console cases skipped in the child suites (`-Skip 'profiler:,console:'`), 300 s deadline
per mutant. The `-MutantName` option takes one name when started through `pwsh -File` (an array is passed as a single
string).

## Results

### Test suite

30 cases passed, 0 failed, 0 skipped, in 45 s. The suite covers property, fuzz, example/schema, integration,
logger, profiler and encoding/console cases. Each property case runs 300 generated inputs (names, profiles, merge
pairs, samples, tables). Before any case runs, a start-up self-check compares the console and pipe code pages with an
independent oracle (65001, or the culture's OEM page for `-ConsoleEncoding oem`) and fails in pure ASCII
(`SUMMARY Passed=0 Failed=1 Skipped=0`), because a strict-UTF-8 consumer cannot read anything else once the console
is wrong.

### Mutation campaign

| Mutants | Killed | Survived | Crashed | Timeout | Invalid | Score | Duration |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 63 | 63 | 0 | 0 | 0 | 0 | 100% | 17m26s + 1m8s |

Evidence is in two parts, because the full catalogue was not re-run after the last correction. The full 63-mutant
run (seed 61207, 120 iterations) gave 60 Killed, 1 Survived and 2 Crashed; the three were then fixed and re-run alone
(all Killed, 1m8s). The other 60 stay valid because the correction only added a start-up check and replaced one
mutant, and the unmutated suite passes 30/0.

- `console-name-case-sensitive` survived because it was an **equivalent mutant**: a PowerShell `switch` is
  case-insensitive by default, so `switch ($Name)` behaves like `switch ($Name.ToLowerInvariant())`. It was replaced by
  `switch -CaseSensitive ($Name)`, which changes behavior and is Killed by the case that resolves `UTF-8`.
- `console-utf8-is-oem` and `console-output-not-applied` crashed with `DecodeOrFramingFailed`: the mutated module left
  the console in OEM and `quiet` could not decode the child's box-drawing output, so the harness failed before any
  assertion ran. That is detection by the transport, not by an assertion. The start-up self-check now turns it into an
  assertion failure; both mutants are Killed by it.
- The 17 encoding mutants (BOM, CRLF, lenient decoding, OEM default, unknown name accepted, console or pipe
  encoding not applied, append without LF, and similar) are all Killed in the final state.

The first full run killed 45 and reported 1 Invalid mutant (`typographic-quotes-undoubled`). The cause was a
mistake in the mutant, not in the code: PowerShell treats the typographic quotes U+2018 to U+201B as single quotes
inside a single-quoted literal, so the target text never matched. The mutant now builds its target from code points
and is Killed by 2 cases (separate re-run, 31 s). The two runs are listed together because the full campaign was not
re-run after the correction.

The score is `killed / (killed + survived)`; crashed, timeout and invalid mutants are reported separately and are all
zero in the final state. The catalogue is in `RunProfiles.Mutation.ps1`.

### Defects found by the tests while building the tooling

| Defect | Fix |
|---|---|
| Name regex used `$`, accepting `"a\n"` | `\z` |
| `WriteAllTextAsync(...).GetAwaiter().GetResult()` leaked a `VoidTaskResult` | `[void]` |
| `Get-Command -LiteralPath` returned no parameters | `Get-Command -Name <path> -CommandType ExternalScript` |
| Hashtable key `Count` hijacked `.Count` | `get_Count()` |
| A single table row was unrolled by `, @()` | `List[object]` with `.Add(@(...))` |
| Empty array refused by a mandatory `[double[]]` | `[AllowEmptyCollection()]` |
| An A/A run with 3 pairs gave a false `slower` | verdict `too-few-pairs` below 20 pairs |
| The child's UTF-8 table output was decoded strictly by `quiet` and failed under `-NoProfile` (`DecodeOrFramingFailed`) | One encoding policy module (`RunEncoding.psm1`) and a `-ConsoleEncoding utf-8\|oem` parameter for the console boundary; files stay fixed at UTF-8 without BOM and LF |
| The exception from a strict UTF-8 read was wrapped in a `MethodInvocationException`, so the strict-read case failed | `GetBaseException()` in the case |

### Not measured in this audit

- A/A false-positive rate of the verdict at 100 and 1000 pairs.
- A/B cold-start comparison of the ReadyToRun engine with these profiles.
- The monitoring window's saved log shows mojibake for the table border characters (`Tee-Object` decodes the
  child's UTF-8 with the OEM code page, the same encoding mismatch as in Gap 1). Names, outcomes and counts are
  ASCII and readable; the tables themselves are correct in the child's own output.

## Gaps

1. ~~Encoding is untested by mutation.~~ Closed: one policy module, `-ConsoleEncoding`, 17 encoding mutants. The shared
   monitored launcher now decodes UTF-8 explicitly without `Tee-Object`. Non-UTF-8 output remains an explicit negative
   protocol case, not a supported alternate product encoding.
2. ~~The benchmark and initializer have no unit or mutation tests.~~ Closed by independent sample properties, malformed
   inputs, real-script native-boundary fixtures, cache/download fixtures, targeted mutants and live smoke cases.
3. ~~RunProfiler has no mutant.~~ Closed by resolver, row-projection and missing-trace mutants. Independent unit cases
   run in mutation sandboxes; the actual profiler remains a separate functional case.
4. ~~No GitHub workflow runs the suite or campaign.~~ Wiring added to the shared Windows x64 stable Core/All job,
   including failure gates and artifact upload. A remote successful run is not claimed.
5. Mutants are hand-written substitutions; there is no automatic mutant generation, so the score only measures the
   catalogue and not every possible fault.

See the [8 November qualification audit](2026-11-08-run-profile-qualification.md) for the final 46-case functional
suite, full campaign and targeted reprise, source identities, Core/Git regression results and remaining measurement limits.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
