# Sync-DocsCredits.ps1

## Purpose

Enforces a repository-wide documentation policy: every `docs/**/*.md` file and every root
`README*.md` file must carry a standard, machine-generated "Credits" paragraph linking back to the
mandatory `CREDITS.md` (produced by `Sync-Credits.ps1`). This solves the problem of license
attribution being easy to omit or let drift as documentation grows — instead of trusting every doc
author to remember the paragraph, this script can both audit (default) and repair (`-Apply`) every
document in one pass. It is the natural second step after `Sync-Credits.ps1`
(`CREDITS.md`'s own header explicitly says "Every `docs/*.md` file links back to it ... checked and
written by `scripts/Sync-DocsCredits.ps1`", confirmed in `scripts/Sync-Credits.ps1:106-107`), and is
almost certainly run in the same CI gate/apply pairing pattern as `Sync-Credits.ps1` (its behavior is
symmetric: no `-Apply` reports only, `-Apply` writes, `-Apply -WhatIf` previews).

The two distributed files `docs/agents/AGENTS.md` and `docs/agents/SKILL.md` use the public absolute
`https://github.com/FrenchExDev2/QuietCli.PoSh/blob/HEAD/CREDITS.md` link. They are copied
into consumer projects without the repository's credits file, so a relative link would violate their
self-contained contract. Other documentation retains its relative credits link. After changing
AGENTS.md, regenerate SKILL.md with `Sync-SkillDocument.ps1` and check both sync gates again.

## Usage

```
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DocsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs'),
    [string]$RootPath = (Split-Path $PSScriptRoot -Parent),
    [string]$CreditsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'CREDITS.md'),
    [switch]$NoRecurse,
    [switch]$Apply
)
```

- `DocsPath` (string, optional) — documentation directory scanned recursively for `*.md`. Defaults to
  `docs` at the repository root.
- `RootPath` (string, optional) — repository root scanned (non-recursively) for `README*.md`. Defaults
  to the script's parent directory.
- `CreditsPath` (string, optional) — the mandatory credits file every document must link to. Defaults
  to `CREDITS.md` at the repository root.
- `NoRecurse` (switch, optional) — restricts `DocsPath` scanning to its direct children only, skipping
  subfolders such as `agents`, `audits`, `ci`.
- `Apply` (switch, optional, default `$false`) — without it, only reports; with it, writes the missing
  or stale block into every non-compliant file (honors `-WhatIf`/`-Confirm`).

Examples (from the doc comment):

```powershell
./scripts/Sync-DocsCredits.ps1                # report only
./scripts/Sync-DocsCredits.ps1 -Apply -WhatIf # preview writes
./scripts/Sync-DocsCredits.ps1 -Apply         # write into every non-compliant file
```

## Dependencies

- No dot-sourced scripts and no `Common.ps1` dependency — entirely self-contained, using only built-in
  PowerShell cmdlets (`Get-ChildItem`, `Get-Content`, regex) and asynchronous UTF-8 file writes.
- No external process is shelled out to; public absolute links are generated without network access.
- Filesystem assumptions: `DocsPath`, `RootPath`, and `CreditsPath` must already exist (explicit
  `throw` guards at lines 54-56) — it does not create `docs/` or `CREDITS.md` itself.

## Side effects

- Report mode (default): read-only; only reads each candidate `*.md` file's content to classify it as
  `Missing`/`Stale`/`UpToDate`.
- `-Apply` (with `ShouldProcess` approval per file): rewrites each non-compliant file in place — either
  replacing an existing stale block in place (line 97) or appending a new block after two trailing
  newlines — using UTF-8 without BOM and `WriteAllTextAsync(...).GetAwaiter().GetResult()`.
- Throws `DocsCreditsNonCompliant: ...` (lines 110-112) listing every file still non-compliant after
  the run, which fails the calling CI job in check mode.

## Findings

- **Portability regression fixed:** the generated relative footer previously made the distributed
  agent documents fail `Test-QuietAgentDocumentSet` in
  `FrenchExDev2.QuietCli.Core.Tests.PoSh/AgentInstructions.Tests.ps1:67`. The generator now uses an
  absolute public link for exactly those two portable documents. Existing independent tests still
  reject relative links and hand-edited generated SKILL bodies; that contract was not weakened.

- No bugs found in the core regex-based block detection/replacement (lines 48-52, 90-100) — the
  `Singleline` regex scoped between literal begin/end markers correctly handles multi-line content
  and the substring splice preserves content before/after the block.
- DESIGN: The relative-path computation for the credits link (`$relativeDir`, line 85) is computed as
  `GetRelativePath(file.DirectoryName, credits-directory)`; for a file directly inside `docs/agents/`,
  this correctly produces `../../CREDITS.md`-style paths, but there is no test or assertion in the
  script itself that the resulting relative link is syntactically valid Markdown or resolves — a
  malformed relative-path edge case (e.g. a doc file sitting on a different drive on Windows, which
  `GetRelativePath` handles by returning the absolute path unchanged) would silently embed an absolute
  local filesystem path into a committed Markdown file instead of throwing. Low likelihood given the
  current fixed directory layout, but worth a guard given this script's whole job is link correctness.
- CONVENTION: all reads use synchronous `Get-Content -Raw -Encoding UTF8` (lines 79, 89) rather than
  the `.GetAwaiter().GetResult()` async pattern used elsewhere in this folder (e.g.
  `AgentDocuments.ps1`, `Sync-SkillDocument.ps1`) — same inconsistency noted in `Sync-Credits.ps1`.
- CONVENTION: unlike `Sync-SkillDocument.ps1`'s explicit `$agents.Contains("`r")` CRLF rejection, this
  script does not verify that the *existing* content of a target `.md` file is LF-only before splicing
  in the new block (lines 89-100) — a file with CRLF line endings would get a clean LF block spliced
  into a CRLF document, producing mixed line endings on disk, in violation of the repository's
  "UTF-8 and LF line endings on disk" rule.
- Coverage: `CommitWorkspace.Tests.ps1` exercises this script's real fixture generation and gate
  wiring, including staged documentation. `AgentInstructions.Tests.ps1` independently checks the
  self-contained distributed result and rejects relative-link document mutants. Full generator
  coverage for cross-drive relative paths, `-NoRecurse` and every replacement branch remains a gap.
- No security concern: operates only on repository-local Markdown files with no secrets or network
  involvement.

## Verdict

Solid, narrowly-scoped compliance tool that does what its documentation claims; the highest-priority
fix is adding the same CRLF-rejection guard `Sync-SkillDocument.ps1` already has, so a stray CRLF file
cannot silently produce a mixed-line-ending document when `-Apply` patches it.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Checks or writes the mandatory CREDITS.md credits paragraph at the end of every docs/**/*.md and root README*.md file.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
