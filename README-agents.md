# QuietCli with AI agents

[Back to the QuietCli overview](README.md)

Install the QuietCli instructions for Codex, Claude Code or another agent. Related: [agent documents](docs/agents/README.md), [Streaming and callbacks](README-streaming.md).

QuietCli ships one set of production instructions for agents: `AGENTS.md` (rules, every command, tested examples,
failure table) and `SKILL.md` (the same text with skill front matter). `Add-QuietAgentInstruction` copies both into
your project's `.skills` directory and writes a short, delimited reference block into the instruction file your agent
reads. Text outside that block is never touched, and repeating the command changes nothing.

**QuietCli installs no hook, profile change or agent setting.** The engine grants no such permission; the command
only writes the files listed in its result. The command ships with the Core module of this checkout (0.2.0-preview);
check that an older published package has it with `Get-Command Add-QuietAgentInstruction`.

Preview first, from the project the agent will work on:

```powershell
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$project = (Get-Location).Path
$preview = Add-QuietAgentInstruction -Path $project -Agents -WhatIf
$preview.Files | Select-Object Path, ReferencePath, Status
```

Then run the line for your agent, without `-WhatIf`:

| Agent | Command | What the agent then reads |
| --- | --- | --- |
| Codex, and agents following the `AGENTS.md` convention | `Add-QuietAgentInstruction -Path $project -Agents` | `AGENTS.md` at the project root, which links to `.skills/AGENTS.md` |
| Claude Code | `Add-QuietAgentInstruction -Path $project -Claude` | `CLAUDE.md`, which imports `@./.skills/AGENTS.md` (Claude Code does not read `AGENTS.md` by itself) |
| Native skills (any agent with a skills directory) | `Add-QuietAgentInstruction -Path $project -Skill` | A reference in the project's `SKILL.md`. Registering the skill is manual: copy `.skills/SKILL.md` into your agent's skills directory (for Claude Code, `.claude/skills/quiet-cli/SKILL.md`) |
| Several agents | combine the switches, for example `-Agents -Claude` | Both files above |
| An agent with its own instruction file | no switch fits | Point that file at `.skills/AGENTS.md`, after running any of the commands above to create it |

Options: `-DocumentDirectory <path>` chooses another copy directory than `.skills`; `-Document Agents|Skill` forces
which document every selected target references. `Get-QuietAgentInstruction` returns the `AGENTS.md` text without
writing anything. Existing project files keep their rules, BOM and line endings; malformed QuietCli markers, linked
directories and non-UTF-8 files are rejected before anything is written.

Check the result before trusting it: the returned `Files` list shows `Created`, `Updated` or `Unchanged` for each
target, and you can start the agent in the project and ask it which instruction files it loaded. Codex discovers
`AGENTS.md` from the project root toward its working directory; Claude Code loads `CLAUDE.md` and follows its import.
Start the agent's shell with its normal PowerShell profile so that `quiet` and UTF-8 initialization are available.

Guides for each client, an example with a non-Git executable and a troubleshooting table are indexed in
[agent documents](docs/agents/README.md): [Claude Code](docs/agents/claude.md), [Codex](docs/agents/codex.md),
[troubleshooting](docs/agents/troubleshooting.md).
