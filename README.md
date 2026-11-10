<p align="center">
  <img src="./icons/logo.png" alt="QuietCli logo" width="150px" />
</p>

# QuietCli

**QuietCli** (pronounced *Quietly*) runs native command-line tools from PowerShell Core 7.6+ and turns their noisy output into small, typed, trustworthy results. It is built for AI agents and developer tooling, where every byte of terminal text costs time, context and attention.

A C# engine starts the native process and streams its output once, through bounded buffers. Your own PowerShell callbacks, which stay in your process, turn that stream into business data. You then inspect the data directly or deliver a bounded JSON/YAML view of it.

Start here: [Gallery installation](#from-powershell-gallery) · [.NET SDK and global.json](README-dotnet-and-global-dot-json.md) · [Local checkout, build and first command](#from-a-source-checkout) · [Git companion](FrenchExDev2.QuietCli.Git.PoSh/README.md#quick-start).

Browse the [documentation index](docs/README.md) for usage guides, technical contracts, agent instructions, CI, profiling and dated audit evidence.

## Resources

[Resource preparation and integrity](README-resources.md) explains pinned payloads, on-demand automation preparation and optional GitHub caching. The [generated resource inventory](docs/resources/README.md) maps declared files to source consumers. Resource documentation and the [complete script preview review](docs/scripts/preview-support.md) are checked by the shared workspace/commit pipeline.

> **Status: preview (`0.2.0-preview`).** The engine is under active development and its API may change. The Git companion module is a work in progress and is presented here as an example only. Nothing in this repository is a release qualification unless a report says so; see [Tests and qualification](README-qualification.md).

## How projection works

QuietCli's engine streams native output once. Your own code decides what that stream becomes, split across two callbacks with different jobs:

- **`-Output`** runs once per stream event (one line of stdout or stderr). It never produces the result itself; its only job is to accumulate state into `$runtime.Data` — counters, lists, parsed fields. Nothing else leaves this callback.
- **`-Complete`** runs once, after the stream ends. It reads `$runtime.Data` and returns the one object the call delivers — the actual business projection. This is where you decide what the command means in business terms: a status summary, a count, a list of typed records.

In short: `-Output` folds raw events into accumulated state, `-Complete` projects that state into the business output you asked for. A companion module (see the Git example below) just supplies a ready-made `-Output`/`-Complete` pair — a handler — for one executable, so you don't write the fold or the projection yourself.

Callbacks can also call `$runtime.Emit($event)` to notify `-Listeners` without producing pipeline output.
Events are transient by default. Explicit `-CollectEvents` retains them in order on `$runtime.Events`,
lets `-Complete` read them, and adds a snapshot under the finished result's top-level `Events` field,
alongside `Data`. Without this switch, the runtime list stays empty and the result omits `Events`.
`-UI` exposes a separate live presentation surface. The
[streaming guide](README-streaming.md) explains these contracts, and the
[Vagrant companion](FrenchExDev2.QuietCli.Vagrant.PoSh/README.md) uses both for per-machine progress.

```powershell
$r = quiet -AsObject -CollectEvents -C sdk-version -WorkingDirectory (Get-Location).Path `
    -RecordDelimiter "`n" -Data @{ Version = $null } `
    -Listeners {
        param($event, $runtime)
        Write-Host "SDK version emitted: $event"
    } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            $runtime.Data.Version = $event.Text.Trim()
            $runtime.Emit($runtime.Data.Version)
        }
    } `
    -Complete {
        param($runtime)
        [pscustomobject]@{ SdkVersion = $runtime.Data.Version; Emitted = $runtime.Events }
    } `
    dotnet --version
```

`-Listeners` accepts one scriptblock or an array of scriptblocks and runs each one synchronously as
`$runtime.Emit(...)` is called, including without collection. This example explicitly collects the
values for `-Complete`; omit `-CollectEvents` when only live notification or UI progress is needed.

## Roadmap: from a script to an ecosystem

QuietCli is meant to grow along one path, each step adding reuse without discarding the one before it:

1. **`pwsh` callback** — inline `-Output`/`-Complete` scriptblocks at the call site. Fastest to write, not reusable.
2. **Parameterizable script** — a standalone `.ps1` projection file, loaded and reused across calls and projects without a full module.
3. **Module** — a companion module (like the Git module) with registered handlers, tests, and a documented coverage/limits matrix.
4. **Ecosystem** — a family of modules sharing conventions, scaffolding and qualification tooling.

Each step up this path can opt into a stricter dev pipeline style — Minimal, Standard (basic tests), or Hardened (property, fuzz and mutation testing) — so a one-off script stays light while a published module can be qualified to the same rigor as QuietCli's own handlers. See [Tests and qualification](README-qualification.md) for what "qualified" means today.

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

## .NET SDK and global.json

The [.NET SDK and global.json guide](README-dotnet-and-global-dot-json.md) explains release and image availability checks, verified portable SDK installation with its runtimes, optional Docker/Podman image downloads, and SDK pin updates with backups. All operations support standard `-WhatIf`/`-Confirm`.

From this checkout:

```powershell
$report = ./scripts/Test-DotNetReadiness.ps1
./scripts/Install-DotNet.ps1 -Channel 11.0 -UpdateGlobalJson -ActivateSession -WhatIf
```

Use `scripts/Update-DotNetGlobalJson.ps1` for a separate SDK pin update. See the guide for exact versions, preview/RC selection, container configuration and complete installation commands.

## How to install

### From PowerShell Gallery

Install the `QuietCli` package, which provides Core, then import it in the current session:

```powershell
Install-PSResource -Name QuietCli -Prerelease -Repository PSGallery -Scope CurrentUser
Import-Module QuietCli
```

`-Prerelease` includes available preview packages; omit it to select stable releases only. See [package installation](docs/README-PSGallery.md) for publication status, runtime requirements and platform notes.

### From a source checkout

For container-based source checks, `./scripts/Initialize-CiEnvironment.ps1 -Target Local` writes the
checkout's ignored runtime preset. Explicit `-ContainerRuntime` overrides `.env`; otherwise discovery
is the fallback. See [local/GitHub environment initialization](docs/ci/environment.md).

Use PowerShell Core 7.6+, Git and the exact .NET SDK pinned in `global.json` (currently `11.0.100-rc.3.26522.148`). Build before importing the local modules. Close sessions that already loaded this checkout's assemblies before rebuilding.

For SDK/runtimes installation, container image downloads and SDK pin updates, see [the .NET and global.json guide](README-dotnet-and-global-dot-json.md).

**1. Check out and build.**

The commands start in a parent directory of your choice and clone the whole monorepo into `$HOME/src/QuietCli`. For an existing checkout, set `$checkout` to its root and skip the clone. Git performs this initial bootstrap before local `quiet` is available; the build script uses the engine-independent process helper.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
New-Item -ItemType Directory -Path (Split-Path $checkout -Parent) -Force | Out-Null
git clone --branch develop https://github.com/FrenchExDev2/QuietCli.PoSh.git $checkout
if ($LASTEXITCODE -ne 0) { throw 'CheckoutFailed' }
Set-Location $checkout
./scripts/Initialize-Workspace.ps1 -Restore
./scripts/Build-Workspace.ps1
```

All paths are relative to the monorepo root. `-Restore` verifies the committed source lock; on an intentionally edited checkout, `./scripts/Initialize-Workspace.ps1` without `-Restore` refreshes the local lock. A successful build creates the compiled engine and companion binaries; it does not publish or install a Gallery package.

**2. Import and run in a fresh session.**

**Open a new PowerShell Core 7.6+ session with its normal profile**, then paste the following block. Reassigning `$checkout` makes the new session independent of variables from the build session.

```powershell
$checkout = Join-Path $HOME 'src/QuietCli'
Set-Location $checkout
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Get-Alias quiet

$r = quiet -AsObject -C sdk-version -WorkingDirectory (Get-Location).Path `
    -RecordDelimiter "`n" -Data @{ Version = $null; Records = 0 } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            $runtime.Data.Version = $event.Text.Trim()
            $runtime.Data.Records++
        }
    } `
    -Complete {
        param($runtime)
        if ($runtime.Data.Records -ne 1) { throw 'ExpectedOneSdkVersion' }
        [pscustomobject]@{ SdkVersion = $runtime.Data.Version }
    } `
    dotnet --version
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteSdkVersion'
}
Out-QuietResult $r -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

YAML excerpt; invocation IDs and other envelope metadata are omitted. The version shown is the SDK selected in this checkout. `-Output` reads one native record; `-Complete` creates `{ SdkVersion }`. `-AsObject` keeps that result local, and `Out-QuietResult -AsYaml` formats the same result without executing `dotnet` again.

```yaml
"Outcome": "Success"
"Context": "sdk-version"
"Data":
  "SdkVersion": "11.0.100-rc.3.26522.148"
"Completeness":
  "Source": true
  "Analysis": true
```

The source manifest above loads the local Core project. The public Gallery module is named `QuietCli`; its installation uses `Install-PSResource -Name QuietCli` and `Import-Module QuietCli`.

For source automation, [`scripts/Invoke-Quiet.ps1`](docs/scripts/Invoke-Quiet.md)
loads that exact local Core module before invoking your block in the same process:

```powershell
$result = ./scripts/Invoke-Quiet.ps1 -Code {
    param($runtime)
    $runtime.Data.Result = quiet -AsObject -Complete { param($native) $native.Data } dotnet --version
    $runtime.Data.Result
}
```

Supply `-Output`/`-Complete` callbacks for your business analysis or explicitly import
a compatible companion. The block receives fresh `Data` and `State` hashtables, or
your own `-Runtime` object; this is separate from native callback runtimes.
`-WhatIf` skips both import and block execution. See the
[launcher contract and complete projection example](docs/scripts/Invoke-Quiet.md).

## How to use

For a Gallery installation, import `QuietCli` and run this SDK-version contract. For a local build, the checkout recipe above already imports the source manifest and executes the same example.

```powershell
Import-Module QuietCli -ErrorAction Stop

$r = quiet -AsObject -C sdk-version -WorkingDirectory (Get-Location).Path `
    -RecordDelimiter "`n" -Data @{ Version = $null; Records = 0 } `
    -Output {
        param($event, $runtime)
        if ($event.Stream -eq 'stdout') {
            $runtime.Data.Version = $event.Text.Trim()
            $runtime.Data.Records++
        }
    } `
    -Complete {
        param($runtime)
        if ($runtime.Data.Records -ne 1) { throw 'ExpectedOneSdkVersion' }
        [pscustomobject]@{ SdkVersion = $runtime.Data.Version }
    } `
    dotnet --version
if ($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count) {
    throw 'IncompleteSdkVersion'
}
Out-QuietResult $r -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

YAML excerpt; invocation IDs and other envelope metadata are omitted. The version shown is the SDK selected in this checkout. `-Output` reads one native record; `-Complete` creates `{ SdkVersion }`. `-AsObject` keeps that result local, and `Out-QuietResult -AsYaml` formats the same result without executing `dotnet` again.

```yaml
"Outcome": "Success"
"Context": "sdk-version"
"Data":
  "SdkVersion": "11.0.100-rc.3.26522.148"
"Completeness":
  "Source": true
  "Analysis": true
```

The raw native output is a version string. The completed business object has one `SdkVersion` property; the YAML envelope adds execution outcome and completeness. Reject an incomplete result before using `Data`. QuietCli options precede the executable, and native arguments follow verbatim.

See [streaming, callbacks and results](README-streaming.md) for callback rules and [a non-Git example](docs/agents/non-git-example.md) for a larger parser.

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
Import-Module QuietCli -ErrorAction Stop
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

Out-QuietResult $r -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

Illustrative YAML excerpt for branch `develop`, one modified tracked file and one untracked file. The callbacks count the selected porcelain records; `-Complete` defines these four business fields.

```yaml
"Outcome": "Success"
"Data":
  "Branch": "develop"
  "Changed": 1
  "Conflicted": 0
  "Untracked": 1
```

With the Git companion loaded (it depends on Core), the same question needs no callback. The module selects its own handler for `git status`:

```powershell
Import-Module ./FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1 -ErrorAction Stop
Import-Module ./FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1 -ErrorAction Stop

# Run from the built checkout root; select which handler fields to deliver.
$statusView = {
    param($data, $budget)
    [pscustomobject]@{
        Branch = $data.Branch
        Staged = $data.Counts.Staged
        Unstaged = $data.Counts.Unstaged
        Untracked = $data.Counts.Untracked
    }
}
$result = quiet -AsObject -WorkingDirectory (Get-Location).Path -Projection $statusView git status
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count) { throw 'IncompleteGitStatus' }
Out-QuietResult $result -AsYaml -MaxItems 5 -MaxOutputBytes 4096
```

For the same illustrative repository, the handler's projected YAML is:

```yaml
"Outcome": "Success"
"Data":
  "Branch": "develop"
  "Staged": 0
  "Unstaged": 1
  "Untracked": 1
```

The handler builds the complete local status object; `$statusView` selects the delivered fields without changing `$result.Data`. Counts depend on the selected repository.

The module's handler goes further than this sketch: it reads NUL-delimited porcelain v2 and reports the branch, HEAD, initial or detached state, divergence from local references, entries and counters, and it keeps the short forms and pathspec filters. QuietCli options precede `git`; Git arguments follow it. To build a module for another executable, see [Companion modules](README-modules.md).

## Go deeper

The [documentation index](docs/README.md) groups all guides and technical references by topic. Dated audits record their own revisions and executed scopes; they do not qualify a later revision.

| Topic | Read |
| --- | --- |
| Package installation, runtime and platform requirements | [PowerShell Gallery installation](docs/README-PSGallery.md) |
| Outcome, completeness, callbacks, reusable scripts | [Streaming, callbacks and results](README-streaming.md) |
| Capturing native evidence and analyzing it later | [Recall](README-recall.md) |
| Integrated and isolated engine, pipes and PTY, platforms | [Hosting and native transports](README-hosting.md) |
| YAML configuration and the single environment override | [Configuration](README-configuration.md) |
| What is measured, stored and never stored | [Measurements and privacy](README-measurements.md) |
| Using QuietCli with Codex, Claude Code or another agent | [QuietCli with AI agents](README-agents.md) |
| Production agent rules, examples and troubleshooting | [Agent documentation index](docs/agents/README.md) |
| Registered handlers and writing a module | [Companion modules](README-modules.md) |
| Working from a source checkout, building | [Development](README-development.md) |
| Property, fuzzing and mutation campaigns, CI matrix | [Tests and qualification](README-qualification.md) |
| Performance evidence and reproducible profiling campaigns | [Core performance evidence](FrenchExDev2.QuietCli.Core.PoSh/PERFORMANCES.md), [Run profiles](docs/README-run-profiles.md) |
| Packaging, publication gates, repository layout | [Repository and distribution](README-distribution.md) |
| Preview identities, artifact preparation and publication | [Preview versions and GitHub publication](docs/README-preview-releases.md) |
| Repository rules for contributors and agents | [AGENTS.md](AGENTS.md) |

## License

QuietCli is distributed under the MIT license. Each module directory ships its own `LICENSE` file, for example [Core](FrenchExDev2.QuietCli.Core.PoSh/LICENSE).

Each business module also ships its own `LICENSE_CREDITS.md`, declaring the third-party license(s) its native dependency uses, with reference links. The root [CREDITS.md](CREDITS.md) is generated from them by [`scripts/Sync-Credits.ps1`](scripts/Sync-Credits.ps1); see [AGENTS.md](AGENTS.md) for the module contract.

<!-- credits:begin -->
## Credits

This document is covered by the mandatory [CREDITS.md](CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).
<!-- credits:end -->
