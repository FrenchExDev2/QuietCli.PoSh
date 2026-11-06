# Core performance and integration evidence

## Scope and measurement rules

This document records the local measurements made on **6 November 2026** for commit `21d0441`, explains the Windows import change, and describes the mandatory portable integration coverage added afterwards. Historical measurements, current CI wiring and future test proposals are separate evidence categories.

The tested command uses only `FrenchExDev2.QuietCli.Core.PoSh` and explicit callbacks:

```powershell
$result = quiet -AsObject -WorkingDirectory $repository -Output {
    param($event, $runtime)
    # Update explicitly selected business counters or a streaming digest.
} -Complete {
    param($runtime)
    # Return the final bounded business summary exactly once.
} git status
```

The Git companion is absent and the handler registry must be empty. The example callbacks are explanatory; runnable callbacks and assertions live in the companion test project. Native output is streamed, not automatically captured. Tests retain counts, digests, timings and explicit fixture manifests. Native token counts, delivery sizes for `-AsObject`, monetary cost and unmeasured gains remain unknown.

## Windows fresh-session import: before and after

Each sample starts the current `$PSHOME` executable with `-NoProfile -NonInteractive`. One warm-up pair is discarded; seven baseline/import pairs are retained with alternating order. The baseline performs no import. The import interval surrounds `Import-Module` inside the child; it excludes process startup, JSON report emission and the parent engine. Filesystem caches are warm. This is a fresh-process/module measurement, not disk-cold startup or a normal user-profile benchmark.

The following focused Windows measurements used PowerShell **7.6.9 / .NET 10.0.14 / win-x64**. Duration is the median import interval; allocations are median signed paired differences from the baseline.

```text
┌─────────────────────────────┬─────────────┬───────────────┬────────────────────┐
│ Loader                      │ Duration    │ Import p95    │ Allocated MiB      │
├─────────────────────────────┼─────────────┼───────────────┼────────────────────┤
│ Cmdlet-based loader         │ 2 220.48 ms │   2 941.94 ms │              54.93 │
│ Host .NET APIs              │   211.23 ms │     352.68 ms │               6.99 │
└─────────────────────────────┴─────────────┴───────────────┴────────────────────┘
```

These snapshots observed about **90.5% less import time** and **87.3% fewer cumulative managed allocations**. This is a local observation, not a universal performance guarantee. Allocations are not retained-memory or working-set guarantees. CPU, managed heap, working-set/private-memory deltas, raw pairs and end-to-end invocation timing are also retained in the original reports. Signed differences are never clamped.

### Where the Windows time went

Independent fresh-process controls started with no PowerShell modules loaded. They measured the previous loader's operations and then repeated them in the same process:

```text
┌──────────────────┬────────────────────┬────────────────────┐
│ Operation        │ Duration first use │ Duration second use│
├──────────────────┼────────────────────┼────────────────────┤
│ Join-Path        │        1 086.33 ms │            0.29 ms │
│ Get-Content      │            7.93 ms │            1.05 ms │
│ ConvertFrom-Json │          885.10 ms │            0.24 ms │
│ Set-Alias        │            4.73 ms │            0.14 ms │
└──────────────────┴────────────────────┴────────────────────┘
```

`Join-Path` first resolves/autoloads Management cmdlets; `ConvertFrom-Json` first resolves/autoloads Utility cmdlets. Those first-use paths account for most of the observed delay in the minimal Windows session. Explicit module preloads, source reading, parsing and dot-sourcing are separate controls, not additive phases of the same import. These controls do not causally attribute any time to Defender, AMSI, storage hardware or a specific internal PowerShell implementation.

The loader still reads `protocol.json` and checks protocol version 1, block sizes 1,024–16,384 bytes and header limits 65,536–1,048,576 bytes. It now uses asynchronous `System.IO.File` reading, strict UTF-8 decoding, `System.Text.Json`, `System.IO.Path` and the public session-state provider API for alias creation. The exported `quiet` alias and lazy engine startup remain checked. Fresh-import tests reject autoloaded Management/Utility modules before later reporting code can load them.

## Local platform comparison

The following numbers come from the subsequent full Core/Git validation runs, not the focused before/after pair above. Seven import samples were retained per platform. Different PowerShell/CLR versions, Windows versus a Linux VM/container, scheduling and warm caches prevent a controlled OS ranking.

```text
┌──────────┬─────────────────┬─────────────┬─────────────┬──────────────┐
│ Platform │ PowerShell      │ Duration    │ Import p95  │ Allocated MiB│
├──────────┼─────────────────┼─────────────┼─────────────┼──────────────┤
│ Windows  │ 7.6.9           │   211.38 ms │   220.57 ms │         7.04 │
│ Debian   │ 7.7.0-preview.5 │   336.47 ms │   385.28 ms │         7.41 │
│ Alpine   │ 7.6.7           │   241.34 ms │   279.87 ms │         7.41 │
└──────────┴─────────────────┴─────────────┴─────────────┴──────────────┘
```

The observed CLRs were .NET 10.0.14, .NET 11.0.0-rc.3.26522.148 and .NET 10.0.13 respectively. All three local RIDs were x64. Each historical full run passed **115 scenarios**: 48 Core and 67 Git. The first live Windows run passed those functional checks but rejected concurrent root-README drift; its successful replacement used a frozen copy with matching project hashes. No ARM64 or remote GitHub execution is inferred from those local results. The new controlled scenarios described below postdate that 115-scenario snapshot.

## Real repository observations

The optional `RealStatus` suite inspected the existing LLVM and VS Code Insiders repositories. It used the exact same Git executable for subject and independent reference, checked reference output before and after every sample, and compared CR-normalized line counts, UTF-8 sizes and SHA-256 digests. A changing repository fails the sample. Git optional locks were disabled; no reset, cleanup, commit or network operation was requested on these repositories.

Each repository had a fresh profile-free process, a separately measured Core import, one first call starting the engine, and three calls reusing it. Durations below are milliseconds. Warm/reference/callback columns are medians of three observations.

```text
┌──────────────────┬──────────────┬──────────────┬──────────────┬─────────────┐
│ Repository       │ First quiet  │ Warm quiet   │ Git reference│ Callback    │
├──────────────────┼──────────────┼──────────────┼──────────────┼─────────────┤
│ LLVM             │   1 242.60 ms│     780.54 ms│     670.71 ms│      2.45 ms│
│ VS Code Insiders │   1 167.11 ms│     291.14 ms│     248.69 ms│      1.90 ms│
└──────────────────┴──────────────┴──────────────┴──────────────┴─────────────┘
```

Core imports in these already-prepared probes were 180.45 ms and 171.15 ms. Both engines used integrated hosting. Each command emitted four stdout lines: 100 bytes for LLVM and 102 bytes for VS Code Insiders, with no stderr. The Git companion stayed unloaded and `-Complete` ran once per call. Reference setup can warm cmdlet modules and filesystem caches before the first measured `quiet`; “first” means a cold engine session, not a completely untouched PowerShell host. Quiet invocation time includes dispatch and telemetry; engine-reported native intervals include drainage and are not an independent process stopwatch.

The original local metadata report is `dotnet-import-real-status-20261106.json`, SHA-256 `1E3873B2A868BA87739510C36B180F18161FDAB11311DF7E2BB852E0B4C4B790`. It and its referenced detailed reports were saved under the local temporary QuietCli2 report root. Temporary evidence may be cleared by the operating system; the tables above preserve the selected historical observations, not every raw timing pair.

## Mandatory controlled integration in CI

Import measurements, all ten diagnostic controls, and **eight owned repository states** run inside Core/All. `-Suite Integration` runs this focused subset. Existing LLVM/VS Code checkouts are not CI prerequisites. Fixture setup and human-output references use the independent `scripts/Ci.Process.ps1` runner; measured subject commands always use Core `quiet` callbacks. A fresh child imports the explicit Core only, asserts the exported alias path, an empty handler registry and absence of the Git companion before and after every scenario.

```text
┌──────────────────┬─────────────────────────────────────────────────────────┐
│ Fixture          │ Independently controlled state                          │
├──────────────────┼─────────────────────────────────────────────────────────┤
│ unborn           │ No commit; one staged new file                          │
│ clean            │ Committed tree and index agree                          │
│ mixed            │ Staged/unstaged edits, MM, deletions, rename, new files, │
│                  │ ignored file, leading hyphen, spaces and Unicode paths  │
│ conflict         │ Divergent local branches; intentional UU merge conflict │
│ detached         │ Clean detached HEAD                                     │
│ linked-worktree  │ Linked .git-file worktree with an independent edit      │
│ submodule        │ Local-only submodule with a dirty tracked file          │
│ bulk             │ 512 generated Unicode paths; reproducible seed 73594    │
└──────────────────┴─────────────────────────────────────────────────────────┘
```

Plain human-readable `git status` reuses the same comparison code as `RealStatus`, including one first engine call and three warm calls. A second oracle is constructed from literal fixture XY/path/rename expectations, using porcelain v2 `-z` records and destination/source rename fields, modes, submodule flags and object IDs computed from literal Git blob/tree/commit payloads. It is not derived from another parse of actual Git output. Each fixture is checked in byte callbacks and NUL-framed text callbacks at 1,024- and 16,384-byte read blocks. Exact SHA-256, native and business byte counts, NUL-record counts, exit code, zero stderr, both completeness flags and exactly one completion must agree. There are 32 machine-format subject calls plus 32 human-format subject calls across the eight fixtures.

Fixtures use fixed identities/dates, SHA-1 repositories, explicit line/rename settings, empty global/system configuration and disabled hooks/signing. Creation requires a new absolute owned root. All mutating setup stays below that root; a ceiling prevents parent-repository discovery. Only the local submodule source is allowed. Generated fixtures, seeds, partial reports, telemetry and final evidence stay within the current run directory so the existing artifact uploads retain them, including failure diagnostics. No existing repository is modified by this suite.

`Assert-CoreIntegrationEvidence.ps1` rejects missing import/diagnostic evidence, missing or duplicate states, missing block/mode combinations, incomplete streams, a loaded companion, and failed assertion qualification. Timing observations have no machine-dependent speed threshold. Core changes trigger `core-ci.yml`, which calls reusable `ci.yml` with `suite: All`; Git-only development retains its narrower suite. The shared worker enforces the evidence gate before reporting a successful Core result.

```text
┌───────────────────┬─────────────────┬───────────────────────────────────────┐
│ CI matrix         │ Architecture    │ Hosting / PowerShell                  │
├───────────────────┼─────────────────┼───────────────────────────────────────┤
│ Windows stable    │ x64 and ARM64   │ Process and InProcess; PS 7.6.7       │
│ Windows preview   │ x64 and ARM64   │ InProcess; PS 7.7.0-preview.5         │
│ Debian / glibc    │ x64 and ARM64   │ Existing native image / Auto hosting │
│ Alpine / musl     │ x64 and ARM64   │ Existing native image / Auto hosting │
└───────────────────┴─────────────────┴───────────────────────────────────────┘
```

These are configured workflow targets, not a claim that all remote jobs have executed. Actual PowerShell version, CLR, RID, engine mode and process identity remain in run evidence. CI keeps its revision-bound qualification gate and mandatory native phases. The controlled Git test does not qualify every Git version or the Git companion.

### Properties, malformed inputs and mutations

```text
┌───────────────────────────┬──────────────┬────────────────────┬─────────┐
│ Assertion family          │ Generated    │ Boundary / damaged │ Mutants │
├───────────────────────────┼──────────────┼────────────────────┼─────────┤
│ Import statistics         │           64 │                 68 │       4 │
│ Protocol specification    │           66 │                143 │       6 │
│ Human-record aggregation  │           65 │                  6 │       3 │
│ Controlled-status gate    │           32 │                448 │       5 │
│ CI receipt gate           │            8 │                128 │       4 │
└───────────────────────────┴──────────────┴────────────────────┴─────────┘
```

The corresponding deterministic seeds are 73591, 73593, 73592, 73595 and 73596. The controlled-status damaged envelopes vary failure, stderr, missing data, byte/record/digest corruption, zero/double completion and incomplete source/analysis states. Source-checked targeted mutants must be detected. These bounded catalogues test the new assertions; they are not exhaustive language, operator, Git or engine mutation coverage. Native C/C# campaigns remain independently defined by the existing CI matrix.

### Reproduction

From the monorepo root, with matching built binaries and existing prepared images:

```powershell
# Focused portable integration with its visible local monitor.
./scripts/Invoke-WorkspaceCi.ps1 -Suite Integration -SkipBuild

# All Core assertions, including the mandatory integration cases.
./scripts/Invoke-WorkspaceCi.ps1 -Suite Core -SkipBuild

# The same focused suite in prepared Linux images; no pull or guest network.
./scripts/Invoke-ContainerCi.ps1 -Suite Integration -Platform debian -Image localhost/quietcli2-debian-net11:2.56.0 -ExpectedRuntimeIdentifier linux-x64
./scripts/Invoke-ContainerCi.ps1 -Suite Integration -Platform alpine -Image localhost/frenchexdev-quality:alpine-pwsh-7.6.7-net11 -ExpectedRuntimeIdentifier linux-musl-x64

# Optional existing repositories, specified in a UTF-8 JSON array.
./scripts/Invoke-WorkspaceCi.ps1 -Suite RealStatus -SkipBuild -RepositoryConfig /absolute/path/repositories.json
```

Reports contain `Suites[].Performance` for imports/diagnostics and `Suites[].Integration` for controlled state evidence. Linux reports are copied under the container run's `guest/` directory. The launcher prints the actual run directory and monitor reopening command. Local monitors close automatically after saved terminal results; `-Headless` is reserved for CI.

## Further complex CI scenarios

The existing suite already covers large byte volumes, Unicode fragmentation, framing limits, duplex stdin, callbacks, cancellation/timeouts, PTY behavior and SQLite/protocol assertions. The following are proposals for extending end-to-end coverage, not completed claims:

1. **Seeded repository state machines.** Generate sequences of stage/edit/rename/commit/reset transitions in owned repositories. Check metamorphic invariants after every transition, retain minimized failing sequences, and compare different read-block boundaries. This extends the fixed eight-state oracle to transition behavior.
2. **Several PowerShell clients sharing one measurement database.** Run distinct Core-only command sessions concurrently, with different fixtures and deterministic output sentinels. Verify business-data isolation, independent lifecycle/outcomes, telemetry aggregation and engine disposal while another client continues. This extends existing C# SQLite concurrency to the complete facade/process path.
3. **Telemetry faults during successful native work.** Inject a locked, read-only or resource-limited private measurement store while consuming a large backpressured command. Require the native result and completeness to remain accurate, storage failure to remain explicit, and recovery not to replay the command or persist business content.
4. **Combined shutdown faults.** Combine cancellation, an inherited stdout handle held by a descendant, delayed stderr and an engine restart. Independently verify source completeness, process-tree ownership and the observed/unknown effect distinction. This extends the existing separate lifecycle and PTY cases to adversarial combinations.

Keep these campaigns bounded and deterministic, use the same visible-monitor/artifact rules, and qualify each new invariant with independent generated inputs and targeted mutations before making it a release requirement.

## Pinned PowerShell and CLR profiling in CI

Every Core/All entry of the reusable Windows/Linux matrix explicitly prepares **Profiler 4.3.0** and **dotnet-trace 10.0.750501** with `Initialize-Profilers.ps1`. Versions and archive SHA-256 values are fixed in that script. Packages are extracted to a private runner cache, not installed globally or into user profiles. The Linux host stages the verified tools into the networkless guest. Git-only development keeps its narrower suite.

Use `-Profiler` on the local workspace/container launcher to request the same separate pass. Without explicit tool paths it prepares the same pinned private cache. Normal import, callback and native timing samples finish before instrumentation begins. The owned bulk fixture is then reused for a diagnostic workload, with no Git companion loaded.

Profiler's `Trace-Script` exports line-level self/inclusive durations and a speedscope trace. Lines are classified as user callbacks/workload, Core PowerShell facade, PowerShell modules, or profiler/other scripts. Those are wall-clock line observations and can include untraced C# calls or waits.

Actual EventPipe collectors attach to the owned PowerShell PID and, with isolated hosting, the separate engine PID. Recording is acknowledged by the collector and its written NetTrace header before releasing the workload. Raw `.nettrace` files and converted speedscope views are required. Managed frame-name buckets distinguish Core C#, PowerShell runtime, .NET libraries and unresolved/other frames. Frame counts and PS line times are not an additive CPU-percentage partition; native Git time and unresolved frames are not relabeled as engine C#. Missing collectors, conversions or expected files fail the requested profiling pass.

Primary tool documentation: [Profiler](https://github.com/nohwnd/Profiler), [Profiler 4.3.0 package](https://www.powershellgallery.com/packages/Profiler/4.3.0), [Microsoft dotnet-trace documentation](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace).

## Published CI evidence artifacts

Windows artifacts are named `quietcli-core-evidence-<RID>-<channel>-<mode>-<SHA>`; Linux artifacts are named `quietcli-core-evidence-<RID>-Auto-<SHA>`. Upload runs with `if: always()`, including failed jobs, uses the pinned upload-artifact action, errors when no artifact is found, and retains evidence for 30 days. This configures publication by the workflow; it does not claim a remote run was dispatched by local validation.

`New-CoreEvidenceBundle.ps1` copies report JSON, diagnostic logs, fixture manifests/seeds, PS line/speedscope output and CLR traces while excluding staged workspaces, Git internals and tool caches. Its `evidence-manifest.json` records the exact revision, GitHub repository/run/attempt, runner identity and per-file sizes/SHA-256 values. Mandatory profiling receipts are checked against their actual trace files and hashes. Successful-looking receipts with missing or changed traces fail the CI evidence step; incomplete failure evidence is still uploaded. Checksums establish integrity, not standalone author authentication. Synthetic integrity-test inputs are labeled and do not count as real run profiling receipts.

For a local instrumented development run: `./scripts/Invoke-WorkspaceCi.ps1 -Suite Integration -SkipBuild -Profiler`. The integration report retains controlled-status assertion mutants, CI receipt-gate mutants and binary-evidence integrity tests in addition to the historical import/parser qualification.

### Human-readable matrix results

Every job bundle also contains **PERFORMANCES_RESULTS.md** and its structured JSON counterpart. A separate `performance-results` job downloads all ten matrix bundles, checks their revisions and hashes, and publishes one combined `quietcli-performance-results-<SHA>` artifact, with the Markdown also displayed in the GitHub job summary. The qualification gate requires that job to succeed. Missing jobs, failed functional runs, absent profiling or altered evidence remain explicit failures; the readable report is still uploaded with `if: always()`.

The generated report compares host/RID/CLR/engine mode, test outcomes, import median/p95 and allocations, each controlled Git state's first/warm/reference/callback durations, and PS line versus CLR frame categories. It explains what these measurements mean, marks unavailable data rather than inventing values, and does not turn frame-name counts into CPU percentages. Readers can assess the result before opening any raw trace.

## Validation of the added CI path

Local development validation on 6 November 2026 used an isolated source snapshot containing only this change, preserving concurrent allocation/telemetry work in the live checkout. Windows Core/All passed **119 scenarios** (52 Core, 67 Git), followed by successful pinned PowerShell and CLR profiling. The focused Integration suite passed all three top-level groups on Windows isolated hosting, Debian and Alpine. Each focused run additionally checks all eight controlled fixture states, generators, damaged inputs and targeted mutants; three groups is not a count of individual assertions.

```text
┌────────────────────┬─────────────────┬─────────────┬─────────────┬────────────────┐
│ Local context      │ PowerShell      │ Test scope  │ Passed      │ CLR collectors │
├────────────────────┼─────────────────┼─────────────┼─────────────┼────────────────┤
│ Windows InProcess  │ 7.6.9           │ Core + Git  │         119 │              1 │
│ Windows Process    │ 7.6.9           │ Integration │           3 │              2 │
│ Debian InProcess   │ 7.7.0-preview.5 │ Integration │           3 │              1 │
│ Alpine InProcess   │ 7.6.7           │ Integration │           3 │              1 │
└────────────────────┴─────────────────┴─────────────┴─────────────┴────────────────┘
```

All four contexts produced the required source-line profile and raw/converted CLR evidence. Evidence copying, trace checksums, per-context Markdown and the combined Markdown/JSON report were exercised locally. YAML and every embedded PowerShell block were parsed, and the six Windows/four Linux matrix rows plus report dependency were checked. These are local x64 observations, not remote GitHub or ARM64 execution. Real workflow artifacts are published when CI runs the delivered revision.
