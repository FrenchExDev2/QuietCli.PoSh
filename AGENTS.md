# QuietCli2 monorepo

## Script-first automation

- Any automatable operation on this repository is done through a script under `scripts/` (discover what already exists with `Get-ChildItem scripts -Recurse`, or browse the [scripts documentation index](docs/scripts/README.md)), never an ad hoc inline command improvised for one occasion. Extend an existing script before writing a new one that overlaps it.
- At the start of every discussion that touches this repository, actively look for the opportunity to turn a manual or ad hoc sequence into a new or extended script under `scripts/`. A one-off command typed into a shell is a missed script, not a shortcut. A new or changed script must ship with its own doc under `docs/scripts/`, mirroring its subdirectory - see [Every script has a doc](docs/README-scripts-have-docs.md); the gate is `scripts/Sync-ScriptsReadme.ps1`.

## Production documentation

- The public PowerShell module and Gallery package are named `QuietCli`; they provide Core. `FrenchExDev2.QuietCli.Core.PoSh` is the internal source project name, never a public package identity. Use `Install-PSResource -Name QuietCli` and `Import-Module QuietCli` in consumer instructions; retain explicit local manifest paths only for source development. Public packaging must use the `QuietCli` identity.
- Keep documentation up to date whenever a change affects documented behavior, public commands, configuration, installation, workflows or qualification scope. Update the affected READMEs, guides, contracts and examples in the same change, and maintain the [documentation index](docs/README.md) when documents are added, renamed or removed. Preserve dated audits as historical evidence; record new results separately rather than rewriting their original scope or outcomes.
- User-facing documentation describes the product as installed and used in production, not the development checkout or an editorial history of local changes.
- Do not add unreleased-version annotations or rewrite documentation around development work unless explicitly requested as part of an upward version change. Consumer guides link to the distributed production instructions and use the public installation and instruction-generation commands; this root AGENTS.md governs repository development only.

Read `README.md`, then the selected module README. This root is one Git repository with six internal projects (Core, Git, Vagrant and their test companions). Preserve the original modules outside this root.

- Interactive AI command analysis uses `quiet` from this checkout. Explicitly import the local Core manifest once per process, and the local Git manifest for Git commands. Use the `quiet` alias exported by the local Core V2 module for all native CLI calls. Existing matching binaries need no compilation; rebuild missing or stale binaries before use and start a fresh process. CI/build orchestration invokes tools directly through the engine-independent `scripts/Ci.Process.ps1` helper; it must not load the QuietCli engine or discover pump/quiet aliases to run tools. Product functional/import tests may load the product as their subject.
- The .NET 11 RC engine can run isolated or inside a .NET 11+ host. Never load its assembly into a .NET 10 PowerShell process.
- The engine also targets net10.0 under lib/inprocess. Auto hosting selects this verified build for CLR 10 and the portable net11.0 build under lib/engine for CLR 11+, including PowerShell Preview. YAML engine.hosting=Process explicitly selects isolation; InProcess explicitly selects direct hosting. Both hosts share EngineSession. Never add a business-object serialization step to the direct read path.
- The Windows CI matrix requires stable/.NET 10 and preview/.NET 11 integrated hosting on x64 and ARM64, plus both isolated-host architecture checks. build/powershell-hosts.lock.json pins official ZIP hashes. Workers must use the selected PSHOME executable and verify actual host version, CLR, RID, engine target framework and PID. No preview or architecture failure may be treated as a skipped success.
- Never capture or spool native output automatically. Count bytes, dispatch bounded transient blocks and release them. Business handlers retain only their explicit business data.
- Explicit `-Recall -AsObject` and `-SaveRecall -AsObject` are the opt-in exceptions: retain bounded caller-local evidence or a durable streaming journal, never in SQLite or ordinary deliveries. Offline identity-based replay and optional ZIP64 transport follow [the Recall contract](docs/README-recall.md). Core includes Recall regressions; `-Suite Recall` and `-Suite RecallMutation` provide focused monitored development runs, not release qualification.
- `-AsObject` must not enumerate or serialize business Data, even for metrics. It must not transfer Data to the engine. Unknown delivery sizes stay null.
- Keep source-reference names out of executable identifiers, comments and test code. Preserve attribution and original license text in notices/provenance.
- Business modules contain no tests. Put fixtures and assertions in their companion projects.
- Use the shared test launcher. Local runs require the visible PowerShell monitor, normal profile, UTF-8, stable framing and automatic closure after a saved terminal report. Headless mode is for CI.
- No commit, push, profile change or publication is implicit in a build or test.
- A command inventory is not semantic support. Missing or incomplete version/platform qualification must stay explicit and must never be marked successful by a skipped scenario.
- Document PowerShell scripts/functions and C# types, methods and parameters. Prefer async I/O.

## Monorepo projects and dependency-aware CI

- One public repository: `FrenchExDev2/FrenchExDev2.QuietCli.PoSh`. Keep the six existing directories as projects; do not recreate child repositories.
- `FrenchExDev2.QuietCli.Core.PoSh` owns the facade, engine, runtime catalogue and native bridges. `Core.Tests` owns its C#/PowerShell assertions. `Git` depends on Core. `Git.Tests` depends on Git and Core.Tests.
- `Vagrant` is a pure PowerShell consumer of Core; `Vagrant.Tests` depends on Vagrant and Core.Tests. `-Suite Vagrant` runs fixtures without installing Vagrant. `All` includes all three companions, including release validation through the existing shared workflow.
- `scripts/WorkspaceProjects.ps1` discovers project manifests and their dependency order. The host/container launchers build `Suite` validation/completion dynamically from declared test companions. `All` is an execution mode, never a module. `Get-QuietWorkspacePackages` separates explicit public-package eligibility from local source/test archives: tests are always excluded, and undeclared business modules default to non-publishable. See [the catalogue contract](docs/README-workspace-projects.md).
- `core-ci.yml` filters Core/Core.Tests and shared infrastructure paths, then calls `ci.yml` with `suite=Core`: a Core-only change validates Core alone and does not run the Git suite or its mutation campaigns.
- `git-ci.yml` filters Git/Git.Tests and calls the same reusable workflow with `suite=Git`. A commit touching both groups may run both workflows; no applicable dependency check may be silently dropped to reduce that overlap.
- Release qualification stays the exception: `publish-psgallery.yml` always requests `suite=All`, so Git is still validated against Core before any publication even though routine Core development no longer triggers it.
- `ci.yml` is the shared manual/reusable implementation. It builds all six runtime publications, runs the selected companion suites and checks the actual host/guest RID.
- Linux runners build the multi-stage `.github/containers/Dockerfile.ci.*` natively: Ubuntu x64 for x64, `ubuntu-24.04-arm` for ARM64. No developer ARM machine, emulation or manually provisioned test image is required.
- `New-CiImage.ps1` fingerprints recipes, tool/source locks and image scripts. A first upstream main push/manual run publishes missing GHCR entries; changed inputs publish new entries. Existing entries are resolved and pulled by digest, checked against their source/fingerprint/architecture labels and reused. Never publish from a pull request. Missing private cache access in a fork falls back to a local build, not to an unverified image.
- Registry publication uses the workflow's ephemeral `GITHUB_TOKEN` with `packages: write`, stdin login and a private temporary auth file deleted on exit. Do not use PSGallery credentials for GHCR. Images contain only the test toolchain, never workspace sources, `.env`, tokens or native business output. Receipts live in `artifacts/ci-images`.
- `publish-psgallery.yml` is the shared qualified packaging/publication workflow. Manual releases supply an exact version; `publish=false` prepares/validates artifacts only. The explicitly authorized `preview-psgallery.yml` wrapper publishes previews automatically for applicable pushes to the original repository's `develop` branch, only after the configured `All` qualification gate (TTY excluded in GitHub CI). PRs and forks never publish. Only Core is published; Git remains an internal development/test companion. Stable releases remain manual; builds and tests themselves never publish.
- Preview identities keep the source numeric version and GUIDs, with a staged `preview{run-number:D8}a{attempt:D4}` suffix. Do not bump a minor version for a new build, use dot-separated prerelease labels, edit source manifests in CI, or overwrite a published identity. Artifact preparation has no Gallery secret; publication downloads and verifies the exact prepared files. Superseded automatic preview revisions are skipped before publication.
- `repositories.lock.json` schema 3 records one repository and six project source hashes/dependency lists. Checkout the workflow commit once; no child clone is performed. Record the actual Git revision in run/build reports rather than trying to pin a file to its own future commit.
- From this root, use `scripts/Initialize-Workspace.ps1`, `scripts/Build-Workspace.ps1`, then `scripts/Invoke-WorkspaceCi.ps1 -SkipBuild -Suite All` (or `Git` for a Git-only development check). Local test runs retain the visible monitor requirement.
- Before an explicit commit, refresh `scripts/Update-WorkspaceLock.ps1`. `Commit-Workspace.ps1` and `Push-Workspace.ps1` now operate on the single root repository.
- `Commit-Workspace.ps1` adds no `Co-Authored-By` trailer by default; pass `-CoAuthoredBy` (one or more of `Claude`, `Codex`, or a literal `Name <email>`) only when the agent that produced the change should be credited in that specific commit. Known names resolve to: `Claude` -> `Claude Sonnet 5 <noreply@anthropic.com>`, `Codex` -> `Codex <noreply@openai.com>`.
- PSGallery credentials belong only to the `psgallery` environment secret `PSGALLERY_API_KEY`. Never commit the workspace `.env`, print its token, pass it as a native command argument, or copy it into reports.
- The migration preserves the four former local Git directories under ignored `artifacts/monorepo-migration`. Do not delete that archive or restore nested Git metadata during routine builds.

<!-- module-license-credits:begin -->
- Each business module (`Core`, `Git`, `Vagrant` — never a `.Tests` companion) must ship its own `LICENSE_CREDITS.md`, declaring the third-party license(s) its native dependency uses, with reference links. This is part of the module contract alongside its manifest and declared test companion.
- The root [`CREDITS.md`](CREDITS.md) is generated, never hand-edited: `scripts/Sync-Credits.ps1` discovers every business module through `Get-QuietWorkspaceProjects` and aggregates its `LICENSE_CREDITS.md` into the root file, each wrapped in its own `<!-- module-credits:<Name>:begin/end -->` marker. No arguments reports compliance without writing; `-Apply` regenerates `CREDITS.md`; `-Apply -WhatIf` previews that write without touching any file.
- A new business module is not complete until it ships `LICENSE_CREDITS.md` and `scripts/Sync-Credits.ps1 -Apply` has regenerated the root file. Run `scripts/Sync-DocsCredits.ps1 -Apply` afterward only if `CREDITS.md`'s own relative path changed.
<!-- module-license-credits:end -->

## NuGet dependency map (Central Package Management)

- `Directory.Packages.props` at this root centralizes NuGet versions for the whole sub-tree (`Core`, `Core.Tests`, `Git`); no `.csproj` under this root pins its own `Version=` on a `<PackageReference>` any more.
- `System.Management.Automation` (`7.6.9`) — the PowerShell host assembly. Compile-only (`PrivateAssets="all" ExcludeAssets="runtime"`) on `Core/engine` and `Git/engine`, since the host process already supplies it at runtime; loaded normally (no those attributes) in `Core.Tests/engine-tests`, which must actually run against it.
- `Spectre.Console` (`0.57.2`) — renders the `-UI`/`-MaxLines` live frame (`QuietUiRenderer`, `Core/engine/Cmdlets/UiRenderer.cs`). Referenced normally (copied to the module's output) on `Core/engine` only — nothing else supplies this assembly.
- Before bumping either version, run `dotnet list package --outdated` from this root (the authoritative source — not a web search) and never downgrade a pinned version on the strength of a possibly stale web result.

## Native PTY mutation qualification

- GitHub workflows exclude native TTY/PTY execution and the standalone properties, fuzzing and mutation matrix to limit duration. Pass `-SkipTty` through Windows, container and packaging test launchers. Record TTY as excluded, never successful. Local defaults and standalone campaign scripts remain available.
- Invoke FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Invoke-PtyMutation.ps1 locally with its visible monitor, or with -CompilerPath gcc -Headless in CI. The existing compiler is required; no installation is implicit.
- The unmodified 43-assertion baseline must pass before evaluating the 31 source-checked targeted mutations. Reject survivors, invalid mutants, timeouts and infrastructure errors. This catalogue does not establish exhaustive mutation coverage.
- Preserve artifacts/pty-mutation reports and distinguish killed, survived, invalid, timed-out and infrastructure-failed mutants. Upload reports even when the gate fails.

- The GitHub qualification gate waits for Windows, Linux and performance evidence. Its explicit `-SkipTty` scope expects native mutation to be skipped and records the exclusion. The local default gate still requires native mutation for Core/All.
- The reusable workflow exposes qualified_sha only after that gate passes. Gallery publication explicitly requests All, requires a successful qualification result with qualified_sha equal to github.sha, and checks out that exact revision. No previous revision's success qualifies a new delivery.

- Run native C mutation through Invoke-ContainerCi.ps1 -Suite Mutation with ExpectedRuntimeIdentifier. Every Linux matrix target must succeed; image compilers are installed inside the CI images, never on the host. Windows uses the separate C# ConPTY implementation.

## CI bootstrap and mandatory native phases

- Local native C qualification includes compilation, unit/process properties, coverage-guided fuzzing and mutation. GitHub CI does not run these TTY campaigns. They need only source files, PowerShell, GCC/Clang (or Zig for the C bridge build) and native system libraries. No Core manifest, engine assembly or built test fixture is required.
- Full local native qualification requires 43 assertions including six generated property groups, 20,000 libFuzzer executions with ASan/UBSan, and 31 detected targeted mutants. Missing, skipped, failed, timed-out or incomplete phases block full native qualification. They are outside the explicitly reduced GitHub CI scope. Assert-PtyQualification.ps1 enforces this independently of the product.
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

<!-- local-test-reports:begin -->
## Local test reports

- Store local test progress, summaries, logs and mutation reports outside the checkout, under `%TEMP%\QuietCli2\<workspace-id>\<category>\<run-id>` on Windows (the system temporary directory on other platforms). Resolve the path with `scripts/ReportPaths.ps1` / `Get-QuietReportRoot`; do not hard-code a user name or recreate local report directories under `artifacts/`.
- For this checkout, the resolved root is `C:\Users\serard\AppData\Local\Temp\QuietCli2\874a99c9b658`. Companion reports are under `tests`; container, Gallery-validation and mutation reports use separate categories. Launchers print the exact run path and monitor reopening command.
- Preserve explicit `-RunDirectory` overrides. CI retains repository `artifacts/` paths for its upload contracts. Do not move an active run. Keep toolchains, package outputs and the protected monorepo-migration archive separate from test reports.
- Temporary storage may be cleared by the operating system. Export evidence requiring durable retention before cleanup; never silently delete failure diagnostics, seeds or mutation results.
<!-- local-test-reports:end -->

## Test selection and fail-fast

- The unfiltered, full-suite run (all failures listed) remains the pre-commit gate. Never commit on the basis of a filtered or stopped run.
- `Invoke-WorkspaceCi.ps1 -StopOnFirstFailure` is an opt-in development switch: the monitor stops at the first failing case so it can be fixed immediately. The report states "stopped at case N of M" and is flagged incomplete.
- `Invoke-WorkspaceCi.ps1 -Case <wildcard>` runs only the matching cases. The report is flagged partial. The two options can be combined.
- Both options act on the Core suite's cases (the worker exposes them to the case loop as `QUIETCLI_TEST_CASE` / `QUIETCLI_TEST_STOP_ON_FIRST_FAILURE`). The summary carries `Partial`, `Incomplete`, `StoppedAt` and `Skipped`, and the full-run integration evidence assertion is skipped for such runs.
- The C# test executable accepts `--case <wildcard>` and `--stop-on-first-failure` for direct runs (for example `dotnet QuietCli.Engine.Tests.dll <nativeDir> --case "*framer*"`); its JSON summary reports the same fields. Incomplete and partial runs never count as qualification evidence.

## Mandatory Core performance evidence

- Core/All runs fresh-session import measurements, ten diagnostic controls and eight owned Core-only porcelain-v2 Git fixture states. `Invoke-WorkspaceCi.ps1 -Suite Integration -SkipBuild -Profiler` selects the focused development scope. No Git business companion is loaded by these subjects.
- Shared ci.yml prepares checksum-pinned Profiler 4.3.0 and dotnet-trace 10.0.750501 in a private runner cache. Linux stages them into the networkless guest. PS line data and CLR traces are collected separately from ordinary benchmark samples; isolated hosting requires both owned target PIDs.
- Each matrix job builds an integrity-checked evidence bundle and PERFORMANCES_RESULTS.md, then uploads it with `if: always()`. The performance-results job verifies/downloads all ten Windows/Linux bundles and publishes a combined readable report plus JSON/checksum metadata. The qualification gate also requires this job.
- Missing jobs, failed functional checks, absent profiles and modified trace files are explicit evidence gaps. Frame-name counts are not CPU percentages. Preserve raw/converted traces, source identities, seeds, partial failures and tool receipts in the CI artifacts. See FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md for definitions and measured scope.

## Configuration and delivery validation

- `QUIETCLI_CONFIG_DIRECTORY` is the only product configuration environment override. Other `QUIETCLI_*` test-worker controls do not configure the product. Do not restore old database, hosting or tracking environment overrides.
- The lazy YAML snapshot, configuration cmdlets, unique representation receipts and per-encoding token measurements follow [the configuration contract](docs/README-configuration.md). No automatic native tokenization or Recall capture is implied.
- `scripts/Invoke-WorkspaceCi.ps1 -Suite ConfigurationDelivery -SkipBuild` runs the focused properties, malformed YAML corpus, historical SQLite fixtures and targeted PowerShell/C# mutations with the shared visible monitor. Core/All also includes its functional baseline. Preserve the full release matrix requirements.

## Run-profile tooling qualification

- Use `scripts/Invoke-WorkspaceCi.ps1 -Suite RunProfiles -SkipBuild -TimeoutSeconds 600` for the complete tooling suite, and `-Suite RunProfilesMutation -TimeoutSeconds 3300` for the entire targeted catalogue. Both retain the shared visible monitor and external report directories.
- CI runs both suites on Windows x64 stable integrated hosting for Core/All. A skipped required functional case or any surviving, crashed, invalid or timed-out mutant blocks that Windows job and qualification. Git-only development does not run tooling campaigns.
- Benchmark properties and malformed samples, native-boundary fixtures, profiler/cache unit cases and actual-process smoke tests are distinct evidence. Never present three A/A smoke pairs as false-positive calibration or a ReadyToRun speedup.

## SDK readiness

@AGENTS-SDK-READINESS.md

<!-- docs-credits:begin -->
## Mandatory CREDITS.md linkage

- Every `docs/**/*.md` file (recursively, including `agents`, `audits` and `ci`) and every root `README.md`/`README-*.md` file must end with a dedicated paragraph linking the mandatory [`CREDITS.md`](CREDITS.md). `CREDITS.md` itself is mandatory and generated (see "Each business module" below) from every discovered module's `LICENSE_CREDITS.md`; do not hand-edit it directly.
- The paragraph is a regex-identifiable block surrounded by `<!-- credits:begin -->` / `<!-- credits:end -->` markers, matching this section's own `<!-- docs-credits:begin/end -->` convention. Never hand-edit a block out of sync with its generator.
- Use [`scripts/Sync-DocsCredits.ps1`](scripts/Sync-DocsCredits.ps1) to check and apply it: no arguments reports compliance (recursively) without writing; `-Apply` writes the missing or stale block into every non-compliant `docs/**/*.md` or root `README*.md` file; `-Apply -WhatIf` previews that write without touching any file; `-NoRecurse` limits either mode to `docs/*.md`'s direct children. A new or renamed `docs/**/*.md` or root `README*.md` file must pass `-Apply` before being committed. The companion GitHub workflows [`sync-credits-check.yml`](.github/workflows/sync-credits-check.yml) and [`sync-credits-apply.yml`](.github/workflows/sync-credits-apply.yml) run this and `Sync-Credits.ps1`; see [docs/README-credits-and-syncing.md](docs/README-credits-and-syncing.md).
<!-- docs-credits:end -->

<!-- scripts-have-docs:begin -->
## Every script has a doc

- Every file under `scripts/` (`*.ps1`, `*.psm1`, recursively, including `lib/` and `RunProfiles/`) must have a matching Markdown doc under `docs/scripts/`, mirroring its subdirectory: `scripts/lib/Foo.psm1` is documented at `docs/scripts/lib/Foo.md`, `scripts/RunProfiles/bar.profile.ps1` at `docs/scripts/RunProfiles/bar.profile.md`, a root `scripts/Baz.ps1` at `docs/scripts/Baz.md`. When you add, rename, move or materially change a script's behavior (parameters, side effects, dependencies, known gaps), update its doc in the same change: purpose, usage, dependencies, side effects, a critical findings review (bugs, convention violations against this file, design smells, missing validation, test-coverage gaps — with file:line references) and a verdict.
- Find a script's existing doc, or confirm one is missing, from the generated index [`docs/scripts/README.md`](docs/scripts/README.md) — it links every script to its doc, grouped by subdirectory. Never guess a doc's path by filename alone; the index is the source of truth for what already exists and what still needs writing.
- Use [`scripts/Sync-ScriptsReadme.ps1`](scripts/Sync-ScriptsReadme.ps1) to check and apply the index: no arguments reports compliance and throws `ScriptsDocsMissing` the moment any script has no doc, or `ScriptsReadmeNonCompliant` if the index is stale — this is the gate, and it never writes. `-Apply` regenerates `docs/scripts/README.md` once every script is documented; `-Apply -WhatIf` previews that write without touching any file. `-Apply` cannot resolve a missing doc, only the index's own staleness. The companion GitHub workflows [`scripts-docs-check.yml`](.github/workflows/scripts-docs-check.yml) and [`scripts-docs-apply.yml`](.github/workflows/scripts-docs-apply.yml) run this; see [docs/README-scripts-have-docs.md](docs/README-scripts-have-docs.md).
<!-- scripts-have-docs:end -->

## Gallery preview qualification

- Use `scripts/Invoke-WorkspaceCi.ps1 -Suite GalleryPreview -SkipBuild` for version examples/properties, malformed counters, staged-manifest checks, real offline nupkg preparation and installation, publication-boundary fixtures and targeted version mutations. Core/All includes the functional baseline.
- Publication fixtures use aliases and a non-secret placeholder; never substitute a real Gallery key or send a real publication as a test. The `psgallery` environment must allow `develop` for automatic previews; any configured approval protection still applies and is never disabled implicitly.
