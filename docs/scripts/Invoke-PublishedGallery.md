# Invoke-PublishedGallery.ps1

With `-Headless`, CI starts no desktop monitor and prints no `Watch-Tests.ps1` reopen command.
The package-validation worker remains isolated and supervised with its saved reports and timeout.
Local runs keep their visible monitor and its reopen instruction.

## Purpose

Validates that an already-published version of the Core PowerShell module actually installs and works from a public gallery feed (PSGallery), without touching the user's own locally-installed modules. It solves the "it builds locally but is the published package actually usable" problem — the gap between "the repo's source works" and "what a real consumer who runs `Install-Module` gets" is otherwise unverified. It launches a worker script (`FrenchExDev2.QuietCli.Core.Tests.PoSh/audit/Probe-PublishedGallery.ps1`) in an isolated background process and a visible monitor window per the repository's mandatory test-monitoring convention, then waits for and reports the result. This is a release-verification step, likely run after a `publish-psgallery` workflow (an actual workflow of that name exists at `.github/workflows/publish-psgallery.yml`), though no `.ps1`/`.yml` caller of this exact script was found in the scripts folder itself — it appears to be a manually or externally triggered post-publish check rather than something the main workspace CI pipeline invokes automatically.

## Usage

Parameters:
- `WorkspaceRoot` (`string`, optional, default: parent of `$PSScriptRoot`) — QuietCli2 monorepo root.
- `Version` (`string`, **mandatory**, validated against `^\d+\.\d+\.\d+(?:-[A-Za-z][A-Za-z0-9-]*)?$`) — exact published version to validate.
- `Headless` (`switch`, optional) — reserved for CI without a desktop; on non-Windows without `-Headless`, the script throws.

Example:
```powershell
./scripts/Invoke-PublishedGallery.ps1 -Version 2.45.0
```

## Dependencies

- Dot-sources `Common.ps1` (line 14) for `Get-QuietReportRoot`, `ConvertTo-CiArgument`, and `Wait-WorkspaceWorker`.
- Shells out to `pwsh` (resolved via `Get-Command pwsh -CommandType Application`, line 17) to launch the worker and, when not headless, the monitor window (`Watch-Tests.ps1`, line 23–24).
- Depends on `FrenchExDev2.QuietCli.Core.Tests.PoSh/audit/Probe-PublishedGallery.ps1` existing and accepting `-WorkspaceRoot`, `-RunDirectory`, `-Version`.
- Filesystem: creates a new run directory under `Get-QuietReportRoot $WorkspaceRoot 'gallery-validation'`.
- Implicit network dependency: the worker script presumably reaches out to the real PSGallery (not verified in this script itself, but implied by "validates the published public Core package").

## Side effects

- Creates a new timestamped+GUID-suffixed run directory (line 15–16) and writes `worker.stdout.log`/`worker.stderr.log` into it via `Start-Process` redirection (line 20).
- Starts two OS processes: a hidden worker (`Hidden` window style on Windows, line 21) and, unless `-Headless`, a normal-visible monitor window (line 24) — satisfying the AGENTS.md requirement that test runs get a dedicated visible monitoring window.
- Prints a "Monitor: pwsh -File ..." line to stdout (line 25) so the user can reopen the monitor manually.
- Throws and leaves the run directory behind (with logs) if the gallery validation fails (line 28) — this is intentional, to keep failure evidence.

## Findings

- DESIGN: On line 21, `if($IsWindows){...}elseif(!$Headless){throw...}` — on Linux/macOS, `-Headless` is required or the script throws immediately, but there is no `else` branch handling the case where `$IsWindows` is true and `$Headless` is also requested; that's fine functionally (Windows just always gets `WindowStyle='Hidden'` for the worker regardless of `-Headless`), but the asymmetry (headless is only meaningful for whether the *monitor* opens, not the worker's window style) is not documented in the `.PARAMETER Headless` comment, which only says "Reserved for CI without a desktop" — a reader cannot tell from the docstring that `-Headless` only suppresses the monitor, not anything about the worker itself.
- CONVENTION: No explicit UTF-8 encoding is set for the redirected `worker.stdout.log`/`worker.stderr.log` files (line 20); `Start-Process -RedirectStandardOutput` uses the console's default encoding, which may not match the repository-wide UTF-8-everywhere rule. Compare with `Common.ps1`'s `Invoke-WorkspaceNative`, which explicitly constructs a `[Text.UTF8Encoding]::new($false)` writer for its own log file.
- Testability: No Pester test exercising this script directly was found. Its logic is mostly orchestration (process launch + wait), so the testable unit is really `Wait-WorkspaceWorker` in `Common.ps1`, which also has no dedicated test file found under `FrenchExDev2.QuietCli.Core.Tests.PoSh`.
- No input validation beyond the `Version` regex; `WorkspaceRoot` is not checked for existence before being passed to `Get-QuietReportRoot`/the worker — a typo'd path would fail downstream with a less specific error rather than failing fast here.
- Genuine scrutiny found no mutation-testing/fuzzing gap beyond the general absence of tests, and no security issue: the `Version` parameter is strictly pattern-validated before being interpolated into any path or argument, and `ConvertTo-CiArgument` is used consistently for process arguments.

## Verdict

Fit for purpose as an orchestration wrapper around a real worker/monitor pair, following the repository's visible-monitor convention correctly; the main gap is the complete absence of any direct or indirect test coverage for this exact script and the unenforced UTF-8 policy on its log redirection. Highest-priority fix: add explicit UTF-8 encoding to the redirected log files, matching the rest of the codebase's I/O discipline.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-library-boundary:begin -->
## Automation library boundary

This entry point contains no function definitions. Automation helpers are imported from `scripts/lib` with `-DisableNameChecking`; path composition uses `System.IO.Path`. Public parameters and the documented operation remain unchanged.

Direct library contracts: [Common.psm1](lib/Common.md).

See [the library index](README.md) and [RAC-PS-003 / RAC-PS-004](../README-automation-contracts.md) for dependency, preview and source-layout obligations.
<!-- script-library-boundary:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Validates the published public Core package without changing the user's installed modules.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
