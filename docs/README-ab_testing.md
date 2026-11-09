# Cold-start A/B testing

How to compare two QuietCli Core module builds (for example a plain IL build against a ReadyToRun build) with a
statistically defensible verdict, and why an A/A control is a mandatory precondition rather than an optional
sanity check. The tooling lives in `scripts/Measure-ColdStart.ps1`, `scripts/Invoke-RunProfile.ps1` and
`scripts/Invoke-ColdStartGate.ps1`.

## What is actually measured

Every sample starts a fresh `pwsh -NoProfile` child process through `quiet`. The child imports the module under
test, then times two `quiet` calls of a trivial native command (`cmd /c exit 0` on Windows, `true` on Linux). Three
phases are recorded per child, each isolating a different cost:

- **Import** — time to `Import-Module` the manifest (assemblies, PowerShell class definitions, module processing).
- **First call** — the first `quiet` invocation after import. This is the engine's JIT-cold path: the first time
  this process executes that code, plus the cost of spawning the native child.
- **Second call** — the second `quiet` invocation in the same child process. JIT is already warm, so this is the
  steady-state cost (process spawn and protocol streaming only, no more one-time JIT cost).

The trivial native command (`cmd /c exit 0`) is deliberately cheap: the goal is to isolate the cost of the QuietCli
engine itself (process spawn, pipes, protocol parsing, `-Output`/`-Complete` callback dispatch), not the cost of
whatever the command does.

Baseline and candidate runs alternate within each pair, in a randomized order (fixed seed), so machine drift (CPU
frequency scaling, scheduler noise, background processes) hits both variants symmetrically instead of favoring
whichever variant always runs first or second.

The verdict for each phase comes from a seeded percentile bootstrap of the median of paired differences (candidate
minus baseline): `faster` or `slower` only when the 95% confidence interval excludes zero, otherwise
`inconclusive`.

## What an A/A control measures, and why it is not a wasted run

An A/A control points `BaselineModule` and `CandidateModule` at the **same** module manifest. Both sides are
therefore the same binary, the same code — there is no real difference to detect, by construction.

This means an A/A control is not measuring the engine's performance at all. It measures **the noise floor of the
measurement methodology on this specific machine**: process-spawn jitter, OS disk-cache state, antivirus scanning,
CPU frequency scaling, scheduler contention, or anything else that makes two runs of the identical artifact look
different.

Because the true difference between the two sides is mathematically zero, the **correct** result for a clean A/A
control is `inconclusive` on every phase — the bootstrap confidence interval straddling zero is exactly what should
happen when there is nothing to detect. This is a validation of the statistical protocol, not a "nothing to report"
shrug:

- `inconclusive` on every phase → the protocol does not manufacture a phantom difference where none exists → the
  noise floor is low enough, for this profile's pair count and seed, to trust a later A/B verdict measured the same
  way on this machine.
- `faster` or `slower` on any phase → a **false positive**: the machine is too noisy for this profile's settings
  (not enough pairs, too much background interference, thermal/frequency variance). Any A/B result measured under
  those same noisy conditions cannot be trusted either, and must not be reported as a real effect.

### Example: a clean A/A control

```
┌─────────────┬────────────┬─────┬───────────────────┬───────────────┬───────────────┬────────────────┐
│ Phase       │ Variant    │   N │ Duration (median) │ Duration (Q1) │ Duration (Q3) │ Duration (min) │
├─────────────┼────────────┼─────┼───────────────────┼───────────────┼───────────────┼────────────────┤
│ Import      │ baseline   │ 100 │             161ms │         153ms │         170ms │          143ms │
│ Import      │ aa-control │ 100 │             159ms │         153ms │         169ms │          143ms │
│ First call  │ baseline   │ 100 │             270ms │         262ms │         295ms │          248ms │
│ First call  │ aa-control │ 100 │             274ms │         262ms │         293ms │          247ms │
│ Second call │ baseline   │ 100 │              65ms │          62ms │          71ms │           59ms │
│ Second call │ aa-control │ 100 │              65ms │          62ms │          69ms │           59ms │
└─────────────┴────────────┴─────┴───────────────────┴───────────────┴───────────────┴────────────────┘

Paired difference (candidate minus baseline), 95% bootstrap interval of the median, 2000 resamples
┌─────────────┬───────┬───────────────────┬───────────────────┬────────────────────┬──────────────┐
│ Phase       │ Pairs │ Duration (median) │ Duration (CI low) │ Duration (CI high) │ Verdict      │
├─────────────┼───────┼───────────────────┼───────────────────┼────────────────────┼──────────────┤
│ Import      │   100 │              -1ms │              -5ms │                3ms │ inconclusive │
│ First call  │   100 │              -3ms │              -6ms │                5ms │ inconclusive │
│ Second call │   100 │              -1ms │              -2ms │                1ms │ inconclusive │
└─────────────┴───────┴───────────────────┴───────────────────┴────────────────────┴──────────────┘
```

All three phases inconclusive, CIs tight around zero: this machine's noise floor is clean for this profile. A
subsequent A/B run (different modules on each side) that reports `faster`/`slower` on top of this baseline can be
trusted as a real effect, not an artifact of machine noise.

### Example: an A/B result validated by the A/A control above

```
┌─────────────┬───────┬───────────────────┬───────────────────┬────────────────────┬──────────────┐
│ Phase       │ Pairs │ Duration (median) │ Duration (CI low) │ Duration (CI high) │ Verdict      │
├─────────────┼───────┼───────────────────┼───────────────────┼────────────────────┼──────────────┤
│ Import      │   100 │              -1ms │              -2ms │                1ms │ inconclusive │
│ First call  │   100 │             -30ms │             -36ms │              -28ms │ faster       │
│ Second call │   100 │               0ms │              -1ms │                2ms │ inconclusive │
└─────────────┴───────┴───────────────────┴───────────────────┴────────────────────┴──────────────┘
```

Consistent with what ReadyToRun should do: it removes first-call JIT cost (`First call` faster by ~30ms, CI
excludes zero), and is a wash everywhere else (`Import`, already-warm `Second call`).

## Running the gate: `scripts/Invoke-ColdStartGate.ps1`

Calling `Measure-ColdStart.ps1` or `Invoke-RunProfile.ps1` directly makes the A/A control a step a caller can
forget. `scripts/Invoke-ColdStartGate.ps1` makes it mandatory:

1. Keeps one cached A/A control per machine and run profile, under `artifacts/coldstart/aa-<profile>-<machine>.json`
   (git-ignored — covered by this project's existing `/artifacts/` rule in `.gitignore`; never commit this
   directory).
2. Reuses that cache only while it is fresh (`-MaxAgeDays`, default 14) **and** still all-inconclusive on every
   phase.
3. Otherwise remeasures the A/A control first, into the same cache file.
4. If the A/A control — cached or freshly measured — is **not** all-inconclusive, it throws
   `ColdStartNoiseFloorUnstable` and refuses to run the A/B. A noisy machine cannot produce a trustworthy
   `faster`/`slower` verdict either.
5. Only once the noise floor is confirmed clean does it run the real A/B through `Invoke-RunProfile.ps1`, writing
   the result to a timestamped `artifacts/coldstart/ab-<profile>-<label>-<UTC-stamp>.json`.

Run from `PoSh/FrenchExDev/QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh`:

```powershell
# First run on this machine, or after a stale/invalidated cache: measures the A/A control, then the A/B.
./scripts/Invoke-ColdStartGate.ps1 `
    -CandidateModule 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh\FrenchExDev2.QuietCli.Core.PoSh.psd1' `
    -CandidateLabel readytorun

# Force a fresh A/A control even if a clean cache entry already exists for this machine.
./scripts/Invoke-ColdStartGate.ps1 `
    -CandidateModule 'C:\tmp\r2r\FrenchExDev2.QuietCli.Core.PoSh\FrenchExDev2.QuietCli.Core.PoSh.psd1' `
    -CandidateLabel readytorun -Force
```

`-Arguments` forwards overrides (for example `@{ Runs = 1000 }`) to both the A/A and the A/B run; never set
`CandidateModule`, `CandidateLabel` or `OutputPath` there — the gate controls those.

A visible `pwsh` monitoring window is still required for the run, per the workspace test rules (see the root
`AGENTS.md`, "Test runs").

## Setting up a ReadyToRun candidate build

Building the candidate itself is outside the gate's scope — it only orchestrates the measurement.
`scripts/New-ReadyToRunCandidate.ps1` builds it as a separate copy, never overwriting the baseline you want to
compare against — see `docs/README-readytorun_profiling.md` for what it does and why. With the baseline already built
normally (`./scripts/Build-Workspace.ps1`, left in place):

```powershell
$candidate = ./scripts/New-ReadyToRunCandidate.ps1
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule $candidate -CandidateLabel 'readytorun'
```

Pass `-RuntimeIdentifier linux-x64` (or the matching Linux RID) to the candidate script on a Linux machine.

`-ReadyToRun` on `scripts/Build-Workspace.ps1` also adds `-p:PublishReadyToRun=true` to every `lib/engine/<rid>`
publication (net11.0), for a later CLR-11-host comparison; this is unverified against the pinned .NET 11 RC SDK's
Crossgen2 package availability per RID — see `scripts/Test-SdkReadiness.ps1` and `AGENTS-SDK-READINESS.md`.

## On-disk footprint and package size

Every run also reports each variant's on-disk footprint — the total size, in bytes, of every file under its
module directory (`Footprint.BaselineBytes`/`CandidateBytes`/`DifferenceBytes` in the output JSON, shown as a
`Module footprint` table in the console output, alongside `Hosted path` and `Package (.nupkg)` columns). This is a
static build-artifact measurement, not a timed sample: it does not get a bootstrap verdict, because there is
nothing probabilistic about it. It matters most for a ReadyToRun candidate, which embeds precompiled native code
and is therefore expected to be **larger** on disk even when it is faster to start — see
`docs/README-readytorun_profiling.md` for a worked example of that tradeoff.

`On disk` sums every file under the module root, including every bundled RID whether or not this process uses it,
so it overstates what a given deployment actually loads. `Hosted path` (`Footprint.BaselineHostedBytes`/
`CandidateHostedBytes`/`HostedDifferenceBytes`) narrows that to only the `lib/inprocess` (CLR10, Auto hosting) or
`lib/engine/<RuntimeIdentifier>` (CLR11+) directory this process actually hosts from — the number to compare when
judging a candidate's real deployed cost rather than its total package bulk.

Pass `-MeasurePackageSize` to also package each variant with `Compress-PSResource` and report the resulting
`.nupkg` size (`Footprint.BaselinePackageBytes`/`CandidatePackageBytes`/`PackageDifferenceBytes`) — the number a
PSGallery install would actually download. It is off by default (slower, and requires a real publishable
manifest — a minimal test fixture manifest is not one), and the `Package (.nupkg)` column shows `-` when it was
not requested.

## See also

- `docs/README-run-profiles.md` — run profile mechanics, statistics background ("Statistics: how noise is eliminated"),
  and CI scope for this tooling.
- `scripts/Measure-ColdStart.ps1` — the underlying measurement script (full parameter reference in its own
  comment-based help).
- `scripts/Invoke-ColdStartGate.ps1` — the A/A-gated A/B workflow described above (full parameter reference in its
  own comment-based help).
- `scripts/New-ReadyToRunCandidate.ps1` — builds the ReadyToRun candidate used above (full parameter reference in
  its own comment-based help).
- `.github/workflows/quietcli2-readytorun.yml` — manual, informational workflow that runs this gate in CI.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
