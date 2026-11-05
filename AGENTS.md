# QuietCli2 monorepo

Read `README.md`, then the selected module README. This root is one Git repository with four internal projects. Preserve the original modules outside this root.

- Every native CLI operation goes through `pump` with an explicit documented contract. If profile autoload does not provide it, dot-source `scripts/Common.ps1` for the limited bootstrap; do not import archived OPumper modules.
- The .NET 11 RC engine is a separate process. Never load its assembly into a .NET 10 PowerShell process.
- Never capture or spool native output automatically. Count bytes, dispatch bounded transient blocks and release them. Business handlers retain only their explicit business data.
- `-AsObject` must not enumerate or serialize business Data, even for metrics. It must not transfer Data to the engine. Unknown delivery sizes stay null.
- Keep source-reference names out of executable identifiers, comments and test code. Preserve attribution and original license text in notices/provenance.
- Business modules contain no tests. Put fixtures and assertions in their companion repositories.
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
- `publish-psgallery.yml` is manually dispatched with an exact version. `publish=false` prepares/validates; `publish=true` publishes Core then Git to PSGallery after the full `All` matrix. No branch push, tag, build or test publishes.
- `repositories.lock.json` schema 3 records one repository and four project source hashes/dependency lists. Checkout the workflow commit once; no child clone is performed. Record the actual Git revision in run/build reports rather than trying to pin a file to its own future commit.
- From this root, use `scripts/Initialize-Workspace.ps1`, `scripts/Build-Workspace.ps1`, then `scripts/Invoke-WorkspaceCi.ps1 -SkipBuild -Suite All` (or `Git` for a Git-only development check). Local test runs retain the visible monitor requirement.
- Before an explicit commit, refresh `scripts/Update-WorkspaceLock.ps1`. `Commit-Workspace.ps1` and `Push-Workspace.ps1` now operate on the single root repository.
- PSGallery credentials belong only to the `psgallery` environment secret `PSGALLERY_API_KEY`. Never commit the workspace `.env`, print its token, pass it as a native command argument, or copy it into reports.
- The migration preserves the four former local Git directories under ignored `artifacts/monorepo-migration`. Do not delete that archive or restore nested Git metadata during routine builds.
