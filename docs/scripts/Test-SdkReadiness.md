# Test-SdkReadiness.ps1

## Purpose

Answers, without installing, building, or publishing anything, whether this machine's .NET SDK
matches the pinned `global.json` version and whether ReadyToRun (Crossgen2) publication is actually
feasible for every RID that `Build-Workspace.ps1 -ReadyToRun` would target. This solves a recurring
pain point in AOT/ReadyToRun workflows: `dotnet publish -p:PublishReadyToRun=true` can fail late and
confusingly if the matching `Microsoft.NETCore.App.Crossgen2.<Rid>` package isn't published for the
locally installed runtime version, or if the installed SDK has silently drifted from the pin. Running
this first turns that failure into an actionable, itemized report. It is referenced directly from
`AGENTS-SDK-READINESS.md` and cross-referenced by name inside its own `-Update` gap-remediation output
(line 236: "revalider avec ./scripts/Test-SdkReadiness.ps1 après mise à jour"), i.e. it is meant to be
re-run after any attempt to close a reported gap. It is a diagnostic entry point, not something other
scripts call programmatically — no other `scripts/*.ps1` file in this folder invokes it.

## Usage

```
[CmdletBinding()]param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$RuntimeIdentifier=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'),
    [string]$LocalRuntimeIdentifier=('win-'+([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant())),
    [switch]$Offline,
    [switch]$Update
)
```

- `WorkspaceRoot` (string, optional) — QuietCli2 workspace containing `global.json` and
  `runtime-targets.json`. Defaults to the script's parent directory.
- `RuntimeIdentifier` (string array, optional, validated against 6 known RIDs) — RIDs to check for the
  net11.0 `lib/engine/<rid>` publications. Defaults to all 6.
- `LocalRuntimeIdentifier` (string, optional) — RID checked for the net10.0 `lib/inprocess`
  publication. Defaults to the local Windows architecture (e.g. `win-x64`); must be overridden on
  Linux (e.g. `linux-x64`) since the default computation always prefixes `win-`.
- `Offline` (switch, optional) — skips every network call and reports those fields as `Unknown`
  instead of failing.
- `Update` (switch, optional) — performs no install/publish; additionally prints the exact remediation
  command for each detected gap.

Example:

```powershell
./scripts/Test-SdkReadiness.ps1 -Update
./scripts/Test-SdkReadiness.ps1 -Offline -RuntimeIdentifier linux-x64
```

## Dependencies

- Dot-sources `Common.ps1` (line 43), which transitively loads `ReportPaths.ps1`, `Ci.Process.ps1`,
  `SourceIdentity.ps1`, `RuntimeTargets.ps1` — though this script itself only actually uses
  `Invoke-CiProcess` (via its own `Invoke-QuietDotnetQuery` wrapper, line 69).
- Shells out to `dotnet --list-sdks`, `dotnet --list-runtimes`, `dotnet --version` via
  `Invoke-CiProcess` (never through `quiet`, consistent with the Ci.Process.ps1 contract of running CI
  tools "independently of the product engine").
- Network calls (skipped entirely under `-Offline`): `Invoke-RestMethod` against
  `dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json` (line 117) and
  `api.nuget.org/v3-flatcontainer/microsoft.netcore.app.crossgen2.<rid>/index.json` (line 133), each
  with a 15-second timeout.
- Filesystem assumption: `global.json` must exist at `WorkspaceRoot` (explicit throw at line 54 if
  missing).

## Side effects

- None that persist: this script only reads `global.json`, queries `dotnet` read-only subcommands, and
  (unless `-Offline`) makes two kinds of read-only HTTPS GET requests. It writes nothing to disk and
  never calls `dotnet install`, `dotnet publish`, or any mutating command — this is explicitly called
  out twice in the doc comment ("This never installs an SDK or calls dotnet publish").
- Writes to the console: in interactive sessions (or always under `-Update`), renders a UTF-8
  box-drawing summary table (`Write-QuietReadinessTable`, lines 191-219) and, under `-Update`, a list
  of suggested remediation commands (`Write-QuietReadinessProposals`, lines 220-241) — but these are
  pure `Write-Host` calls with no retry or installation performed.
- Returns a `[pscustomobject]` (SchemaVersion 1) to the pipeline unconditionally (line 246), intended
  for callers to branch on without re-parsing text (per the `.OUTPUTS` doc comment).

## Findings

- No bugs found in the core comparison logic: pinned-vs-installed (line 159), pinned-vs-effective
  (line 160), pinned-vs-channel (line 161), and per-RID Crossgen2 availability (lines 163-171) are all
  simple, correctly-scoped string/version comparisons with explicit `Unknown`/`RuntimeNotInstalled`/
  `Published`/`NotPublished` status states.
- CONVENTION: this script's console table (`Write-QuietReadinessTable`) is entirely in French
  ("SDK pinné", "Dernier canal", "Écarts", "Actions proposées") while the AGENTS.md convention is
  "Always write code and comments in english. You can talk in UI in user language." This is a UI
  string, which the rule arguably permits as "talk in UI in user language" if the user's language is
  French — but it is inconsistent with sibling scripts in this very folder (`Watch-Tests.ps1`'s
  monitor table, for example, is also French in headings but English in field names), so there's no
  clear project-wide decision being followed consistently either way; flagging as a convention
  judgment call rather than a hard violation.
- DESIGN: `Write-QuietReadinessTable`'s box-drawing table (lines 199-212) is a fixed-width table
  (hardcoded `78`, `18`, `24`, `16` column widths) that does not adapt to the actual terminal width,
  unlike the dynamic-resize requirement AGENTS.md places on "any terminal UI or monitoring window".
  This script's table is a one-shot diagnostic printout rather than a persistent monitor, so the
  strict "redraw on resize" rule for monitors may not literally apply, but the AGENTS.md "tableaux
  dynamiques" section also says "Pour une sortie ponctuelle, calculer la disposition à partir de la
  largeur courante au moment de l'affichage" (for one-shot output, compute the layout from the current
  width at display time) — this script does not do that; it always prints a 78-character-wide block
  regardless of actual console width, which can wrap awkwardly in a narrow terminal.
- No `Duration` column applies here — this is not a timed run, so that specific AGENTS.md rule does not
  apply to this script.
- Testability gap: no Pester test under either `*.Tests.PoSh` project references
  `Test-SdkReadiness.ps1`, `Get-QuietPinnedSdk`, `Get-QuietCrossgen2Versions`, or
  `Test-QuietCrossgen2Match` (searched, no hits). The pure-logic pieces (version comparison, gap
  detection, `Test-QuietCrossgen2Match`'s case-sensitive containment check) are straightforward enough
  to unit-test without any real `dotnet`/network call (by injecting fake `Versions`/`RuntimeVersion`
  values), yet no such test exists — a missed opportunity given AGENTS.md's mandatory property-testing
  strategy, since this is exactly the kind of small, pure, easily-fuzzable function
  (`Test-QuietCrossgen2Match`, line 137-149) the strategy is meant to cover.
- No security concern: only read-only network calls to well-known, hardcoded first-party endpoints
  (official .NET release index, NuGet flat container API); no secrets, no write access.

## Verdict

Fit for purpose as a pre-flight diagnostic and genuinely useful for its "don't find out about a
Crossgen2 gap mid-publish" goal; the most valuable improvement would be adding unit tests for the pure
comparison functions (`Test-QuietCrossgen2Match`, the gap-detection branches) since they need no
`dotnet` or network access to test and currently have zero coverage.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
