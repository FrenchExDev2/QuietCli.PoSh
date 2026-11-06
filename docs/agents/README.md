# QuietCli agent documents

This directory holds the documents that tell AI agents how to use QuietCli. They split into
**distributed** documents, copied into the Core package and into user projects, and
**repository-only** guides that stay here.

| File | Audience | Distributed | Purpose |
| --- | --- | --- | --- |
| [AGENTS.md](AGENTS.md) | any agent | yes | The whole production contract: rules, every command, four tested examples, failure table. Single source |
| [SKILL.md](SKILL.md) | agents with native skills | yes | Generated: skill front matter + the `AGENTS.md` text, unchanged |
| [openai.yaml](openai.yaml) | Codex | packaged only | Skill metadata (display name, default prompt) |
| [examples.md](examples.md) | any agent | no | Seven more tested examples: projection, gains, Recall, evidence transfer |
| [non-git-example.md](non-git-example.md) | any agent | no | Verified example with a non-Git executable (`dotnet`) |
| [troubleshooting.md](troubleshooting.md) | any agent | no | Error codes and incomplete-evidence symptoms, with the fix |
| [claude.md](claude.md) | Claude Code users | no | Install the instructions and drive QuietCli from Claude Code |
| [codex.md](codex.md) | Codex users | no | Install the instructions and drive QuietCli from Codex |
| [persistent-shell.md](persistent-shell.md) | agent integrators | no | Keep one PowerShell process alive across tool calls |

## Who reads what

| Client | Reads automatically | How QuietCli reaches it |
| --- | --- | --- |
| Codex and most agents | `AGENTS.md` | `Add-QuietAgentInstruction -Agents` copies the documents and references them |
| Claude Code | `CLAUDE.md` (not `AGENTS.md`) | `Add-QuietAgentInstruction -Claude` writes `@./.skills/AGENTS.md` into `CLAUDE.md` |
| Native skills | `SKILL.md` in the skills directory | `-Skill` writes a reference in the project's `SKILL.md`; registering the skill is manual |

`CLAUDE.md` therefore needs no content of its own: it imports `AGENTS.md`.

## Editing rules

- Edit `AGENTS.md` only, then run `scripts/Sync-SkillDocument.ps1`. The tests fail when `SKILL.md`
  differs from the generated text.
- `AGENTS.md` must stay self-contained: at most 150 lines, no relative link (only `AGENTS.md` and
  `SKILL.md` are copied into projects), the `Get-Help` and GitHub pointers, and every exported Core
  command named in backticks.
- Both files are non-empty UTF-8 with LF line endings; staging rejects anything else.
- `AGENTS.md` holds 4 `quiet-example` blocks and `examples.md` 7. `AgentInstructions.Tests.ps1`
  runs them in that order, `AGENTS.md` first, against a disposable Git repository. A change to the
  set is a change to that test.
- Repository-only guides may link anywhere in the repository.

`scripts/AgentDocuments.ps1` stages `AGENTS.md`, `SKILL.md` and `openai.yaml` byte for byte into
the Core package (`resources/agents`). `Add-QuietAgentInstruction` copies only `AGENTS.md` and
`SKILL.md` into a project (`.skills` by default).

Production usage instructions are separate from the repository maintenance rules in the
project-level [AGENTS.md](../../AGENTS.md).
