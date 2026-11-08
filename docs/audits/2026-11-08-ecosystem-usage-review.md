# Ecosystem usage, monorepo and gap review — 8 November 2026

Scope: a fresh, independent pass over usage, code quality, monorepo compliance, security and missing
patterns across the four `FrenchExDev2.QuietCli.PoSh` projects, requested after the extensive prior audit
series below. This is a **static, read-only review**: no shell/process-execution tool was available in
this session, so nothing here was run, built or tested; every claim is either read directly from the
current source tree or cross-checked against an existing dated audit. Where a claim needs dynamic
confirmation, the launch command to do so is given instead of a result.

## What this builds on

This module already carries one of the most rigorous audit trails in the workspace: a full security/SOLID/DRY
pass on [4 November](2026-11-04-securite-logiciel.md) with 10 findings, all closed and independently
re-verified on Windows/Alpine/Debian in the [5 November remediation](2026-11-04-remediation.md); a tracked,
incremental PowerShell→C# migration documented in
[`docs/powershell-csharp-boundaries.md`](../powershell-csharp-boundaries.md) with four completed passes;
and per-area audits for the frame codec, run-profile tooling, PTY streams and every major Git command family.
This review does not repeat that work. It reports only what independent reading turned up that those documents
do not already cover, plus a few explicit confirmations worth stating because they were checked, not assumed.

## Findings

### GAP-01 — The two scripts that mutate the monorepo's Git history have no test coverage

**Severity: medium.** `scripts/Commit-Workspace.ps1` stages and commits the whole workspace;
`scripts/Push-Workspace.ps1` pushes a branch to its configured remote. Neither takes `-WhatIf`, and both are
one real `git commit` / `git push --set-upstream` away from changing a shared history.

A search of both test companions found zero references to either script:

```text
Grep "Push-Workspace|Commit-Workspace" FrenchExDev2.QuietCli.Core.Tests.PoSh  -> only the .psm1 export list
Grep "Push-Workspace|Commit-Workspace" FrenchExDev2.QuietCli.Git.Tests.PoSh   -> no matches
Grep "Push-Workspace|Commit-Workspace" scripts/                              -> no *.Tests.ps1 file exists there at all
```

Every other mutating surface in this workspace — the engine, the Git handlers, the gallery publication flow,
the run-profile tooling — has property/fuzz/mutation coverage per the project's own test-strategy policy, and
the root `AGENTS.md` commit-checkpoints section explicitly requires that "mutating Git fixtures must be owned
disposable repositories." `Commit-Workspace.ps1`/`Push-Workspace.ps1` are exactly this kind of mutating Git
surface, and they are the one place in the ecosystem that policy is not applied: there is no disposable-repository
fixture exercising "stage everything, refresh the lock, commit once" or "push once, no force, no retry."

Suggested closure: a fixture repository under an owned temporary directory (same pattern already used for the
Git module's own disposable-repository tests), asserting that `Commit-Workspace.ps1` refreshes the lock before
staging, commits exactly once, and never touches a remote; and that `Push-Workspace.ps1` never force-pushes and
fails closed (no retry) when the remote rejects the push. No launch command exists yet because the test does
not exist; once added it belongs in the existing `Invoke-WorkspaceCi.ps1` suite set.

### OBS-01 — Dense single-line PowerShell style is not confined to the Git lexer

The 4 November audit flagged `Get-GitArgumentToken` and `Read-QuietArguments` by name for cramming many
branches onto few lines, and recommended reformatting before adding more variants. Reading scripts written or
touched after that audit shows the same style is the house convention, not an isolated spot:

- `scripts/Push-Workspace.ps1` line 15: the entire `param()` block (four parameters, two with
  `ValidatePattern`, one `ValidateSet`) is one line.
- `scripts/Commit-Workspace.ps1`: `$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)` and
  the three-statement body are each single `;`-joined lines.
- `scripts/Publish-QuietGallery.ps1` line 13: parameter block, attributes and validation pattern on one line;
  the publish/catch/finally control flow is still readable but consistently minimizes line count over
  statement separation.

This is a style choice applied consistently, and it is not itself a correctness defect — none of the three
files above have a logic problem. It is reiterated here because the original audit scoped the recommendation
to one file family, which could read as "fixed once the lexer is reformatted." The convention is ecosystem-wide
and any reformatting pass should be scoped that way too, or explicitly declared a deliberate style and dropped
from future findings.

### OBS-02 — Audit file:line citations will keep drifting as the C# migration continues

`FrenchExDev2.QuietCli.Core.PoSh/src/` currently contains exactly two files, `Invoke.ps1` and `Protocol.ps1`.
`Registry.ps1`, `Gain.ps1`, `Scaffold.ps1`, `Delivery.ps1` and `Runtime.ps1` — all cited by file:line in the
4 November security audit (SEC-02, SEC-03, DES-01, REL-02) — no longer exist as PowerShell source; their
responsibilities now live in `engine/Cmdlets/*.cs` (`HandlerCommands.cs`, `GainCommands.cs`,
`ModuleScaffold.cs`/`ScriptCommands.cs`, `DeliveryCommands.cs`, `RuntimeCommands.cs`). This is not a surprise
or an undocumented change: `docs/powershell-csharp-boundaries.md` tracks each move explicitly, by file, with
its own validation.

The gap is narrower than "the migration is undocumented" — it is that the boundaries document does not say,
for each moved file, whether the specific security remediations the 4 November audit attached to that file
(message scrubbing in `Gain.ps1`'s former home, the metadata whitelist depth check, the binary-extension
identity fix) were carried into the C# replacement or re-verified there. Today a reader has to manually bridge
the security audit and the boundaries document to answer that question; neither document answers it alone.
Suggested closure: a one-line cross-reference in `powershell-csharp-boundaries.md` per moved file, pointing at
the finding it inherited and whether/where that finding's regression test followed it.

### Confirmed, not re-litigated

Checked directly rather than assumed, since each is easy to get wrong and none appear in a prior audit:

- **`.gitignore` hygiene is correct.** `/artifacts/`, `.vs/`, `.env`/`.env.*`, `**/bin/`, `**/obj/`, `**/lib/`
  are all excluded. This matters because `artifacts/` on this checkout is large — over 1,500 `.psd1` files
  alone across extracted package-tests, gallery-tests and two full PowerShell toolchain installs (stable and
  preview) — and none of it is a repository-bloat risk.
- **Gallery credential handling matches the stated policy.** `scripts/Publish-QuietGallery.ps1` reads
  `PSGALLERY_API_KEY` only from the environment (line 19: throws if unset, never accepts it as a parameter),
  pins the repository URI with a case-sensitive compare before publishing, and refuses to republish a version
  that already exists remotely. This is exactly what the root `AGENTS.md` requires ("Never commit the
  workspace `.env`, print its token, pass it as a native command argument, or copy it into reports") and what
  SEC-06's remediation promised; it holds up on direct reading.
- **The ecosystem's own `AGENTS.md` satisfies the outer monorepo's documentation requirement.** The root
  `FrenchExDev_i2/AGENTS.md` requires each monorepo to document its project map, dependencies, workflow
  filters, validation commands and publication trigger. `FrenchExDev2.QuietCli.PoSh/AGENTS.md` does all five
  (Core/Core.Tests/Git/Git.Tests dependency graph, `core-ci.yml`/`git-ci.yml` path filters calling the shared
  `ci.yml`, `Invoke-WorkspaceCi.ps1` suite commands, and the `psgallery`-gated `publish-psgallery.yml`/
  `preview-psgallery.yml` trigger). No gap found here.

## Usage, read as a prospective caller rather than an auditor

The top-level `README.md`'s `dotnet --list-sdks` and `git status` walkthroughs are honest about what they
measure (byte counts, not tokens or cost) and fail closed on an unrecognized record rather than guessing — a
caller who copies the examples gets the stated behavior. The Git companion is equally honest about its own
limits: `Get-QuietGitCoverage` self-reports **58 of 183** locked inventory entries implemented, 125
`PartialOrMissing`, and qualification `Pending` for all 183 (`EntireInventoryQualified = False`). A caller
adopting the Git module needs to run that coverage check before depending on a specific subcommand — the
README says so directly rather than implying broader support than exists. This is a usability strength worth
preserving as new handlers are added: keep the coverage/qualification split visible rather than folding it into
an aggregate "N commands supported" number that would hide the `Pending` qualification state.

## Method and limits

Read: both root-level `AGENTS.md`/`README.md` pairs, `docs/powershell-csharp-boundaries.md`, nine prior audits
(4–8 November), `scripts/Publish-QuietGallery.ps1`, `scripts/Push-Workspace.ps1`, `scripts/Commit-Workspace.ps1`,
`FrenchExDev2.QuietCli.Core.PoSh/src/Invoke.ps1`, the Core and Git module manifests, the Git module's
`README.md` coverage section, and `.gitignore`. Directory discovery initially timed out against this checkout's
`artifacts/` tree (ripgrep-based globbing exceeded 20 s against ~1,500+ files of extracted toolchains and
package/gallery-test fixtures); all further exploration scoped paths to exclude `artifacts/` explicitly.

Not done: no build, no test run, no `git log`/`git status` on this checkout, no review of the engine C# source
beyond confirming file existence by name, and no re-verification of any of the nine prior audits' own dynamic
evidence (test counts, SHA-256 digests, mutation scores) — those are taken as reported. No commit, push or
workspace mutation was performed while producing this document.
