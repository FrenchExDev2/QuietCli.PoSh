# Run profiles

A **run profile** is a named, data-only file that binds a script to default arguments, so that a measurement
campaign (for example "100 cold-start pairs" or "1000 cold-start pairs") is started with one short, reproducible
command instead of a long argument list.

Current results are recorded in [the qualification audit](audits/2026-11-08-run-profile-qualification.md), with the
[earlier campaigns](audits/2026-11-07-run-profiles.md) retained separately.

## Launch commands

All commands run from the repository root (`FrenchExDev2.QuietCli.PoSh`) in PowerShell 7.6+.

| Goal | Command |
|---|---|
| List profiles | `./scripts/Invoke-RunProfile.ps1 -List` |
| Run the 100-pair profile | `./scripts/Invoke-RunProfile.ps1 coldstart-100 -Arguments @{ CandidateModule = '<path to candidate .psd1>' }` |
| Run the 1000-pair profile | `./scripts/Invoke-RunProfile.ps1 coldstart-1000 -Arguments @{ CandidateModule = '<path to candidate .psd1>' }` |
| Preview without running | `./scripts/Invoke-RunProfile.ps1 coldstart-100 -WhatIf -Arguments @{ CandidateModule = '<.psd1>' }` |
| Run with PSProfiler | `./scripts/Invoke-RunProfile.ps1 coldstart-100 -Profiler -Arguments @{ CandidateModule = '<.psd1>' }` |
| Create a profile | `./scripts/New-RunProfile.ps1 -Name coldstart-500 -Script Measure-ColdStart.ps1 -Parameters @{ Runs = 500; Warmup = 5 } -Description 'Cold start, 500 pairs'` |
| Install the pinned profiler | `./scripts/Initialize-Profilers.ps1 -OutputDirectory <cache>` |
| Run the tests | `pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1` |
| Run the mutation campaign | `pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1 -Mutation` |
| Run all tooling tests with the shared visible monitor | `./scripts/Invoke-WorkspaceCi.ps1 -Suite RunProfiles -SkipBuild -TimeoutSeconds 600` |
| Run every tooling mutant with the shared visible monitor | `./scripts/Invoke-WorkspaceCi.ps1 -Suite RunProfilesMutation -SkipBuild -TimeoutSeconds 3300` |
| Run one mutant | `pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.ps1 -MutantName whatif-ignored` |
| Mutation campaign with a JSON report | `pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.ps1 -OutputPath ./mutation.json` |
| Use the benchmark directly | `./scripts/Measure-ColdStart.ps1 -BaselineModule <a.psd1> -CandidateModule <b.psd1> -Runs 100` |

Per the workspace rules, a test or mutation run started by an agent is also given a visible `pwsh` monitoring
window (`Start-Process pwsh -WindowStyle Normal ...`). `-Mutation` of a single mutant takes about 35 s; the whole
catalogue takes about 15 minutes.

## Profile file format

`scripts/RunProfiles/<name>.profile.ps1` holds exactly one hashtable literal:

```powershell
@{
    SchemaVersion = 1
    Name          = 'coldstart-100'
    Description   = 'Cold start A/B: 100 interleaved pairs, 95% bootstrap interval'
    Script        = 'Measure-ColdStart.ps1'
    Parameters    = @{
        BootstrapResamples = 2000
        Confidence         = 0.95
        MaxFailedPairs     = 5
        Runs               = 100
        Seed               = 20261107
        Warmup             = 5
    }
}
```

Rules, enforced by `Assert-RunProfile` and `Read-RunProfile`:

- **Data only.** The file is parsed with `[scriptblock]::Create(text).CheckRestrictedLanguage(...)` with no allowed
  commands and only `true`/`false`/`null` as variables, so a profile can never execute code. A file containing a
  command, a variable or a subexpression is rejected before anything runs.
- **Value types.** Strings, integers, longs, doubles, booleans and arrays of them. `NaN` and infinities are refused.
  Doubles keep their type when rendered (`0.95`, and `1.0` rather than `1`).
- **Names.** `^[a-z0-9][a-z0-9-]{0,63}\z` (`\z`, not `$`, which would accept a trailing newline). The file name
  must match the `Name` field.
- **Target script.** `^[A-Za-z0-9][A-Za-z0-9._-]*\.ps1\z`, resolved inside the script directory only (no path
  separators).
- **Deterministic rendering.** Parameters are sorted (case-sensitive), UTF-8 without BOM, LF line endings, so the
  same profile always produces byte-identical files.
- **Unknown keys are errors**, at every level, with a coded message.

## Scripts

| Script | Role |
|---|---|
| `scripts/New-RunProfile.ps1` | Validates and writes a profile. Refuses to overwrite without `-Force`. Checks that every key is a real parameter of the target script (`Get-Command -Name <path> -CommandType ExternalScript`). Supports `-WhatIf`. |
| `scripts/Invoke-RunProfile.ps1` | `-List` shows names, targets and parameter counts. `-Name` loads a profile, merges `-Arguments` over the profile parameters (caller wins), validates the keys against the target and runs it. `-WhatIf` stops before the run. |
| `scripts/Measure-ColdStart.ps1` | Cold-start A/B benchmark that profiles use. Interleaved, randomised pairs; each child process runs through `quiet -AsObject -Output {...} -Complete {...}`; a failed pair is discarded, never retried; two result tables (distribution, paired confidence interval and verdict). |
| `scripts/Initialize-Profilers.ps1` | Downloads and verifies pinned Profiler 4.3.0 and dotnet-trace 10.0.750501 into the explicit `-OutputDirectory`. `-Offline` verifies/extracts cached archives and fails on a cache miss. No global installation. |

`LogLevel` and `LogPath` given to `Invoke-RunProfile.ps1` are forwarded to the target only when the target declares
them and the caller or profile did not set them explicitly.

## Library modules (`scripts/lib`)

Each module has one responsibility and a documented, exported surface; dependencies point from scripts to modules
and never between unrelated modules.

| Module | Responsibility |
|---|---|
| `RunLog.psm1` | Leveled logger (`Trace`, `Debug`, `Info`, `Warn`, `Error`, `Off`) with pluggable sinks (console on stderr, append-only file, in-memory) and **counters**: `log.<level>` for every emitted line, `log.suppressed` for filtered lines, `Time(name, body)` producing `name.count/.ok/.failed/.ms`, child loggers sharing the parent's counters, sorted `Snapshot()`. A failing sink is counted (`log.sinkfailed`), never fatal. |
| `RunFormat.psm1` | Compact durations (`12ms`, `1s`, `1m30s`, `2h5m`, `-` when unknown), Unicode box-drawing tables (equal-width lines, widest column shrinks first, `…` truncation, right-aligned numbers), counter tables, safe PowerShell string literals (control characters rejected, typographic quotes doubled). |
| `RunEncoding.psm1` | The single text-encoding policy. **Files are a fixed contract**: UTF-8 without BOM, LF line endings (CRLF and lone CR are normalized on write), strict decoding on read, strict encoding on write (lone surrogates and malformed bytes are errors, never replacement characters). **The console boundary is a parameter**: `Resolve-RunConsoleEncoding` / `Set-RunConsoleEncoding` accept `utf-8` (default) or `oem`. Every file read, write and append of the tooling goes through it. |
| `RunStatistics.psm1` | Quantiles with linear interpolation, summaries (N, Min, Q1, Median, Q3, Max), seeded percentile bootstrap of the median of paired differences, and the verdict. |
| `RunProfileStore.psm1` | Profile names, paths, validation, restricted-language reading, deterministic rendering, writing, argument merging, target resolution and target parameter checks. |
| `RunProfiler.psm1` | Locates the pinned PSProfiler (explicit path, then `QUIETCLI_PROFILER_MODULE`, then the cache; version must be 4.3.0) and exports the top-50 self-duration lines and functions of a traced script block as `<Label>.profile.json`. |
| `RunColdStart.psm1` | Validates exactly three finite, nonnegative invariant-culture measurement fields before the benchmark admits a sample. Duplicate result markers are rejected by the benchmark callbacks. |
| `RunToolCache.psm1` | Owns the pinned package catalogue, digest checks before writes/extraction, offline cache behavior and tool receipt. Its byte-provider boundary allows network-free tests of downloads. |

## Encoding

| Boundary | Setting | Why |
|---|---|---|
| Files on disk (profiles, logs, JSON reports) | Fixed: UTF-8, no BOM, LF, strict | Repository rule, and byte-identical rendering depends on it. Not configurable. |
| Console of the tests and of the mutation runner | `-ConsoleEncoding utf-8` (default) or `oem` | `quiet` decodes the child's output as strict UTF-8. A child printing the box-drawing tables in the OEM code page makes `quiet` fail with `DecodeOrFramingFailed`. Choosing `oem` is allowed so that the failure can be reproduced and diagnosed; the mutation runner then reports the cause instead of an opaque failure. |

```powershell
pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1 -ConsoleEncoding utf-8
pwsh -NoProfile -File ./FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.ps1 -ConsoleEncoding utf-8
```

Prefer the shared launcher: its CI process helper explicitly decodes both child streams as UTF-8 and the existing
read-only monitor reads only the run's status files. No `Tee-Object` decoding boundary is involved. A custom monitor
that tees native output must independently select UTF-8 before reading it.

## Statistics: how noise is eliminated

- Baseline and candidate runs are **interleaved in random order** (seeded), so slow drift of the machine hits both
  members of a pair alike.
- For each pair the difference `candidate - baseline` is computed. The **median of the differences** is estimated
  with a **seeded percentile bootstrap** (resampling pairs with replacement); the interval is two-sided at the
  profile's `Confidence` (0.95 for 100 pairs, 0.99 for 1000 pairs).
- Verdict: `faster` only if the whole interval is below 0, `slower` only if it is above 0, otherwise
  `inconclusive`. Below **20 pairs** the verdict is `too-few-pairs`: with 3 pairs an A/A run once produced a
  spurious "slower", which is why the guard exists.
- Failed pairs are discarded and counted, up to `MaxFailedPairs`; the run fails beyond that.
- An A/A run (the same module twice) is the control for the method itself: the interval must contain 0 in about
  `Confidence` of the campaigns. Run it before believing an A/B result.

## PSProfiler

`-Profiler` on `Invoke-RunProfile.ps1`, or `-ProfileImport` on `Measure-ColdStart.ps1`, runs one **extra** profiled
child per variant. It is not part of the timed samples. The reports are JSON files in the profile output directory
(`%TEMP%\QuietCli2-coldstart-profiles\import-baseline.profile.json`, `import-same.profile.json`).
PSProfiler traces PowerShell only: C# time is invisible to it and appears as the cost of the calling line.

## Tests and mutation testing

Property, fuzz, example and integration cases live in `FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Tests.ps1`
(standalone runner: the exit code is the number of failed cases, seeds are fixed, the last line is
`SUMMARY Passed=N Failed=N Skipped=N`).

- **Property:** name regex versus an independent character-class oracle; render-then-load identity; merge is a
  right-biased union; quantiles are bounded, monotone and shuffle-invariant; every table line has one width.
- **Fuzz:** malformed profile files and code injection attempts are rejected and never executed.
- **Example:** exact quantiles, verdict boundaries, duration units, truncation, schema violations.
- **Integration:** a fixture target script in a temporary directory exercises create, run, `-WhatIf`, `-List` and
  the `LogLevel` forwarding rule.
- **Encoding:** exact bytes of written and appended files (no BOM, LF), strict reads and writes, console name
  resolution, and a live `quiet` check that a UTF-8 child succeeds and an OEM child fails with `DecodeOrFramingFailed`.
- **Profiler:** skipped, and reported as a gap, when the pinned module is absent.
- **Benchmark:** independent duration properties and malformed-input corpus; the actual script with a deterministic
  native boundary checks variant identity, warm-up exclusion, failed-pair rejection without retries, failure budgets,
  paired differences, separate profiling and report paths containing spaces. A live A/A smoke case measures six fresh
  processes. This smoke test does not estimate the false-positive rate of the verdict.
- **Profiler/cache:** resolver precedence and pinned version, generated trace-row projections, missing-trace rejection,
  offline ZIP fixtures, cache reuse, tampered packages, missing entrypoints and injected downloaded bytes. A live case
  runs the initializer against copies of both official cached archives without network access.
- `-Skip` takes case-name fragments, comma-separated (`pwsh -File` passes an array argument as one string). The
  mutation runner skips only the live `profiler:`, `console:`, `coldstart-live:` and `tool-cache-live:` cases. Independent
  profiler, benchmark and cache assertions still run against every mutant in its disposable sandbox.

`RunProfiles.Mutation.ps1` applies one source substitution at a time to a fresh sandbox copy of `scripts/` and the
suite, then runs the suite through `quiet` and reads its `SUMMARY` line. Outcomes: **Killed** (a case failed),
**Survived** (all passed: a missing assertion or an equivalent mutant that must be justified), **Crashed** (no
summary, the mutant does not parse), **Timeout**, **Invalid** (the target text does not occur exactly once). The
baseline must be green first. Survived, Crashed, Timeout and Invalid outcomes all fail the gate. The catalogue is
the `$catalogue` array in that file: `{ Name; File; From; To }`.

The shared `ci.yml` runs the complete suite and catalogue on Windows x64 stable integrated hosting for Core/All,
uploads reports even on failure and requires their success through the existing Windows qualification dependency.
Git-only development retains its narrower scope. The full tooling suite rejects skipped required cases, so a missing
pinned profiler cannot silently qualify a release. This CI scope does not qualify tooling on other platforms.

## ReadyToRun candidate (local A/B)

`scripts/Build-Workspace.ps1 -ReadyToRun` publishes the engine precompiled (Crossgen2) instead of a plain IL
build. It must not overwrite the baseline you want to compare against, so build the candidate in a separate
copy and point `-CandidateModule` at it, per `Measure-ColdStart.ps1`'s own example:

```powershell
# 1. Baseline already built normally (./scripts/Build-Workspace.ps1), left in place.
# 2. Copy the module and global.json aside.
$candidateRoot = 'C:\tmp\r2r'
Remove-Item $candidateRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $candidateRoot | Out-Null
Copy-Item .\global.json $candidateRoot
Copy-Item .\FrenchExDev2.QuietCli.Core.PoSh (Join-Path $candidateRoot 'FrenchExDev2.QuietCli.Core.PoSh') -Recurse

# 3. Rebuild only that copy's lib/inprocess with ReadyToRun (do not run the full Build-Workspace.ps1
#    orchestration against the copy: it is not a full workspace, only the module directory).
. .\scripts\Common.ps1
$project = 'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
$output  = 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'
$inputs  = @(Get-QuietBinaryInputs $candidateRoot $project)
dotnet publish (Join-Path $candidateRoot $project) -f net10.0 -c Release -r win-x64 --self-contained false `
    -p:PublishReadyToRun=true -o (Join-Path $candidateRoot $output) --nologo
Write-QuietBuildManifest $candidateRoot $project $output -Inputs $inputs -Configuration Release

# 4. Compare with the 100-pair profile (seed fixed, 95% bootstrap interval).
./scripts/Invoke-RunProfile.ps1 coldstart-100 -Arguments @{
    CandidateModule = (Join-Path $candidateRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
    CandidateLabel  = 'readytorun'
}
```

Use `-r linux-x64` (or the matching Linux RID) instead of `win-x64` on a Linux machine. Run an A/A control
first (same module as both baseline and candidate) if the 100-pair profile has never been validated on this
machine — see "Statistics: how noise is eliminated" above. A visible `pwsh` monitoring window is still
required for the run, per the workspace test rules.

`-ReadyToRun` on `scripts/Build-Workspace.ps1` also adds `-p:PublishReadyToRun=true` to every `lib/engine/<rid>`
publication (net11.0), for a later CLR-11-host comparison; this is unverified against the pinned .NET 11 RC
SDK's Crossgen2 package availability per RID.

## Known gaps

- The false-positive rate of the verdict at 100 and 1000 pairs has not been measured with an A/A campaign yet.
- The ReadyToRun A/B campaign has not been run with these profiles yet.
- Mutation coverage is the committed targeted catalogue, not exhaustive fault coverage. Actual HTTP connectivity is
  outside the offline tests; the pinned official archives and real profiler are exercised separately.
