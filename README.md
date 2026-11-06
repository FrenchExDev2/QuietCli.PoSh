<p align="center">
  <img src="./icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# QuietCli

**QuietCli** (pronounced *Quietly*) runs native command-line tools from PowerShell Core 7.6+ and turns their noisy output into small, typed, trustworthy results. It is built for AI agents and developer tooling, where every byte of terminal text costs time, context and attention.

A C# engine starts the native process and streams its output once, through bounded buffers. Your own PowerShell callbacks, which stay in your process, turn that stream into business data. You then inspect the data directly or deliver a bounded JSON/YAML view of it.

> **Status: preview (`0.2.0-preview`).** The engine is under active development and its API may change. The Git companion module is a work in progress and is presented here as an example only. Nothing in this repository is a release qualification unless a report says so; see [Tests and qualification](README-qualification.md).

## What QuietCli gives you

- **Any executable, one entry point.** `quiet` (an alias of `Invoke-QuietCli`) wraps `git`, `dotnet`, `docker` or any other native command. QuietCli options come first; native arguments follow verbatim.
- **Output becomes data.** `-Output` and `-Complete` callbacks parse the stream into objects. Nothing is captured, spooled or kept in a history unless you ask for it.
- **Results you can trust.** Every result reports `Outcome`, `Execution` and `Completeness`, so a truncated or failed run is never mistaken for a clean one.
- **Bounded deliveries.** `ConvertTo-QuietJson`, `ConvertTo-QuietYaml` and `Out-QuietResult` enforce item, structural and byte budgets, with token counts measured on the exact delivered text.
- **Capture once, analyze again.** Opt-in *Recall* keeps native evidence in memory or in a durable journal, so analysis can continue in another session without running the command again.
- **Ready for AI agents.** `Add-QuietAgentInstruction` installs production instructions for Codex, Claude Code or any agent that reads `AGENTS.md` or a skill file.
- **Honest measurements.** `Get-QuietCliGain` reports measured volumes and overhead. Unknown values stay unknown, and metadata never contains your business output.
- **Reusable modules.** Companion modules register tested business handlers for one executable, and `New-QuietModule` scaffolds a new one.

## Requirements

| Item | Requirement |
| --- | --- |
| PowerShell | Core 7.6 or later |
| Operating systems | Windows and Linux (glibc and musl) |
| Architectures | x64 and ARM64 |
| Hosting | Automatic: the integrated build matching the PowerShell CLR (.NET 10 or .NET 11+). The isolated `Process` host needs the pinned .NET 11 RC runtime. See [Hosting](README-hosting.md) |
| Native tools | Installed separately; QuietCli never installs the executables you call |

Configured platforms are not the same as qualified platforms. See [Tests and qualification](README-qualification.md) for what has actually been executed.

## How to install

From a source checkout, import the local Core manifest. A built module needs no SDK; import does not compile C#.

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1
```

If binaries are missing or stale, build with `./scripts/Build-Workspace.ps1` and start a fresh PowerShell process. Details are in [Development](README-development.md).

From PowerShell Gallery, use `-Prerelease` to select the preview line once a preview is published. Publication status and platform notes are in [package installation](docs/PSGallery.md).

```powershell
Install-PSResource -Name FrenchExDev2.QuietCli.Core.PoSh -Prerelease -Repository PSGallery -Scope CurrentUser
```

## How to use

Run any native command through `quiet`. This example lists the installed .NET SDKs as typed objects. The parser was written after reading the actual `dotnet --list-sdks` output: one `<version> [<sdk root>]` record per line.

```powershell
$r = quiet -AsObject -C sdk-inventory -RecordDelimiter "`n" `
    -Data @{ Sdks = [Collections.Generic.List[object]]::new() } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -ne 'stdout') { return }
        $m = [regex]::Match($event.Text.TrimEnd([char[]]"`r`n"), '^(?<version>\S+) \[(?<path>.+)\]$')
        if (!$m.Success) { throw 'InvalidDotnetSdkRecord' }
        [void]$runtime.Data.Sdks.Add([pscustomobject]@{ Version = $m.Groups['version'].Value; Root = $m.Groups['path'].Value })
    } `
    -Complete {
        param($runtime)
        [pscustomobject]@{ InstalledSdks = $runtime.Data.Sdks.Count; Sdks = $runtime.Data.Sdks.ToArray() }
    } `
    dotnet --list-sdks

# Check the run before trusting the business result.
$r.Outcome
$r.Execution
$r.Completeness
$r.Data

# Deliver a bounded view for a human or an agent.
ConvertTo-QuietJson $r -MaxOutputBytes 4096
```

QuietCli options precede the executable (`dotnet`); native arguments follow it. The parser throws on a record it does not recognize rather than guessing. Read the executable's help or official documentation before writing a parser for it.

What `Outcome`, `Execution` and `Completeness` mean, the guard to apply before using `Data`, and the callback pitfalls are in [Streaming, callbacks and results](README-streaming.md). A longer walkthrough is in [analyzing a non-Git executable](docs/agents/non-git-example.md).

## Bounded delivery, measured

The point of a delivery budget is that the size of what you hand to a human or an agent no longer grows with the size of the repository. Measured on 6 November 2026 on Windows, with the local `0.2.0-preview` Core and Git modules, on disposable repositories (byte counts of UTF-8 text, default item budget):

| Repository state | Raw `git status` | `quiet -AsObject git status` delivered with `ConvertTo-QuietJson -MaxOutputBytes 4096` |
| --- | ---: | ---: |
| 40 modified and 20 untracked files | 1,883 bytes | 2,973 bytes |
| 1,500 modified files | 33,640 bytes | 2,795 bytes (1,480 of 1,500 entries reported as omitted) |

On a small repository the structured JSON is larger than the raw text, because it carries typed fields. On a large one it stays bounded and states explicitly what it left out (`Truncation.Applied`). A caller-defined projection can be much smaller still, as in the counters example below. These are byte counts, not model tokens or cost: byte reduction alone establishes neither context-window use nor financial savings. See [Measurements and privacy](README-measurements.md) and the [comparison with RTK](QUIET_VS_RTK_MEASURES.md) for definitions and limits.

## Use QuietCli with an AI agent

`Add-QuietAgentInstruction` copies QuietCli's production instructions into your project's `.skills` directory and writes a short, delimited reference block into the instruction file your agent reads. Text outside that block is never touched, and repeating the command changes nothing. It installs no hook, profile change or agent setting.

```powershell
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$project = (Get-Location).Path

# Preview first, then run without -WhatIf.
Add-QuietAgentInstruction -Path $project -Claude -WhatIf    # Claude Code: CLAUDE.md imports .skills/AGENTS.md
Add-QuietAgentInstruction -Path $project -Agents -WhatIf    # Codex and AGENTS.md readers
```

Commands for each agent, the skill form, options and verification steps are in [QuietCli with AI agents](README-agents.md).

## Example: a companion module (Git, under development)

> **Status: under development.** The Git module illustrates what a companion module looks like. Its handler catalogue is growing, the full command/version/platform matrix is not qualified, and its API and coverage may change. Inventory membership is not support. Read the [Git README](FrenchExDev2.QuietCli.Git.PoSh/README.md#coverage-and-limits) before relying on a command.

A handler is a ready-made callback pair. `quiet -AsObject git status` is shorthand for the explicit form `quiet -AsObject -Output { ... } -Complete { ... } git status ...`, where the module supplies the `-Output` parser and the `-Complete` finalizer for you. The explicit form below does the same job by hand on a small scale: it asks Git for its machine format, counts the entries of a repository and returns a typed result.

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1

# Without a companion module: you write the callbacks.
$r = quiet -AsObject -C git-status -RecordDelimiter "`n" `
    -Data @{ Branch = $null; Changed = 0; Conflicted = 0; Untracked = 0 } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -ne 'stdout') { return }
        $line = $event.Text.TrimEnd([char[]]"`r`n")
        switch -Regex ($line) {
            '^# branch\.head (?<name>.+)$' { $runtime.Data.Branch = $Matches['name'] }
            '^[12] ' { $runtime.Data.Changed++ }
            '^u '    { $runtime.Data.Conflicted++ }
            '^\? '   { $runtime.Data.Untracked++ }
        }
    } `
    -Complete {
        param($runtime)
        [pscustomobject]@{
            Branch     = $runtime.Data.Branch
            Changed    = $runtime.Data.Changed
            Conflicted = $runtime.Data.Conflicted
            Untracked  = $runtime.Data.Untracked
        }
    } `
    git status --porcelain=v2 --branch

$r.Data   # Branch master, Changed 1, Conflicted 0, Untracked 1
```

With the Git companion loaded (it depends on Core), the same question needs no callback. The module selects its own handler for `git status`:

```powershell
Import-Module ./FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1

# Run inside an existing Git repository.
$result = quiet -AsObject git status
$result.Outcome
$result.Execution
$result.Completeness
$result.Data

ConvertTo-QuietJson $result -MaxOutputBytes 4096
```

The module's handler goes further than this sketch: it reads NUL-delimited porcelain v2 and reports the branch, HEAD, initial or detached state, divergence from local references, entries and counters, and it keeps the short forms and pathspec filters. QuietCli options precede `git`; Git arguments follow it. To build a module for another executable, see [Companion modules](README-modules.md).

## Go deeper

| Topic | Read |
| --- | --- |
| Outcome, completeness, callbacks, reusable scripts | [Streaming, callbacks and results](README-streaming.md) |
| Capturing native evidence and analyzing it later | [Recall](README-recall.md) |
| Integrated and isolated engine, pipes and PTY, platforms | [Hosting and native transports](README-hosting.md) |
| YAML configuration and the single environment override | [Configuration](README-configuration.md) |
| What is measured, stored and never stored | [Measurements and privacy](README-measurements.md) |
| Using QuietCli with Codex, Claude Code or another agent | [QuietCli with AI agents](README-agents.md) |
| Registered handlers and writing a module | [Companion modules](README-modules.md) |
| Working from a source checkout, building | [Development](README-development.md) |
| Property, fuzzing and mutation campaigns, CI matrix | [Tests and qualification](README-qualification.md) |
| Packaging, publication gates, repository layout | [Repository and distribution](README-distribution.md) |
| Repository rules for contributors and agents | [AGENTS.md](AGENTS.md) |

## License

QuietCli is distributed under the MIT license. Each module directory ships its own `LICENSE` file, for example [Core](FrenchExDev2.QuietCli.Core.PoSh/LICENSE).
