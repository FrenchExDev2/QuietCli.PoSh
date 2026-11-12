<p align="center">
  <img src="./../icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Core.Tests.PoSh

Host-matrix assertions require Windows, Linux selection/results and performance prerequisites as a set, allowing reordered/additional dependencies while rejecting each removed prerequisite. Evidence properties include bracketed Unicode paths and owned hidden manifests. CI uploads only the prepared evidence tree with hidden files included. Mutation workers write a start receipt and a terminal receipt in finally; parents retain bounded output tails/process metadata and reject absent or unfinished receipts even after exit code zero. An abrupt-exit fixture verifies that boundary; this does not claim a native ARM64 rerun.

Release tests exercise a unique batch leader, remote sibling-tag revision rejection, dependency-ordered Core/Git validation and mock publication, and no-write previews. The leader qualifies/packages once, while PR validation remains independent. Legacy tags without annotations retain standalone releases.

## Test boundaries and local work branches

Core mixes pure logic with real filesystem, Git, process and package integration. Local feature/fix commits and pushes do not require automatically running these companions. Every top-level case reports explicit TestKind/Dependencies and shows its classification in progress. The shared static check and runtime guard reject missing or malformed metadata before selection; there is no Unclassified fallback. Pure byte-count checks are independently selectable as `-Case 'unit byte-count*'`. Runner bootstrap/report I/O is separate from a pure case body. See [classification and concurrency](../docs/README-test-classification-and-concurrency.md) for the complete boundary and reviewed parallelization candidates, and [the commit-suite and PSDrive review](../docs/testing/commit-workspace.md) for actual temporary repository effects.

## GitHub execution policy and Docker smoke

`PrivateData.QuietCli.TestExecution` in this companion's manifest declares Ordered defaults, Exclusive measurement barriers and one reviewed IsolatedProcess audit case. Core saves its resolved execution plan before cases run and batches adjacent eligible cases with a cap of two or the smaller caller budget. Each child owns configuration, SQLite and reports and receives one internal worker. `scripts/Test-TestCaseMetadata.ps1 -Plan` previews the complete plan without importing Core or executing a case. The same policy is consumed locally and in CI; Git/Vagrant fan-out still follows complete Core acceptance.

See [Qualification: when, where and how](../README-qualification-when-where-how.md) for PR triggers, the six Windows and four Linux environments, build versus test execution, local launchers and qualification exclusions.

In a source checkout, the companion loads `scripts/Common.ps1` into its own private module scope, including the CI process,
JSON, source-identity and project-discovery helpers. Test functions do not depend on a caller script
or workstation profile having loaded those functions. The focused case `GitHub CI companion helpers
load privately without caller profile dependencies` verifies exact helper source paths and no export
leaks in a bounded child PowerShell process; `-NoProfile` is intentional isolation for that regression.
Architecture assertions distinguish portable integrated hosting from a selected ReadyToRun RID slot,
using the actual host CLR and its build manifest. Isolated hosting still requires the native RID.
Source-free test packages retain their offline Recall tools and do not require workspace orchestration
scripts merely to import. Shared workspace suites still run from a prepared source checkout.

Performance bundles keep a checksummed partial manifest when collection rejects a link or fails to
read a report, so downstream rendering preserves the original gap. Linked agent-test fixtures remove
only their link after assertions; their target stays untouched. Unicode child fixtures initialize their
own UTF-8 output. The resource cleanup test holds its live lease in a separate process, matching Unix
cross-process file-sharing semantics. Container-input tests cover docs, restored packages and traversal.

The focused case `GitHub CI JSON receipts create missing parents and preserve preview boundaries`
reproduces receipt publication on a clean checkout. It covers seeded Unicode writes and overwrites,
relative paths, blocked parent paths, temporary-file cleanup and a directory-creation mutant. The real
matrix selector runs offline for Core/Git/All with image adapters, checking output append and WhatIf
without a preceding directory-preparation step. This case is filesystem integration, not live GHCR
or hosted-runner qualification.

The Core case `GitHub CI separates native containers, Docker fallback and workstation launchers`
checks cache-availability combinations, shuffled targets, malformed references, native runner
identities, terminal-state gates and targeted policy mutants. Its direct-entry fixture requires the
worker to run in the caller's process and rejects a non-GitHub context before side effects. Adapter
fixtures check Docker/Podman vectors for all four RIDs and the Core-to-consumer credential handoff.
Workflow assertions also require explicit cancellation and successful-selection conditions on both
Linux execution paths, so PR-only skipped publication ancestors do not suppress selected matrices.

```powershell
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-GitHubCiSmoke.ps1 -Image '<existing-linux-x64-toolchain-image-ID>'
```

This smoke opens the shared local monitor and runs the GitHub entry in a real Docker container,
without pulling/building/publishing an image. It saves guest RID/runtime/PID and cleanup evidence.
It exercises the focused import suite; it does not qualify hosted Windows/ARM or registry permissions.

Module de tests indépendant du moteur. Dépend du module Core, jamais l’inverse.

## Production instruction and skill examples

`./scripts/Invoke-WorkspaceCi.ps1 -Suite AgentInstructions -SkipBuild` runs the focused
monitored suite. It checks generated reference preservation/idempotence, malformed markers,
UTF-8/BOM handling, WhatIf, linked paths, installed-layout resources, document-set consistency (concise, self-contained, every command named, `SKILL.md` generated from `AGENTS.md`) and targeted reference
mutations. Eleven marked Core-only examples in `docs/agents/AGENTS.md` (4) and `docs/agents/examples.md` (7) execute against an owned
Git fixture and verify business objects, bounded JSON/YAML, gain reporting, memory/durable
Recall, replay and ZIP export/import. Core/All includes the same regression. This targeted
development evidence does not replace release qualification or a Gallery installation test.

## Persistent PowerShell benchmark

```powershell
# Objective: Compare normal-profile fresh processes, persistent sessions and retained results.
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-PersistentShellBenchmark.ps1

# Objective: Run a shorter validation before collecting a larger performance sample.
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-PersistentShellBenchmark.ps1 -Iterations 3 -CommandCounts '1,5,10'
```

The standalone launcher opens the existing read-only, resizing monitor and runs the coordinator
in the background. It saves terminal reports before the monitor closes. The printed monitor
command can reopen the report. Local runs require Windows; this script does not claim Linux
qualification. Reports, fixture repositories and configuration directories remain under the
shared temporary `tests/persistent-shell-*` root unless `-RunDirectory` selects a new directory.

Only the selected local **Core** module is imported. `New-QuietGitRepositoryFixture` is copied
into `PersistentShell.Support.ps1` from the Git test companion, with a local `Invoke-GitFixture`
preparation helper. Neither the Git business module nor the Git test companion is loaded.
Every native execution uses `quiet` with explicit callbacks. The fixture has a committed base,
one modified file and one Unicode untracked path. Dedicated byte-mode `-Output` and `-Complete`
callbacks count NUL records and bytes and compute SHA-256 for `git status --porcelain=v1 -z`.
Assertions compare these against literal independently predicted fixture bytes, including
native exit status, complete source/analysis, stderr and exactly one finalization.

Each sample sets `QUIETCLI_CONFIG_DIRECTORY` to its own temporary directory. The public
`New-QuietCliConfiguration` cmdlet creates the complete default YAML template. Only telemetry
database and recall storage destinations are changed to owned temporary paths; hosting remains
`Auto`, and tokenization and telemetry keep their defaults. User configuration is not edited.
Git configuration, hooks, signing, author identity and repository discovery are isolated.

For each sequence length, one warm-up triple is discarded. Retained repetitions alternate
the order of Fresh/Persistent/Retained. Fresh launches one normal-profile PowerShell per request;
Persistent sends sequential stdin requests to one process, waiting for each response before
sending the next; Retained executes Git once and repeatedly presents the same in-memory result.
The protocol accepts only the fixed `RUN` request, never executable input. PID, random session
token, request index, reference identity and cumulative native execution count are checked.
Each response generates the same bounded JSON representation policy. Detailed samples preserve
first/subsequent command times, import times, local round trips, output byte counts and observed
child working-set/private-memory snapshots.

`summary.json` contains raw samples, paired signed savings, reduction percentages, acceleration
ratios and count/min/median/nearest-rank-p95/max statistics. Existing statistics validation is
reused. Seed 73606 adds 96 generated contract cases, 864 damaged/missing-state cases and six
targeted assertion mutants, reported separately from the existing statistics campaign. A failed
or incomplete sample fails the run; there is no performance threshold. Use more repetitions
(for example `-Iterations 30`) before interpreting tail percentiles. The script does not rebuild,
install dependencies, change profiles, access the network or publish anything.

Elapsed time includes parent QuietCli dispatch, child startup, normal profile, Core import,
sequential local pipe exchanges and shutdown. Configuration creation and fixture preparation
are outside the measurement. This does **not** measure Codex tool-call/model latency, PTY echo,
disk-cold caches, aggregate engine-process memory or a retained-memory guarantee. Retained-result
savings are a separate optimization because they avoid native executions. Keep raw observations
and host/source identity when comparing runs; temporary reports are not durable archives.

- `fixture/` : producteur/consommateur C# de bytes dont les volumes sont connus indépendamment.
- `engine-tests/` : assertions C# de cadrage, limites, EOF, interdiction de stocker des objets métier et concurrence SQLite.
- The 22 C# cases include bounded protocol paging, independent native drainage, safe telemetry projection, read-only installed resources, incremental text framing and exact aggregate query budgets.
- Le module PowerShell vérifie les compteurs, Unicode fragmenté, NUL, stdin, 64 Mio de sortie, callbacks imbriqués, erreurs, timeout, annulation, PTY, contextes et formats.
- Un getter métier qui lève une exception prouve que `-AsObject` ne parcourt pas l’objet pour calculer les mesures.
- Les six publications Windows/Linux x64 et ARM64 sont contrôlées par leurs en-têtes PE/ELF, paramètres de compilation et manifestes ; ce contrôle statique ne remplace pas l’exécution native dans les jobs ARM.
- Les deux nupkg PSGallery sont préparés puis extraits dans une arborescence d’installation isolée. Un processus sans profil charge Git et sa dépendance Core depuis ces seuls paquets, démarre le moteur publié et vérifie Git dans un dépôt dédié. Ce contrôle local ne prétend pas télécharger une version déjà publiée sur PSGallery.
- Le harnais `audit/` fournit des régressions bloquantes ; la provenance rejette les binaires modifiés et les sources périmées. Le packaging est aussi vérifié avec des chemins relatifs puis importé hors des sources.
- `tools/documentation/` est un outil de maintenance explicite ; il ne s’exécute jamais pendant les tests ou les builds normaux.

Depuis le workspace : `./scripts/Invoke-WorkspaceCi.ps1 -Suite Core`. Le lanceur construit les projets et ouvre la fenêtre de suivi. Les rapports conservés comportent chaque assertion et son résultat. Les tests n’installent aucun outil sur l’hôte et utilisent leur propre base SQLite.

Une suite vide, un crash ou un prérequis manquant n’est jamais converti en succès.

## Fresh-session Core import cost

`Import.Tests.ps1` runs on Windows and Linux using the current host's exact `$PSHOME` executable. It is included in Core/All; the focused `Import` suite avoids unrelated functional tests and does not need a rebuild when matching binaries already exist:

```powershell
# Objective: Measure the local Core import with a visible monitor and saved reports.
./scripts/Invoke-WorkspaceCi.ps1 -Suite Import -SkipBuild

# Objective: Repeat inside existing networkless Linux images with host monitoring.
./scripts/Invoke-ContainerCi.ps1 -Suite Import -Platform debian -Image localhost/quietcli2-debian-net11:2.56.0 -ExpectedRuntimeIdentifier linux-x64
./scripts/Invoke-ContainerCi.ps1 -Suite Import -Platform alpine -Image localhost/frenchexdev-quality:alpine-pwsh-7.6.7-net11 -ExpectedRuntimeIdentifier linux-musl-x64
```

Each run discards one warm-up pair and retains seven baseline/import pairs, alternating their order. Each arm starts a fresh process. Only the measurement children use `-NoProfile -NonInteractive`, deliberately isolating the module from user profiles; the launcher and monitor retain normal profiles. This is a fresh module/process measurement with warm filesystem caches, not disk-cold startup or an estimate of normal profile loading.

The probe measures the `Import-Module` interval, CPU, total managed allocations, managed heap delta, working-set delta and private-memory delta. Baseline performs no import. Reports preserve raw observations, signed paired differences and count/min/median/nearest-rank-p95/max for each metric. `InvocationElapsedMs` separately includes process startup/shutdown, probe JSON and parent QuietCli dispatch/callback/telemetry overhead; it is not pure PowerShell startup. Memory deltas are noisy observations, not guaranteed retained memory. No monetary conversion or speed threshold is applied.

The probe rejects a preloaded Core/engine, checks the exact loaded path and `quiet` alias, and verifies that import leaves the engine and managed helper unstarted. It never calls `Get-QuietEngine`. The parent test uses its existing Core engine to launch probes; parent overhead is outside the measured import interval. The monitor and summary retain the actual host version, CLR, RID and source identity. Windows and Linux hosts with different PowerShell/CLR versions are separate observations, not a controlled OS comparison. ARM64 uses the same test but requires actual ARM64 execution to establish results.

`summary.json` contains `Suites[0].Statistics`, `Samples`, `Pairs` and `Validation` for the focused suite; full Core runs retain the same object under `Suites[].Performance`. Linux results are in the container report's `guest/summary.json`. The launcher prints each temporary report directory and its monitor reopening command. Statistics validation retains seed 73591, 64 generated finite-vector properties, 68 malformed/boundary inputs and four source-checked targeted mutants with individual outcomes. This small catalogue qualifies the new statistics, not exhaustive PowerShell mutation coverage or the existing product implementation.

The loader reads protocol JSON through asynchronous .NET file I/O and `System.Text.Json`, combines paths with `System.IO.Path`, and creates the exported alias through the public PowerShell session-state provider API. A fresh import must not autoload `Microsoft.PowerShell.Management` or `Microsoft.PowerShell.Utility`. Their first-use initialization belongs to the cost of the previous cmdlet-based loader and is explicitly isolated by the diagnostic controls below. No security setting is changed.

`ProtocolSpecification.Tests.ps1` checks all six protocol constants, inclusive frame bounds, missing/wrong JSON types and malformed UTF-8. It retains seed 73593, 66 valid properties, 143 malformed/boundary cases and six targeted validation/decoder mutants. Core/All and RealStatus execute this regression. It does not compile or start the engine.

## Real repositories with Core callbacks only

Create a UTF-8 JSON array of existing repository roots outside the checkout, then run from the monorepo root:

```powershell
# Objective: Verify plain git status on explicit real repositories with a visible monitor.
./scripts/Invoke-WorkspaceCi.ps1 -Suite RealStatus -SkipBuild -RepositoryConfig /absolute/path/repositories.json
```

For the local Windows setup, the configuration contains:

```json
[
  "C:/code/FrenchExDev/FrenchExDev_i2/LLVM/llvm-project",
  "C:/code/FrenchExDev/FrenchExDev_i2/VsCode/FrenchExDev/VsCodeInsider"
]
```

This opt-in suite requires those real repositories and is not implicitly added to CI or copied into Linux containers. The probe itself is portable when given local repository roots. Each repository gets a fresh profile-free process which imports only the explicit Core manifest. It checks an empty handler registry and absence of the Git companion before and after all commands.

The measured business call is `quiet -Output { ... } -Complete { ... } git status`, with `-AsObject`, newline records and explicit working directory. Callbacks retain only per-stream line/UTF-8 counters and streaming SHA-256 digests. The independent shared CI runner brackets every sample with a reference `git status`; changing output fails the sample instead of becoming a product defect. Optional Git locks are disabled. No fixture, reset, cleanup, hooks or network operation is requested on a real repository.

The report separates Core import, first call with a cold engine, three calls reusing the engine, independent reference timing and callback timing. Native intervals are the engine's reported observations; wall-clock invocation intervals include Core dispatch and telemetry. Order and warm-cache effects limit performance comparisons. `-Complete` must run once, exit must be zero, both completeness flags must hold, and reference digests/counts must match. `Status.Aggregation.ps1` is also checked in Core/All using seed 73592, 65 generated Unicode properties, six boundary inputs and three targeted mutants.

`Import.DiagnosticProbe.ps1` compares fresh imports, same-process reimports, explicit preloading of PowerShell's Management/Utility modules and separate read/parse/dot-source controls. Controls run in independent processes and are not additive phases of one import. In particular, the source-only dot-source control uses a diagnostic module scope. `summary.json` retains all controls under `Suites[0].Diagnostics`, repository evidence under `Repositories`, and generator/mutation evidence under `Validation` and `ProtocolValidation`. Incremental evidence survives in `real-status.partial.json`. Security-product activity is not causally isolated by this test.

`SecondPass.Tests.ps1` verifies gain group paging and report cleanup, then compares the former PowerShell aggregation with C# in both engine modes. It also measures short-record and long-fragment framing with independent expected counts. `Gain.Baseline.ps1` is test-only. Timing scope, request counts and actual pipe bytes are retained in `Suites[].Performance`; see [the migration review](../docs/README-powershell-csharp-boundaries.md).

`Control.Tests.ps1` verifies an exact 1 MiB + 7 byte duplex copy in both hosting modes, rejected controls followed by a usable session, input/identity bounds, and direct-versus-JSON request accounting. Its timing samples compare identical 1 MiB stdin/hash workloads through local JSON or typed controls. Startup, hashing and drainage are included; actual pipe traffic is zero for both local samples.

`InputBackpressureCases.cs` uses a controlled input sink with no native stdout. Once the full queue becomes writable, the next event poll must complete immediately instead of waiting for unrelated output. This assertion uses explicit synchronization rather than a timing speed threshold. Both possible channel waits are canceled and observed before the normal bounded poll finishes.

## Native PTY regressions

The standalone C harness in native-tests/ includes the bridge source and checks dimensions, PATH lookup without implicit current-directory entries or shell fallback, inherited descriptors above a lowered limit, pre-session signal forwarding, private process-group descendants, real controlling-terminal setup, idle-input shutdown and failed-startup child reaping. Assertions remain enabled in optimized builds. The launcher also verifies static PIE, RELRO, immediate binding and a non-executable stack in all four shipped ELF resources.

From the monorepo root on Windows, run:

```powershell
# Objective: Run native PTY regressions with the pinned compiler and a visible monitor.
./FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyTests.ps1
```

The pinned Zig compiler and the default local Linux x64 image must already exist. Use -Image to select another prepared image. No tools are installed and no image is pulled. Reports, compiler diagnostics and individual assertions are saved under artifacts/pty-tests/. The launcher prints the command to reopen the monitor. This dedicated harness is separate from Invoke-WorkspaceCi; it does not establish native ARM64 qualification.

### Targeted mutation campaign

Run ./FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyMutation.ps1 from the monorepo root on Windows. It uses the same pinned Zig compiler, existing image and visible monitor as the native unit launcher. On Linux CI, use -CompilerPath gcc -Headless with an already available compiler. CI tools execute directly through System.Diagnostics.Process; no QuietCli engine is loaded.

GitHub CI excludes this native TTY/PTY campaign and uses `-SkipTty` for the Core, Recall and Git terminal scenarios. Local test defaults still include terminal scenarios; the standalone native campaign remains available for Debian/glibc and Alpine/musl on x64/ARM64. An unmodified baseline must pass all 43 assertions before 31 explicit single-site mutations are evaluated. The score covers this catalogue only; no exhaustive operator or line coverage is claimed. Survivors, compile failures, timeouts, infrastructure failures and stale mutation anchors fail the job; only assertion failures or fixture crashes count as killed mutants. Invalid and timed-out mutants remain separate from the score denominator.

Artifacts under artifacts/pty-mutation/ retain the catalogue, source/test SHA-256, compiler identity, mutated sources, compiler diagnostics, bounded test diagnostics, per-mutant outcomes, ELF checks and final summary. Local campaign reports retain failures. No remote workflow is dispatched by the local launcher.

Manual native campaigns use Invoke-ContainerCi.ps1 -Suite Mutation and the content-addressed native CI images. GCC and libc development headers are part of those images. ExpectedRuntimeIdentifier rejects the wrong guest before compilation. Windows x64/ARM64 validates the separate C# ConPTY implementation; this POSIX C bridge is tested on its four Linux targets.

### Properties and coverage-guided fuzzing

The baseline includes six property groups: every allowed dimension with leading zeros, 25,000 generated dimension strings, 25,000 generated control inputs plus boundaries, 256 fragmented real-PTY requests, all five truncated-frame disconnects with owned-child reaping, and 32 generated descriptor sets above a lowered limit. Seed 633419 and failing input files are retained. Signal/group invariants also have the existing exhaustive pre/post-session assertions.

Full native qualification supplies -RequireFuzz. The original source is exercised by Clang/libFuzzer for 20,000 executions with AddressSanitizer and UndefinedBehaviorSanitizer, seed 633419 and a 4096-byte input limit. The target covers pure dimension and resize decoding; process creation and descriptor behavior remain in mandatory isolated property tests. Compiler identity, corpus, execution count, bounded diagnostics and crash reproducers are saved. Use -FuzzRuns for a larger manual budget.

A prepared native image can set QUIETCLI_PTY_LLVM_RESOURCE_DIR to runtimes built from a local LLVM checkout. The directory must contain build.json with a successful build, exact source revision, matching guest RID and SHA-256 entries for libFuzzer, ASan, ASan C++, ASan static and standalone UBSan archives. Missing or mismatched artifacts fail before compilation. The fuzz report records the source revision and verified archives separately from the bootstrap compiler version. This explicit image mode does not change the default workflow images or require the QuietCli product to be built.

Assert-PtyQualification.ps1 requires all phases; all harnesses are required when claiming full native qualification. GitHub CI does not claim that scope. The standalone Windows/Zig mutation launcher does not request libFuzzer; use Invoke-ContainerCi.ps1 -Suite Mutation with a prepared native image for full qualification. GCC, Clang and sanitizer runtimes are installed only in the test images.

### No product bootstrap dependency

Build/test scripts use Ci.Process.ps1, an ordinary PowerShell/System.Diagnostics tool runner. They neither call pump/quiet nor import Core. C source and its test headers can therefore be compiled and qualified before the .NET engine exists. GitHub CI builds/tests Core and Git without running native qualification, then checks the revision-bound publication gate.

Native staging is deliberately source-only: no Core/Git module manifest, .NET project, engine assembly or built fixture is copied. Probe-Independent.ps1 rejects such files and shadows pump/quiet with failing traps. The standalone native runner requires its zero-product/zero-AI-call receipt and confirms the actual container exit code before trusting any success report. GitHub Windows and Linux builds have no native-test prerequisite.

On musl, the LLVM 22.1.3 RSS-monitor allocation was observed leaking 56 bytes at shutdown. The paired reproducer keeps the same binary, execution budget and cgroup limit; only rss_limit_mb changes. CI uses the container's 1 GiB memory limit instead of that monitor on musl, and fails if the cgroup bound is missing. ASan, UBSan and LeakSanitizer remain enabled (-detect_leaks=1); there is no leak suppression. Allocation size is additionally limited to 512 MiB. This is a tool-runtime workaround, not a claim of an upstream fix.

The byte-write regressions inject zero progress, permanent errors, short writes and repeated EINTR without changing production code. A fixed set of 1,000 binary-payload schedules checks exact byte preservation. Three corresponding single-site mutants must be detected. Together with the process and stream regressions, qualification requires 43 assertions and 31 mutants.

The four stream regressions use an independent raw-terminal producer and compare a 1 MiB + 137 byte binary payload incrementally. They verify exact delivery to a slow consumer, resize acknowledgements while output is backpressured, killing/reaping after the output consumer disconnects even when the command ignores SIGHUP, and signal exit status with an intact output prefix. Synchronization uses pipe writability rather than assuming that queued bytes equal nominal pipe capacity. Fixture deadlines bound hangs and cleanup kills the owned command before waiting for the bridge. These assertions qualify correctness under backpressure; they are not a throughput benchmark.

On glibc x64 with Clang 14, the standalone fuzz executable is explicitly linked non-PIE to avoid reproduced ASan startup crashes under high-entropy address randomization. A controlled 32-start comparison also reproduced crashes in an empty ASan PIE program, while the empty non-PIE control passed every start. The layout is checked in the compiled ELF and recorded in the fuzz report. ASan, UBSan and LeakSanitizer remain enabled; no automatic retry or sanitizer suppression is used. This affects no shipped transport binary: all four bridges still require static PIE, RELRO, immediate binding and a non-executable stack. See [LLVM issue 81470](https://github.com/llvm/llvm-project/issues/81470) for the related runtime symptom.

## Mandatory portable integration

Core/All now requires the same fresh-import measurements, ten import diagnostic controls, and eight owned Git states provided by the focused `-Suite Integration`. Each fixture checks plain human status against the independent CI runner, then byte and NUL-text callbacks against literal porcelain expectations at two block sizes. The child imports Core only and rejects a loaded Git companion or nonempty registry. `scripts/Assert-CoreIntegrationEvidence.ps1` blocks missing/incomplete receipts. Fixtures and partial/final reports are kept below the actual run directory and uploaded by the existing Windows/Linux matrices. No local LLVM or VS Code checkout is required in CI. See [PERFORMANCES.md](../FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md) for comparisons, scenarios, seeds and bounds.
## ReadyToRun qualification

The Core case `ReadyToRun builds and loads the matching RID and CLR with portable fallbacks` checks all 64 build-target subsets, 1,152 CLR/RID routing properties, malformed manifests and PE input, and two routing mutants. When all six net10.0 targets were precompiled, it also prepares and validates one actual nupkg with all twelve R2R publications. These assertions do not imply that every platform executed locally.

GitHub matrix rows build Release ReadyToRun for their tested RID. The Windows x64 packaging runner builds all six RIDs for CLR 10 and 11 and requires them before compression. Probe-GalleryInstall.ps1 independently checks the installed module's actual runtime/build RID against its selected slots. GalleryPreview retains bounded installation diagnostics on failure. The separate manual A/B benchmark remains informational.
## Automation requirements as code

The automation-contract cases cover Docker/Podman discovery, standard ShouldProcess classification, 128 generated script contracts, malformed contracts, 14 real no-effect previews, five workflow documentation drift forms, missing/tampered parser resources, 40 malformed YAML variants and two targeted mutants. Workflow diagrams are generated from actual job needs and checked for exact correspondence. The dedicated commit bridge fixtures reject bad staged workflow receipts or unsafe staged scripts even when the working copy is repaired, and verify explicit skip reporting plus unchanged HEAD/index under WhatIf. The broader existing commit campaign retains its eleven targeted mutations and disposable repositories. These targeted development campaigns do not substitute for full release qualification.
# Focused .NET tooling validation

Run `../scripts/Invoke-DotNetTests.ps1` from this directory, or `./scripts/Invoke-DotNetTests.ps1` from the checkout root. The shared `DotNet` worker selects Readiness, Provisioning and Layout fixtures, bounded properties/fuzz inputs and targeted mutations without building or importing the product engine. Reports use the shared external temporary root and visible monitor. This focused Windows evidence is separate from Core/All release qualification. See [the user guide](../README-dotnet-and-global-dot-json.md).

Core product qualification requires only Core. The scaffolding case generates a scripted git-status companion and checks clean/untracked Unicode observations without the real Git module. Repository commit and source-check catalogues belong to private Tooling.Tests. The three full-distribution architecture, Gallery installation and packaged Recall checks belong to private Distribution.Tests and run once behind the tooling build barrier. Build-Workspace -Suite Core compiles only Core and its own tests; Test-CoreIndependence verifies a source copy with Git absent.
