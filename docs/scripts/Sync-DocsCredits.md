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
  PowerShell cmdlets (`Get-ChildItem`, `Get-Content`, regex) and `[System.IO.File]::WriteAllText`.
- No external process is shelled out to.
- Filesystem assumptions: `DocsPath`, `RootPath`, and `CreditsPath` must already exist (explicit
  `throw` guards at lines 54-56) — it does not create `docs/` or `CREDITS.md` itself.

## Side effects

- Report mode (default): read-only; only reads each candidate `*.md` file's content to classify it as
  `Missing`/`Stale`/`UpToDate`.
- `-Apply` (with `ShouldProcess` approval per file): rewrites each non-compliant file in place — either
  replacing an existing stale block in place (line 97) or appending a new block after two trailing
  newlines (line 99) — using UTF-8 without BOM (`$utf8NoBom`, line 83, 101).
- Throws `DocsCreditsNonCompliant: ...` (lines 110-112) listing every file still non-compliant after
  the run, which fails the calling CI job in check mode.

## Findings

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
- Testability gap: no Pester test file references `Sync-DocsCredits.ps1`, `New-CreditsBlock`, or the
  compliance-state logic (`Missing`/`Stale`/`UpToDate`) — searched `*.Tests.ps1` under both
  `*.Tests.PoSh` projects, no hits. As with `Sync-Credits.ps1`, the only exercise this logic gets is
  whatever CI workflow runs it against real repository content; there is no unit test for the
  anchor/relative-path computation, the `-NoRecurse` behavior, or the stale-vs-missing branch.
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
