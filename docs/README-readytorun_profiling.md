# ReadyToRun cold-start profiling

How to measure whether a ReadyToRun (R2R) build of `FrenchExDev2.QuietCli.Core.PoSh` actually reduces cold-start
cost, and how to read the resulting `artifacts/coldstart/*.json` file. For the statistical protocol itself (why an
A/A control is mandatory, what each verdict means), see `docs/README-ab_testing.md` — this page is the ReadyToRun-specific
walkthrough on top of it.

## Why ReadyToRun is being profiled here

A plain IL build pays a JIT-compilation cost the first time each method runs in a process. `PublishReadyToRun=true`
precompiles the engine's native code ahead of time, so that cost should shrink or disappear — but only for the
**first** call in a process; once the JIT has warmed up, R2R and IL converge. The gate measures exactly that shape
of effect, instead of assuming it.

## Building the R2R candidate

`-CandidateModule` must point at an already-built module manifest; the gate only orchestrates measurement, it does
not build anything. `scripts/New-ReadyToRunCandidate.ps1` builds that candidate as a **separate copy**, never
overwriting the baseline module you want to compare against — the gate needs both to exist side by side. It copies
`global.json` and the Core module into a throwaway directory, then republishes only that copy's engine project
with `-p:PublishReadyToRun=true` (the only difference from a normal publish, which is why the A/B comparison
isolates exactly the effect ReadyToRun has), recording the build's input hashes and configuration next to the
output the same way `./scripts/Build-Workspace.ps1` does. From
`PoSh/FrenchExDev/QuietCliEcosystem/FrenchExDev2.QuietCli.PoSh`, with the baseline already built normally
(`./scripts/Build-Workspace.ps1`, left in place and untouched):

```powershell
$candidate = ./scripts/New-ReadyToRunCandidate.ps1
```

Pass `-RuntimeIdentifier linux-x64` (or the matching Linux RID) on a Linux machine; it otherwise defaults to this
machine's own architecture. `$candidate` now holds the manifest path to pass as `-CandidateModule` below.

## Launching the gate

From the same directory, run the gate against the manifest just built. `-Arguments @{ MeasurePackageSize = $true }`
also packages each variant with `Compress-PSResource` and reports its real `.nupkg` size, not just its on-disk
footprint — see "Reading the output JSON" below for why the two can diverge; it is worth the extra time on the
first run against a new candidate, so it is included here rather than as an afterthought:

```powershell
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule $candidate -CandidateLabel readytorun -Arguments @{ MeasurePackageSize = $true }
```

This:

1. Measures (or reuses a fresh cached) **A/A control** — baseline against itself — to confirm this machine's
   measurement noise floor is clean. If it is not, the run aborts with `ColdStartNoiseFloorUnstable` and no A/B
   result is produced.
2. Runs the real **A/B comparison** (baseline vs. the R2R candidate) and writes it to
   `artifacts/coldstart/ab-<profile>-<label>-<UTC-stamp>.json` — this is the file analyzed below.

A visible `pwsh` monitoring window is still required for the run (workspace "Test runs" rule in the root
`AGENTS.md`).

## Reading the output JSON

Each `ab-*.json` file has four top-level sections:

- **`Parameters`** — the exact inputs: which module manifest was baseline vs. candidate, how many pairs
  (`Runs`), how many warmup pairs were discarded, the child command actually timed (`cmd /c exit 0` on Windows),
  the bootstrap seed and resample count, and confidence level.
- **`Environment`** — machine name, PowerShell version, OS, CLR version, runtime identifier. Needed because the
  noise floor (and therefore which verdicts are trustworthy) is per-machine; a result from one machine does not
  validate another, and the runtime identifier is what a Linux-matrix run checks against the expected platform.
- **`Counters`** — operational bookkeeping (log volume, how many runs started/succeeded, how many verdicts came
  out `faster`/`slower`/`inconclusive`). Useful as a sanity check that nothing silently failed, not for the
  performance conclusion itself.
- **`Summary`** — the actual result, one entry per phase:
  - **`Import`** — time to `Import-Module` the manifest.
  - **`First call`** — the first native call after import: JIT-cold path plus process spawn. This is where R2R
    is expected to help.
  - **`Second call`** — the second native call in the same process: JIT already warm, steady-state cost only.

  Each phase reports `Baseline`/`Candidate` order statistics (N, Min, Q1, Median, Q3, Max in milliseconds), a
  `Difference` block (candidate minus baseline: paired median, and the 95%-confidence bootstrap `Low`/`High`
  bounds), and a `Verdict`:
  - `faster` — the confidence interval is entirely negative: candidate is reliably quicker.
  - `slower` — the confidence interval is entirely positive: candidate is reliably slower.
  - `inconclusive` — the interval straddles zero: no reliable difference detected at this sample size.
- **`Footprint`** — `BaselineBytes`, `CandidateBytes` and `DifferenceBytes`: the total on-disk size of every file
  under each variant's module directory. This is a static build-artifact measurement, not a timed sample, and it
  is the other half of the ReadyToRun tradeoff: R2R embeds precompiled native code in the assembly, so the
  candidate is expected to be **larger** on disk even when it is faster to start. A timing win that ignores a
  large footprint increase is an incomplete comparison — check both. `BaselineHostedBytes`/`CandidateHostedBytes`/
  `HostedDifferenceBytes` narrow that to only the engine files on the hosting path this process actually loads —
  `lib/inprocess` on CLR10, or `lib/engine/<RuntimeIdentifier>` on CLR11+ (Auto hosting) — so the bundled-but-unused
  RIDs that inflate `*Bytes` do not also inflate the number you'd use to judge the candidate's real deployed cost.
  With `-MeasurePackageSize` (see above), `BaselinePackageBytes`/`CandidatePackageBytes`/`PackageDifferenceBytes`
  add the actual `.nupkg` size `Compress-PSResource` would publish — the number a PSGallery install actually
  downloads. This can diverge from the raw on-disk difference: already-compact IL and embedded native R2R code do
  not compress the same way, so the on-disk gap is not a reliable stand-in for the published package's gap. Both
  fields are `null` unless `-MeasurePackageSize` was passed, since packaging is slower and requires a real,
  publishable manifest.
- **`Pairs`** — the raw per-pair timings (one `Baseline`/`Candidate` triplet per measured pair), in case a
  specific outlier needs investigating. `Profiles` is reserved for future per-call profiler output and is empty
  for a plain cold-start run.

## Worked example

`artifacts/coldstart/ab-coldstart-100-readytorun-20261108T095226Z.json` (100 pairs, baseline vs. an R2R build):

| Phase | Baseline median | Candidate median | Difference (95% CI) | Verdict |
|---|---|---|---|---|
| Import | 161.67 ms | 161.72 ms | -0.81 ms [-2.55, +1.64] | `inconclusive` |
| First call | 278.35 ms | 246.33 ms | **-30.5 ms [-33.7, -25.3]** | `faster` |
| Second call | 66.32 ms | 67.92 ms | +0.07 ms [-1.36, +2.57] | `inconclusive` |

Reading it: the ~30 ms gain lands exactly on `First call`, the JIT-cold phase R2R is meant to fix, and the interval
never crosses zero — a reliable effect, not noise. `Import` and the already-warm `Second call` show no reliable
difference, which is also expected: R2R changes JIT behavior, not module loading or steady-state execution. This is
the shape of result that validates the ReadyToRun port: a real, localized gain where the mechanism predicts one,
and no regression elsewhere.

That particular file predates the `Footprint` field below; a fresh run reports it alongside the timing verdicts,
and it is the number to check before calling the port a pure win — see the note on `Footprint` above.

## Running the whole matrix locally

`./scripts/Invoke-ColdStartMatrix.ps1` is the single entry point for everything above, for every platform at
once, from a developer's own machine: it builds the baseline, builds each requested target's ReadyToRun
candidate, and runs the gate on each — directly for `windows`, or inside that Linux distribution's prepared
container for `debian-x64`/`alpine-x64`/`debian-arm64`/`alpine-arm64`. Linux targets run with configurable
concurrency (`-MaxConcurrency`, default 2); each target's result is informational, so one failing or
noise-floor-unstable target never stops the others. It never builds a container image itself — it pulls one
already published by `.github/workflows/ci.yml`'s `linux-images` job via `scripts/Get-CiImageForDevelopment.ps1`,
which is the one supported way to use these images from a non-Linux host:

```powershell
./scripts/Invoke-ColdStartMatrix.ps1
```

Then render every run found so far (local and containerized alike) in one table with
`./scripts/Show-ColdStartMatrixReport.ps1` — repeatable any time, like `Show-ColdStartReport.ps1`, without
rerunning anything.

## See also

- `docs/README-ab_testing.md` — full statistical protocol, why the A/A control is mandatory, and the example tables this
  page's worked example follows.
- `docs/README-run-profiles.md` — run profile mechanics (what `coldstart-100` configures) and CI scope.
- `scripts/New-ReadyToRunCandidate.ps1` — builds the candidate used above (full parameter reference in its own
  comment-based help).
- `scripts/Invoke-ColdStartGate.ps1` — the script launched above (full parameter reference in its own
  comment-based help).
- `scripts/Invoke-ColdStartMatrix.ps1` — single local entry point running every platform's gate, with
  configurable concurrency.
- `scripts/Get-CiImageForDevelopment.ps1` — pulls an already-published test image from any host OS, without
  building one.
- `scripts/Invoke-ContainerColdStart.ps1` / `scripts/Invoke-ContainerColdStartWorker.ps1` — runs the gate inside
  one Linux container.
- `scripts/Show-ColdStartMatrixReport.ps1` — renders every report found (local and containerized) as one table.
- `.github/workflows/quietcli2-readytorun.yml` — manual, informational workflow that runs this gate in CI, on
  Windows and on the same Linux matrix as `Invoke-ColdStartMatrix.ps1`.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
