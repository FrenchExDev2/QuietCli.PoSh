# Invoke-ColdStartGate.psm1

Implements [Invoke-ColdStartGate.ps1](../Invoke-ColdStartGate.md). Exports only "Invoke-QuietScriptInvokeColdStartGate". Imported without name checking; import defines the command without running the operation.

# Invoke-ColdStartGate.ps1

## Purpose

Enforces a trustworthy A/B cold-start comparison by first requiring a fresh A/A (same-binary-vs-itself)
"noise floor" control to be conclusive (all phases `inconclusive`, meaning no phantom difference was
detected) before running the real A/B comparison between a baseline and a candidate module build. This
solves the problem that `Measure-ColdStart.ps1`'s verdicts ("faster"/"slower") are meaningless if the
measuring machine itself has enough timing noise to manufacture a false difference between two identical
builds. It caches the per-machine, per-profile A/A result (git-ignored artifacts directory) and reuses it
while fresh. It is invoked directly on Windows by `Invoke-ColdStartMatrix.ps1` (line 129, the `'windows'`
target) and, inside Linux containers, as the actual containerized entrypoint dispatched by
`Invoke-ContainerColdStartWorker.ps1` (lines 80–87, via `podman create --entrypoint pwsh ... Invoke-ColdStartGate.ps1`).

## Usage

Parameters:
- `-CandidateModule` (string, **mandatory**) — module manifest of the compared build.
- `-CandidateLabel` (string, optional, `[ValidateNotNullOrEmpty()]`, default `'candidate'`) — display name of the compared build.
- `-BaselineModule` (string, optional, default `<repo>/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1`) — reference build, used as both sides of the A/A control and as the A/B baseline.
- `-ProfileName` (string, optional, `[ValidateNotNullOrEmpty()]`, default `'coldstart-100'`) — run profile for both A/A and A/B.
- `-ArtifactsDirectory` (string, optional, default `<repo>/artifacts/coldstart`) — per-machine A/A cache and every A/B result; must stay git-ignored.
- `-MaxAgeDays` (int, optional, `[ValidateRange(1,365)]`, default `14`) — cached A/A staleness threshold.
- `-Force` (switch, optional) — remeasures the A/A control even if fresh and clean.
- `-Arguments` (hashtable, optional, default `@{}`) — extra overrides forwarded to both runs; must not set `CandidateModule`/`CandidateLabel`/`OutputPath`.
- `-MeasurePackageSize` (switch, optional) — convenience flag forwarding `MeasurePackageSize=$true` via `-Arguments`, for contexts where a hashtable literal can't be passed (e.g. `pwsh -File` from a container).
- `-LogLevel` (string, optional, `[ValidateSet('Trace','Debug','Info','Warn','Error','Off')]`, default `'Info'`).
- `-LogPath` (string, optional) — optional log file.

Example (from the file's own help, line 50):
```powershell
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh\FrenchExDev2.QuietCli.Core.PoSh.psd1' -CandidateLabel readytorun
```

## Dependencies

- `using module ./lib/RunLog.psm1` (line 52) for `New-RunLogger`.
- Imports `lib/RunEncoding.psm1` and `lib/RunFormat.psm1` with `-Force` (line 68) for `Read-RunTextFile`, `Format-RunCounters`.
- Invokes `Invoke-RunProfile.ps1` (resolved at line 70, called at lines 158 and 178) twice per execution — once for the A/A control (unless cache is fresh), once for the real A/B comparison. All actual cold-start measurement logic is delegated there (and ultimately to `Measure-ColdStart.ps1`, per the `.DESCRIPTION`).
- Reads/writes JSON artifacts under `-ArtifactsDirectory`.
- No native tool (git/docker/dotnet) invoked directly in this file; relies entirely on `Invoke-RunProfile.ps1`.

## Side effects

- Creates `-ArtifactsDirectory` if missing (line 147).
- Writes/overwrites the A/A cache file `aa-<profile>-<machine>.json` under that directory (via the forwarded `Invoke-RunProfile.ps1` call, `-OutputPath` at line 157).
- Writes a timestamped A/B result file `ab-<profile>-<label>-<stamp>.json` (line 172, written by the forwarded call at line 177-178).
- Logs via `$logger` to console and optionally `-LogPath`.
- Throws `'ColdStartNoiseFloorUnstable: ...'` (line 143) if the A/A control is not all-`inconclusive`, aborting before any A/B run — this is the gate's entire reason for existing.

## Findings

- No bugs found after genuine scrutiny of the control flow: cache freshness check (`Test-ColdStartAaCacheFresh`, lines 96–111) correctly checks both age and verdict-cleanliness; `Assert-ColdStartNoiseFloor` (lines 131–145) is called unconditionally after either branch (cached-reuse or freshly-measured), so a stale cache cannot silently proceed — this is good defensive design.
- DESIGN: `Get-ColdStartAaDisplayVerdict` (lines 113–129) remaps the raw `'inconclusive'` verdict to the display string `'conclusive'` specifically for A/A controls, with a long comment explaining why this isn't a semantic contradiction. This dual-meaning overload of the same literal string (`'inconclusive'`) for two different real-world states (ambiguous in A/B, healthy in A/A) is a readability risk for anyone reading raw JSON artifacts without this script's comment in front of them — a distinct enum value (e.g. `NoiseFloorClean` vs. `Inconclusive`) at the data layer would remove the need for this display-time remapping entirely. This is a DRY/clarity smell rather than a bug.
- Missing input validation: `-Arguments` is a plain `[hashtable]` with no guard against the caller accidentally including `CandidateModule`/`CandidateLabel`/`OutputPath` keys despite the doc comment (lines 34–36) explicitly warning against it — the script silently overwrites those keys later (lines 155–157, 174–177) via `$aaArguments['CandidateModule']=...` etc., so in practice an accidental collision is silently corrected, not rejected. This is actually safe behavior, just undocumented as such in-code (only in the comment-based help).
- `Get-ColdStartMachineKey` (lines 72–82) builds a cache key from `[Environment]::MachineName` only, not also the OS/platform/architecture; if the same machine name is reused across different containers (e.g. multiple Linux containers on the same Windows host, each with a different guest architecture) sharing one bind-mounted artifacts directory, their A/A caches could collide. In the normal container flow this risk is mitigated because `Invoke-ContainerColdStartWorker.ps1` uses a networkless, isolated container per run with its own filesystem, so cache collision across distinct guest architectures sharing one host name is unlikely in current usage but is a latent sharp edge if the artifacts directory is ever shared across containers.
- No companion Pester test found for `Invoke-ColdStartGate.ps1`.

## Verdict

Fit for purpose and carefully reasoned about the A/A-before-A/B trustworthiness problem; no bugs found. The one worth tracking is the `'inconclusive'`-as-healthy-for-A/A naming overload (DESIGN), which is well-explained in comments but would benefit from a distinct verdict value in the underlying data model.

Shared helper imports reuse loaded modules and preserve caller command visibility across repeated invocations.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Enforces a fresh A/A noise-floor control before running a cold-start A/B comparison, and persists both.

Boundary: **Library**. Preview API: **Library**. Guarded functions: 1.

See [the complete review](../preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
