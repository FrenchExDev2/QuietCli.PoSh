# Using QuietCli with Claude Code

Repository-only guide; see the [agent documents index](README.md). The distributed rules are in
[AGENTS.md](AGENTS.md); [SKILL.md](SKILL.md) is the same text with skill front matter. This guide covers only what is
specific to Claude Code.

## Install the instructions into a project

`Add-QuietAgentInstruction` copies `AGENTS.md` and `SKILL.md` into the project and writes a
delimited reference block. For Claude Code, select `-Claude`:

```powershell
# Objective: Preview, then install QuietCli's production instructions for Claude Code.
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$repository = (Get-Location).Path
$preview = Add-QuietAgentInstruction -Path $repository -Claude -WhatIf
$preview.Files | Select-Object Path, ReferencePath, Status
```

Run it without `-WhatIf` only when the user asked for the installation: it writes files in the
project. What it does, from `src/Agent.ps1`:

- copies `AGENTS.md` and `SKILL.md` into `.skills` (or the `-DocumentDirectory` you choose);
- creates or updates the project's `CLAUDE.md` and replaces only the block between
  `<!-- quietcli:instructions:begin -->` and `<!-- quietcli:instructions:end -->`;
- writes an import line (`@./.skills/AGENTS.md`, spaces escaped with a backslash) instead of a
  Markdown link, so Claude Code loads the rules with the project memory;
- leaves everything outside the block untouched, and is idempotent (`Unchanged` on a repeat).

`-Agents` adds the same reference to `AGENTS.md` as a Markdown link. `-Skill` writes a `SKILL.md` reference in the project root;
it does **not** register a native Claude Code skill. To use `SKILL.md` as a Claude Code skill, place
a copy under the skills directory your Claude Code setup reads (for example `.claude/skills/quiet-cli/SKILL.md`)
yourself; its front matter (`name`, `description`) already follows that format. That step is outside
what the module automates.

## Shell behavior in Claude Code

- Each `Bash` or `PowerShell` tool call starts a new process unless the client documents otherwise,
  so `$result` does not survive between calls. Keep one call self-contained: import Core, run
  `quiet -AsObject`, check the envelope and deliver a bounded view in the same call.
- Do not attempt the Codex-style long-lived loop from [persistent-shell.md](persistent-shell.md);
  it relies on `exec_command` / `write_stdin`, which Claude Code does not expose.
- When a later call needs the evidence, use `-SaveRecall` and reload it by `RecallId`
  ([examples.md](examples.md), "Save evidence"), not a variable.
- Background commands (`run_in_background`) are reported when they finish. Do not poll their output.

## Rules from the repository that apply to the agent

- Call every native CLI through `quiet`, with the Core module explicitly imported once per process.
- Use PowerShell 7.6+ with its normal profile; do not add `-NoProfile` without a reason.
- A test run needs a visible `pwsh` monitoring window opened at the same time as the run; the
  `Monitor` tool may supplement it but does not replace it.
- Do not commit, push or publish implicitly while building or testing.

These come from the workspace and project `AGENTS.md` files and are repository maintenance rules,
not part of the distributed production instructions.
