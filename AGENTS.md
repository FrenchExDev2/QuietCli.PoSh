# QuietCli2 monorepo

Read `README.md`, then the selected module README. This root is one Git repository with four internal projects. Preserve the original modules outside this root.

- Interactive AI command analysis uses `quiet` from this checkout. Explicitly import the local Core manifest once per process, and the local Git manifest for Git commands. Use the `quiet` alias exported by the local Core V2 module for all native CLI calls. Existing matching binaries need no compilation; rebuild missing or stale binaries before use and start a fresh process. CI/build orchestration invokes tools directly through the engine-independent `scripts/Ci.Process.ps1` helper; it must not load the QuietCli engine or discover pump/quiet aliases to run tools. Product functional/import tests may load the product as their subject.
- The .NET 11 RC engine can run isolated or inside a .NET 11+ host. Never load its assembly into a .NET 10 PowerShell process.
- The engine also targets net10.0 under lib/inprocess. Auto hosting selects this verified build for CLR 10 and the portable net11.0 build under lib/engine for CLR 11+, including PowerShell Preview. QUIETCLI2_ENGINE_MODE=Process explicitly selects isolation; InProcess explicitly selects direct hosting. Both hosts share EngineSession. Never add a business-object serialization step to the direct read path.
- The Windows CI matrix requires stable/.NET 10 and preview/.NET 11 integrated hosting on x64 and ARM64, plus both isolated-host architecture checks. build/powershell-hosts.lock.json pins official ZIP hashes. Workers must use the selected PSHOME executable and verify actual host version, CLR, RID, engine target framework and PID. No preview or architecture failure may be treated as a skipped success.
- Never capture or spool native output automatically. Count bytes, dispatch bounded transient blocks and release them. Business handlers retain only their explicit business data.
- `-AsObject` must not enumerate or serialize business Data, even for metrics. It must not transfer Data to the engine. Unknown delivery sizes stay null.
- Keep source-reference names out of executable identifiers, comments and test code. Preserve attribution and original license text in notices/provenance.
- Business modules contain no tests. Put fixtures and assertions in their companion projects.
- Use the shared test launcher. Local runs require the visible PowerShell monitor, normal profile, UTF-8, stable framing and automatic closure after a saved terminal report. Headless mode is for CI.
- No commit, push, profile change or publication is implicit in a build or test.
- A command inventory is not semantic support. Missing or incomplete version/platform qualification must stay explicit and must never be marked successful by a skipped scenario.
- Document PowerShell scripts/functions and C# types, methods and parameters. Prefer async I/O.

## Monorepo projects and dependency-aware CI

- One public repository: `FrenchExDev2/FrenchExDev2.QuietCli.PoSh`. Keep the four existing directories as projects; do not recreate child repositories.
- `FrenchExDev2.QuietCli.Core.PoSh` owns the facade, engine, runtime catalogue and native bridges. `Core.Tests` owns its C#/PowerShell assertions. `Git` depends on Core. `Git.Tests` depends on Git and Core.Tests.
- `core-ci.yml` filters Core/Core.Tests and shared infrastructure paths, then calls `ci.yml` with `suite=All`: Core changes must also validate Git.
- `git-ci.yml` filters Git/Git.Tests and calls the same reusable workflow with `suite=Git`. A commit touching both groups may run both workflows; no applicable dependency check may be silently dropped to reduce that overlap.
- `ci.yml` is the shared manual/reusable implementation. It builds all six runtime publications, runs the selected companion suites and checks the actual host/guest RID.
- Linux runners build the multi-stage `.github/containers/Dockerfile.ci.*` natively: Ubuntu x64 for x64, `ubuntu-24.04-arm` for ARM64. No developer ARM machine, emulation or manually provisioned test image is required.
- `New-CiImage.ps1` fingerprints recipes, tool/source locks and image scripts. A first upstream main push/manual run publishes missing GHCR entries; changed inputs publish new entries. Existing entries are resolved and pulled by digest, checked against their source/fingerprint/architecture labels and reused. Never publish from a pull request. Missing private cache access in a fork falls back to a local build, not to an unverified image.
- Registry publication uses the workflow's ephemeral `GITHUB_TOKEN` with `packages: write`, stdin login and a private temporary auth file deleted on exit. Do not use PSGallery credentials for GHCR. Images contain only the test toolchain, never workspace sources, `.env`, tokens or native business output. Receipts live in `artifacts/ci-images`.
- `publish-psgallery.yml` is manually dispatched with an exact version. `publish=false` prepares/validates; `publish=true` publishes Core then Git to PSGallery after the full `All` matrix. No branch push, tag, build or test publishes.
- `repositories.lock.json` schema 3 records one repository and four project source hashes/dependency lists. Checkout the workflow commit once; no child clone is performed. Record the actual Git revision in run/build reports rather than trying to pin a file to its own future commit.
- From this root, use `scripts/Initialize-Workspace.ps1`, `scripts/Build-Workspace.ps1`, then `scripts/Invoke-WorkspaceCi.ps1 -SkipBuild -Suite All` (or `Git` for a Git-only development check). Local test runs retain the visible monitor requirement.
- Before an explicit commit, refresh `scripts/Update-WorkspaceLock.ps1`. `Commit-Workspace.ps1` and `Push-Workspace.ps1` now operate on the single root repository.
- PSGallery credentials belong only to the `psgallery` environment secret `PSGALLERY_API_KEY`. Never commit the workspace `.env`, print its token, pass it as a native command argument, or copy it into reports.
- The migration preserves the four former local Git directories under ignored `artifacts/monorepo-migration`. Do not delete that archive or restore nested Git metadata during routine builds.

## Native PTY mutation qualification

- The shared ci.yml workflow owns the independent pty-mutation matrix (Linux glibc/musl, x64/ARM64). Core/All and release qualification run it; Git-only development skips it.
- Invoke FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyMutation.ps1 locally with its visible monitor, or with -CompilerPath gcc -Headless in CI. The existing compiler is required; no installation is implicit.
- The unmodified 43-assertion baseline must pass before evaluating the 31 source-checked targeted mutations. Reject survivors, invalid mutants, timeouts and infrastructure errors. This catalogue does not establish exhaustive mutation coverage.
- Preserve artifacts/pty-mutation reports and distinguish killed, survived, invalid, timed-out and infrastructure-failed mutants. Upload reports even when the gate fails.

- The stable qualification-gate job waits for Windows, Linux and native mutation. Core/All requires all three to succeed; only Git-only development expects mutation to be skipped.
- The reusable workflow exposes qualified_sha only after that gate passes. Gallery publication explicitly requests All, requires a successful qualification result with qualified_sha equal to github.sha, and checks out that exact revision. No previous revision's success qualifies a new delivery.

- Run native C mutation through Invoke-ContainerCi.ps1 -Suite Mutation with ExpectedRuntimeIdentifier. Every Linux matrix target must succeed; image compilers are installed inside the CI images, never on the host. Windows uses the separate C# ConPTY implementation.

## CI bootstrap and mandatory native phases

- Native C compilation, unit/process properties, coverage-guided fuzzing and mutation precede the .NET build matrix. They need only source files, PowerShell, GCC/Clang (or Zig for the C bridge build) and native system libraries. No Core manifest, engine assembly or built test fixture is required.
- Native qualification requires 43 assertions including six generated property groups, 20,000 libFuzzer executions with ASan/UBSan, and 31 detected targeted mutants. Missing, skipped, failed, timed-out or incomplete phases block the matrix and publication. Assert-PtyQualification.ps1 enforces this independently of the product.
- Bootstrap.ps1 is only a compatibility entry point for Ci.Process.ps1. It defines no pump/quiet aliases, provider catalogues or analysis contracts.

- Native staging copies only C sources, C-only test drivers and C transport resources. It never requests compiled .NET build manifests. Probe-Independent.ps1 rejects product assemblies/manifests and traps accidental AI command calls; its independence receipt and the real guest exit code are required for CI success.

Native mutation containers have a 1 GiB cgroup memory limit. On musl the fuzzer requires that external limit before disabling its defective internal RSS-monitor thread; ASan, UBSan and LeakSanitizer remain enabled. The delivery guard requires at least 20,000 executed fuzz inputs, all process properties and all 31 targeted mutants. Runtime-leak reproducers are retained for the separate future libFuzzer patch.

<!-- test-strategy:begin -->
## Property testing, fuzzing and mutation testing

- Property-based testing, fuzzing and mutation testing are mandatory parts of the test strategy for every implementation language, including PowerShell, C#, C and future languages. Consider all three when writing or changing tests; ordinary example tests alone do not satisfy this strategy. Reuse and extend existing companion test projects, generators, corpora, mutation catalogues and runners.
- Define independent business properties and invariants, generate varied valid inputs, and fuzz malformed inputs, boundary values and relevant state/stream sequences. Use mutation testing to verify that assertions detect meaningful behavior changes; assertions must not merely duplicate the implementation. Keep each language's coverage and remaining gaps explicit.
- Execute the relevant campaigns when necessary: new or changed behavior, parsers or serializers, protocols or input validation, state/lifecycle/concurrency logic, a bug exposing a missing invariant, changes to assertions/generators/corpora/mutation tooling, or a dependency/runtime change affecting those guarantees. Run a deterministic regression for each discovered defect and retain its minimized reproducer or seed.
- Scope runs to the affected component and its dependent behavior. Do not rerun every campaign after every edit, read-only operation or documentation-only change. Reuse successful evidence only while its source, tests, dependencies, runtime and configuration remain applicable; explain the selected scope and why existing evidence is sufficient when no new campaign is needed.
- Before release/publication, execute the full required qualification matrix for the delivered revision. A targeted development run does not replace release qualification. Missing tooling or an unexecuted required campaign is an explicit qualification gap, never an implicit pass or an automatic waiver.
- Bound campaign duration and resources, retain seeds/corpora and source identity, and report property/fuzz executions and mutation outcomes separately. Investigate surviving mutants; distinguish equivalent mutants with evidence from missing assertions, invalid mutants, crashes, timeouts and infrastructure failures. Preserve failures and respect the repository's visible-monitor and artifact rules.
<!-- test-strategy:end -->

<!-- design-principles:begin -->
## SOLID, DRY and modular design

- Classes and modules must follow SOLID, DRY and MODULAR design principles in every implementation language. Apply these principles when creating, changing or reviewing code.
- Give each class/module a cohesive responsibility and a name describing that responsibility. Separate parsing, business policy, orchestration and infrastructure; keep dependencies explicit and interfaces focused. Depend on stable contracts, preserve substitutability and extend behavior without scattering command-specific branches across unrelated components.
- Reuse shared behavior through small composable components; avoid duplicated business rules, validation or protocol logic. Keep genuinely different semantics separate instead of forcing unrelated behavior into one abstraction.
- Preserve module boundaries and dependency direction. Do not introduce speculative frameworks, catch-all utility classes, unnecessary interfaces or extra IPC to satisfy a pattern mechanically. Test observable contracts and invariants independently of implementation details.
<!-- design-principles:end -->

<!-- commit-checkpoints:begin -->
## Commit checkpoints

- Create commits at validated, coherent checkpoints for each module or change. Account explicitly for every created, modified or deleted file in that change; do not accumulate unrelated completed work without committing it. One commit per file is not required.
- Commit from this monorepo root. Cross-module changes belong together when splitting them would break dependency contracts, builds or tests. Keep unrelated module changes separate and order shared foundations before their consumers.
- After completing and validating requested work, make its checkpoint commit without waiting for another reminder. Refresh the workspace lock before committing, review the exact staged paths and diff, and use a message describing the resulting behavior and relevant validation. Build/test execution alone does not authorize unrelated commits; never include secrets, generated artifacts or another task's unfinished work.
- Preserve completed work in commits before starting a new phase or any operation that could replace it. Never reset, clean or discard uncommitted workspace changes as part of a test. Mutating Git fixtures must be owned disposable repositories; non-repository tests must use an external temporary directory with parent-repository discovery explicitly blocked.
- Never create child repositories or independent module histories. A commit does not authorize pushing, tagging, publication or release.
<!-- commit-checkpoints:end -->

## Text encoding and line endings

All repository text files must use UTF-8 and LF line endings on disk, including generated JSON, native source, notices and lock files. Honor .gitattributes and .editorconfig. Preserve text content and attribution, retain original provenance digests when normalizing third-party evidence, and refresh every affected content lock. Never normalize binary resources or recorded native business evidence as text.
