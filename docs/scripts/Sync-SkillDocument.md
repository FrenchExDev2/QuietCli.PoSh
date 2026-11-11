# Sync-SkillDocument.ps1

## Purpose

Regenerates the distributed `docs/agents/SKILL.md` file from the canonical `docs/agents/AGENTS.md`
source, so the "skill" packaging format (front matter + body) never has to be hand-maintained
separately from the production agent instructions. This solves documentation drift between two
representations of the same content: `AGENTS.md` is the single source of truth, `SKILL.md` is a
derived artifact consumed by whatever packages this project as a Claude/agent "skill". It is run by a
human after any `AGENTS.md` change — `docs/agents/README.md:31` states this explicitly: "Edit
`AGENTS.md` only, then run `scripts/Sync-SkillDocument.ps1`. The tests fail when `SKILL.md`" is stale —
implying a companion test (likely `AgentInstructions.Tests.ps1`) checks `SKILL.md` against what this
script would regenerate, making this a CI-enforced regeneration step, not just a convenience script.

## Usage

```
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
```

- `WorkspaceRoot` (string, optional) — the QuietCli monorepo root; defaults to the parent of the
  script directory. No other parameters; the source (`docs/agents/AGENTS.md`) and destination
  (`docs/agents/SKILL.md`) paths are hardcoded relative to it.

Example:

```powershell
./scripts/Sync-SkillDocument.ps1
```

## Dependencies

- Dot-sources `AgentDocuments.ps1` (line 12) for `New-QuietSkillDocumentText`.
- No external process, no module import. Pure file I/O.
- Filesystem assumption: `docs/agents/AGENTS.md` must exist under `WorkspaceRoot`, be non-empty, and
  contain no `\r` characters (line 16) — i.e. it must already be UTF-8 LF-only. There is no repair
  path; a CRLF `AGENTS.md` makes this script throw rather than normalize it.

## Side effects

- Writes `docs/agents/SKILL.md`, always fully replacing its content with the front matter plus the
  verbatim `AGENTS.md` body (line 18), using UTF-8 without BOM (`[Text.UTF8Encoding]::new($false)`).
- No other side effects: it is not gated by `ShouldProcess`/`-WhatIf` — unlike `Sync-Credits.ps1` and
  `Sync-DocsCredits.ps1`, this script has no "report only" mode or `-Apply` switch. It unconditionally
  overwrites `SKILL.md` on every invocation.

## Findings

- No bugs found: the happy path (read `AGENTS.md`, validate it's non-empty UTF-8 LF, wrap it with front
  matter from `New-QuietSkillDocumentText`, write `SKILL.md`) is short, correctly uses the async
  `ReadAllTextAsync`/`WriteAllTextAsync(...).GetAwaiter().GetResult()` pattern AGENTS.md mandates
  (lines 15, 18), and matches its documented contract.
- DESIGN: Unlike its siblings `Sync-Credits.ps1` and `Sync-DocsCredits.ps1`, this script has no
  report-only / `-Apply` / `-WhatIf` mode — it always writes. If `docs/agents/README.md:31`'s claim
  that "the tests fail when SKILL.md" is stale is accurate, then the actual CI gate for staleness
  detection must live entirely in a separate test file (not reviewed here), with this script serving
  purely as the human-facing "fix it" tool. That is a reasonable split of responsibility, but it means
  this script alone cannot be used as a CI check (it would always "pass" by silently overwriting), so
  anyone wiring a new CI step around it should not assume it has check semantics like its two siblings.
- DESIGN: The skill description text is a hardcoded literal inside `AgentDocuments.ps1`
  (`New-QuietSkillDocumentText`, line 34: `$description='Use when running a native command (git,
  dotnet, or any executable) from PowerShell through the \`quiet\` alias ...'`), not something
  `Sync-SkillDocument.ps1` itself parameterizes or could override. A change to the skill's one-line
  description requires editing `AgentDocuments.ps1` directly rather than `Sync-SkillDocument.ps1` or
  `AGENTS.md` — a minor SOLID/single-source-of-truth gap since the skill's *name and description* live
  in a different file than its *body content*.
- CONVENTION: no issue — this is one of the few scripts in this batch that actually follows the
  async-I/O convention consistently (lines 15, 18).
- Testability: `docs/agents/README.md` asserts a test exists that fails on `SKILL.md` staleness; that
  test file was not part of this review's assigned scope (likely `AgentInstructions.Tests.ps1`, which
  matched the broader repository search for "AGENTS.md"/"SKILL.md"-adjacent terms), so it is plausible
  but not independently confirmed from this script's own folder that the regeneration logic
  (`New-QuietSkillDocumentText`'s front-matter construction) has dedicated unit coverage beyond an
  equality check against the live file.
- No security concern: local-only file transform, no untrusted input, no network.

## Verdict

Fit for purpose as a simple, correct regeneration tool; the one thing worth flagging to users is that
it has no dry-run or check mode of its own — anyone wanting a CI gate for `SKILL.md` staleness needs
the separate test referenced in `docs/agents/README.md`, not this script in isolation.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->

<!-- script-contract:begin -->
## Execution contract

Purpose: Regenerates docs/agents/SKILL.md from docs/agents/AGENTS.md.

Boundary: **Executable**. Preview API: **ShouldProcess**. Guarded functions: 0.

See [the complete review](preview-support.md) for orchestration guards, delegated effects and static-analysis limits.
<!-- script-contract:end -->
