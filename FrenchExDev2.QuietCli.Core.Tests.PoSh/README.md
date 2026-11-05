<p align="center">
  <img src="./../icons/logo.png" alt="Requirement-As-Code logo" width="150px" />
</p>

# FrenchExDev2.QuietCli.Core.Tests.PoSh

Module de tests indépendant du moteur. Dépend du module Core, jamais l’inverse.

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

`SecondPass.Tests.ps1` verifies gain group paging and report cleanup, then compares the former PowerShell aggregation with C# in both engine modes. It also measures short-record and long-fragment framing with independent expected counts. `Gain.Baseline.ps1` is test-only. Timing scope, request counts and actual pipe bytes are retained in `Suites[].Performance`; see [the migration review](../docs/powershell-csharp-boundaries.md).

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

The shared ci.yml workflow runs this campaign in the independent pty-mutation matrix (Debian/glibc and Alpine/musl, x64 and ARM64 on native Ubuntu runners) for Core/All, including release qualification. Git-only development skips it. An unmodified baseline must pass all 43 assertions before 31 explicit single-site mutations are evaluated. The score covers this catalogue only; no exhaustive operator or line coverage is claimed. Survivors, compile failures, timeouts, infrastructure failures and stale mutation anchors fail the job; only assertion failures or fixture crashes count as killed mutants. Invalid and timed-out mutants remain separate from the score denominator.

Artifacts under artifacts/pty-mutation/ retain the catalogue, source/test SHA-256, compiler identity, mutated sources, compiler diagnostics, bounded test diagnostics, per-mutant outcomes, ELF checks and final summary. The workflow uploads them even after a failure. CI validates the checkout; no remote workflow is dispatched by the local launcher.

The four mutation jobs reuse Invoke-ContainerCi.ps1 -Suite Mutation and the content-addressed native CI images. GCC and libc development headers are part of those images. ExpectedRuntimeIdentifier rejects the wrong guest before compilation. Windows x64/ARM64 validates the separate C# ConPTY implementation; this POSIX C bridge is tested on its four Linux targets.

### Properties and coverage-guided fuzzing

The baseline includes six property groups: every allowed dimension with leading zeros, 25,000 generated dimension strings, 25,000 generated control inputs plus boundaries, 256 fragmented real-PTY requests, all five truncated-frame disconnects with owned-child reaping, and 32 generated descriptor sets above a lowered limit. Seed 633419 and failing input files are retained. Signal/group invariants also have the existing exhaustive pre/post-session assertions.

Every native CI job supplies -RequireFuzz. The original source is exercised by Clang/libFuzzer for 20,000 executions with AddressSanitizer and UndefinedBehaviorSanitizer, seed 633419 and a 4096-byte input limit. The target covers pure dimension and resize decoding; process creation and descriptor behavior remain in mandatory isolated property tests. Compiler identity, corpus, execution count, bounded diagnostics and crash reproducers are saved. Use -FuzzRuns for a larger manual budget.

A prepared native image can set QUIETCLI_PTY_LLVM_RESOURCE_DIR to runtimes built from a local LLVM checkout. The directory must contain build.json with a successful build, exact source revision, matching guest RID and SHA-256 entries for libFuzzer, ASan, ASan C++, ASan static and standalone UBSan archives. Missing or mismatched artifacts fail before compilation. The fuzz report records the source revision and verified archives separately from the bootstrap compiler version. This explicit image mode does not change the default workflow images or require the QuietCli product to be built.

Assert-PtyQualification.ps1 requires all phases; separate harnesses are never optional in CI. The standalone Windows/Zig mutation launcher does not request libFuzzer; use Invoke-ContainerCi.ps1 -Suite Mutation with a prepared native image for full qualification. GCC, Clang and sanitizer runtimes are installed only in the test images.

### No product bootstrap dependency

Build/test scripts use Ci.Process.ps1, an ordinary PowerShell/System.Diagnostics tool runner. They neither call pump/quiet nor import Core. C source and its test headers can therefore be compiled and qualified before the .NET engine exists. The workflow runs the four native qualification jobs first, then builds/tests Core and Git, then checks the revision-bound publication gate.

Native staging is deliberately source-only: no Core/Git module manifest, .NET project, engine assembly or built fixture is copied. Probe-Independent.ps1 rejects such files and shadows pump/quiet with failing traps. CI requires its zero-product/zero-AI-call receipt and confirms the actual container exit code before trusting any success report. The native matrix must finish before either Windows or Linux .NET builds start.

On musl, the LLVM 22.1.3 RSS-monitor allocation was observed leaking 56 bytes at shutdown. The paired reproducer keeps the same binary, execution budget and cgroup limit; only rss_limit_mb changes. CI uses the container's 1 GiB memory limit instead of that monitor on musl, and fails if the cgroup bound is missing. ASan, UBSan and LeakSanitizer remain enabled (-detect_leaks=1); there is no leak suppression. Allocation size is additionally limited to 512 MiB. This is a tool-runtime workaround, not a claim of an upstream fix.

The byte-write regressions inject zero progress, permanent errors, short writes and repeated EINTR without changing production code. A fixed set of 1,000 binary-payload schedules checks exact byte preservation. Three corresponding single-site mutants must be detected. Together with the process and stream regressions, qualification requires 43 assertions and 31 mutants.

The four stream regressions use an independent raw-terminal producer and compare a 1 MiB + 137 byte binary payload incrementally. They verify exact delivery to a slow consumer, resize acknowledgements while output is backpressured, killing/reaping after the output consumer disconnects even when the command ignores SIGHUP, and signal exit status with an intact output prefix. Synchronization uses pipe writability rather than assuming that queued bytes equal nominal pipe capacity. Fixture deadlines bound hangs and cleanup kills the owned command before waiting for the bridge. These assertions qualify correctness under backpressure; they are not a throughput benchmark.

On glibc x64 with Clang 14, the standalone fuzz executable is explicitly linked non-PIE to avoid reproduced ASan startup crashes under high-entropy address randomization. A controlled 32-start comparison also reproduced crashes in an empty ASan PIE program, while the empty non-PIE control passed every start. The layout is checked in the compiled ELF and recorded in the fuzz report. ASan, UBSan and LeakSanitizer remain enabled; no automatic retry or sanitizer suppression is used. This affects no shipped transport binary: all four bridges still require static PIE, RELRO, immediate binding and a non-executable stack. See [LLVM issue 81470](https://github.com/llvm/llvm-project/issues/81470) for the related runtime symptom.
