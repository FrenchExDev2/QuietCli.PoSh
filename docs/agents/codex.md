# Using QuietCli with Codex

QuietCli turns native output into caller-local business objects. Codex can keep those objects
inside a persistent PowerShell process and request bounded representations when needed. This
avoids repeated profile/module initialization and unnecessary native executions.

This guide describes the **development checkout**, not a promise that every feature exists in
the published `0.1.0` package. Start with the [repository README](../../README.md), the supplied
[AGENTS.md](../../AGENTS.md) and the [Core README](../../FrenchExDev2.QuietCli.Core.PoSh/README.md).
Use PowerShell Core 7.6+ and existing matching binaries. Importing Core does not compile C#.

## Give Codex the supplied agent instructions

The instruction filename is **`AGENTS.md`**, plural. Codex discovers instructions along the
path from the project root to its working directory, with global guidance and directory
overrides. An arbitrary `agent.md` or this `codex.md` is not automatically an instruction file.
See the [official instruction-discovery documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

When working in this monorepo, keep its supplied `AGENTS.md` and start Codex in the intended
project directory. If Codex starts in an enclosing workspace, explicitly ask it to read this
monorepo's instructions before working here. In another repository, merge the relevant
QuietCli execution policy into that repository's existing `AGENTS.md`; adapt paths and preserve
its own conventions. The supplied file also contains rules for maintaining QuietCli itself,
which should not be copied blindly into an unrelated project.

The following additional block makes persistent-shell use explicit. Replace the path once:

```markdown
## QuietCli execution with Codex

- Read the selected QuietCli checkout's AGENTS.md, README.md and Core README before use.
- Selected checkout: C:/path/to/FrenchExDev2.QuietCli.PoSh.
- Use PowerShell Core 7.6+ with its normal profile and UTF-8 initialization.
- Use exec_command with login: true. For interactive persistence, use tty: true,
  keep the process alive, retain its session_id and use write_stdin for later commands.
- Prefer one initialized PowerShell process for sequential work. Retain its PID,
  a session identity and named QuietCli results; verify them before dependent work.
- Import the exact local Core manifest once per process and check its loaded path.
  Load the matching Git module only for its business handlers. Explicit Core callbacks
  may analyze Git directly without the Git companion, as in the Core benchmark.
- Route native commands through quiet. Define the question, required business data
  and smallest useful delivery before executing. Read executable help or official docs.
- Keep -AsObject results in variables. Inspect Outcome, Execution, Completeness,
  Error and business scope. Deliver bounded views using module-qualified Core cmdlets.
- Keep engine hosting at Auto. Rebuild only missing/stale binaries through the
  documented workspace build, then use a fresh process for rebuilt assemblies.
- Wait for each command's completion marker before sending dependent work.
  If the session is lost, initialize a new process; never replay a mutation automatically.
- Keep the repository's visible test-monitor, CI orchestration and permission rules.
```

Ask Codex to identify the instruction files it loaded. Start a new Codex run when changing
instruction files so discovery is refreshed. `AGENTS.md` guides the agent's choices; it does
not itself retain a process, install a hook or change tool permissions.

## Initialize the selected Core once

Run this in the PowerShell process that Codex will reuse, from the QuietCli monorepo root:

```powershell
$quietRoot = (Get-Location).Path
$coreManifest = Join-Path $quietRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
$loadedCore = Get-Module FrenchExDev2.QuietCli.Core.PoSh
if (!$loadedCore -or $loadedCore.ModuleBase -ne (Split-Path $coreManifest -Parent)) {
    Import-Module $coreManifest -ErrorAction Stop
}
$loadedCore = Get-Module FrenchExDev2.QuietCli.Core.PoSh
if ($loadedCore.ModuleBase -ne (Split-Path $coreManifest -Parent)) {
    throw 'UnexpectedQuietCliCorePath'
}
$loadedCore.Path
$PID
```

Keep modules with overlapping command names in separate processes. Do not load legacy QuietCli
or archived OPumper modules into this session. Existing matching `lib/` binaries need no SDK
or rebuild. If a build is necessary, follow `scripts/Build-Workspace.ps1`, then open a fresh
PowerShell process; reimporting cannot replace an already loaded .NET assembly reliably.

Leave `engine.hosting` at `Auto`: a CLR 10 host selects the integrated `net10.0` build;
CLR 11+ selects the compatible `net11.0` build. Never load a .NET 11 assembly into CLR 10.
Explicit `Process` hosting needs the pinned .NET 11 runtime. After actual engine use,
`Get-QuietEngine` identifies the selected host; importing the module alone leaves it lazy.

Use normal profiles (`login: true` in the exposed Codex execution tool) and reuse their UTF-8
initialization. If a deliberately isolated process has no profile initialization, initialize
console input, console output and `$OutputEncoding` with UTF-8 before any exchange.

## Select an ephemeral configuration before first use

`QUIETCLI_CONFIG_DIRECTORY` selects the **directory containing `config.yaml`**. It is the sole
product configuration environment override. Legacy database, hosting and tracking environment
variables are not configuration APIs. See the [configuration contract](../configuration.md).

For an owned disposable session, create the full default template, then put its storage inside
that directory. Relative YAML paths resolve against the configuration file's directory:

```powershell
$env:QUIETCLI_CONFIG_DIRECTORY = Join-Path ([IO.Path]::GetTempPath()) ('QuietCli2/codex-' + [guid]::NewGuid().ToString('N'))
$configurationFile = New-QuietCliConfiguration -Confirm:$false
$configurationText = [IO.File]::ReadAllTextAsync($configurationFile.FullName, [Text.Encoding]::UTF8).GetAwaiter().GetResult()
$configurationText = [regex]::Replace($configurationText, '(?m)^  database:.*$', '  database: gains.sqlite')
$configurationText = [regex]::Replace($configurationText, '(?m)^  root:.*$', '  root: recall')
[void][IO.File]::WriteAllTextAsync($configurationFile.FullName, $configurationText, [Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
Import-QuietCliConfiguration -Path $configurationFile.FullName | Out-Null
$effectiveConfiguration = Get-QuietCliConfiguration
$effectiveConfiguration.Path
```

This preserves the default `Auto` hosting, telemetry and tokenizer settings while isolating
database and possible Recall files. Selecting a configuration directory alone does not relocate
default storage paths. No capture is enabled by this setup. Temporary storage is not a durable
archive; retain the files while a live engine or saved evidence still needs them.

Do this before the first engine starts. Changing the directory variable does not reload an
existing snapshot. To intentionally switch an active engine's database or hosting, finish its
work, call `Stop-QuietEngine`, then explicitly reload the configuration. User configuration and
profiles need no changes. In a shared caller process, restore the previous environment value
when finished; a dedicated process can simply exit after disposing its engine.

## Keep a PowerShell process active across Codex tool calls

Three identities are different: a Codex conversation, an execution-tool `session_id` and the
PowerShell process PID. Conversation continuity does not preserve PowerShell variables.
Ordinary completed `exec_command` calls do not share PowerShell state.

When the exposed tools support it, Codex can start a long-lived interactive process with
`exec_command`, retain the returned `session_id`, then send input or poll with `write_stdin`.
This mechanism is described in the [official Codex tool guidance](https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide).
Tool names and availability depend on the client; these are agent tools, not PowerShell cmdlets.

No Codex hook is required for this workflow. The agent must actually keep the shell alive and
reuse the same handle. A tool call's waiting/yield interval is not proof that a command ended.
Neither the handle nor the process is guaranteed to survive a client restart or reconnection.
This workflow does not attach to an arbitrary terminal already open in VS Code.

A minimal trusted-command loop can be supplied as the `cmd` body of `exec_command`. It keeps
PowerShell waiting after each command, dot-sources agent-authored code in the same scope and
emits a correlated completion marker. The input is Codex's own command channel, not native
output or an external data source. Reserve the `$codex*` variable names for loop control:

```powershell
$global:CodexPowerShellToken = [guid]::NewGuid().ToString('N')
[Console]::Out.WriteLine('@@CODEX_READY@@' + $global:CodexPowerShellToken + ':' + $PID)
try {
    while ($null -ne ($codexLine = [Console]::In.ReadLineAsync().GetAwaiter().GetResult())) {
        if ($codexLine -ceq '__CLOSE_CODEX_PWSH__') { break }
        $codexRequest = $null
        $codexRequestId = $null
        $codexSucceeded = $false
        try {
            $codexRequest = $codexLine | ConvertFrom-Json -ErrorAction Stop
            $codexRequestId = [string]$codexRequest.Id
            if (!$codexRequest.Id -or $codexRequest.Code -isnot [string]) {
                throw 'InvalidCodexPowerShellRequest'
            }
            . ([scriptblock]::Create($codexRequest.Code))
            $codexSucceeded = $true
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorAction Continue
        }
        $codexCompletion = @{ Id = $codexRequestId; Succeeded = $codexSucceeded; ProcessId = $PID; Token = $global:CodexPowerShellToken }
        [Console]::Out.WriteLine('@@CODEX_DONE@@' + (ConvertTo-Json $codexCompletion -Compress))
    }
} finally {
    if (Get-Module FrenchExDev2.QuietCli.Core.PoSh) { Stop-QuietEngine }
}
```

Start that loop through `exec_command` with `tty: true`, `login: true`, the selected workspace
as `workdir` and an output budget large enough to receive the markers. No nested `pwsh` is
needed when the execution tool already runs PowerShell. Send newline-terminated single-line
JSON requests through `write_stdin`, using the actual returned session identifier. For example:

```json
{"session_id":12345,"chars":"{\"Id\":\"probe-1\",\"Code\":\"$global:ProbeCounter = 41; $PID\"}\n"}
```

After receiving the matching `@@CODEX_DONE@@` marker, send:

```json
{"session_id":12345,"chars":"{\"Id\":\"probe-2\",\"Code\":\"$global:ProbeCounter++; $global:ProbeCounter; $PID\"}\n"}
```

Expect `42`, the same PID and the same token. Then initialize Core and configuration through
that channel and keep using it. Encode multiline commands with a JSON serializer rather than
hand-escaping them. The loop is an integration example, not a QuietCli product API. Its marker
reports whether PowerShell code threw; the QuietCli envelope remains authoritative for native
failure and source completeness. Nonterminating PowerShell errors require explicit handling.

Poll if a marker has not arrived; do not submit dependent commands concurrently into the same
shell. A truncated response does not establish completion. Preserve the session identifier,
PID, token, loaded module path and retained variable names in task context. If those identities
cannot be verified, initialize a fresh process and reconstruct read-only state as needed.
Do not automatically repeat a mutation whose previous effect is unknown. Close an owned idle
session with `__CLOSE_CODEX_PWSH__` followed by a newline and verify process termination.

## Execute through QuietCli and keep the result local

Before execution, identify the question, the required business result and the smallest useful
delivery. Read the executable's help or official format documentation before writing a parser.
Facade options precede the executable; native arguments follow it verbatim.

For documented Git business semantics, import the matching local Git module once:

```powershell
Import-Module (Join-Path $quietRoot 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1') -ErrorAction Stop
$repository = $quietRoot
$result = quiet -AsObject -C codex-status -WorkingDirectory $repository git status
```

Core can also analyze a native command directly through dedicated callbacks. The following
summary deliberately counts machine-output bytes and NUL records; it does not interpret the
records as a complete business status model. Porcelain v1 rename/copy entries have an extra
NUL-delimited path, so a record count must not be presented as a changed-file count:

```powershell
$repository = $quietRoot
$result = quiet -AsObject -C codex-status-bytes -WorkingDirectory $repository -StdoutMode Bytes -Data @{ Bytes = 0L; Records = 0L } -Output {
    param($event, $runtime)
    if ($event.Stream -eq 'stdout') {
        $runtime.Data.Bytes += $event.ByteCount
        foreach ($value in $event.Bytes) {
            if ($value -eq 0) { $runtime.Data.Records++ }
        }
    }
} -Complete {
    param($runtime)
    [pscustomobject]@{ StdoutBytes = $runtime.Data.Bytes; NulRecords = $runtime.Data.Records }
} -FilePath git -ArgumentList @('status', '--porcelain=v1', '-z', '--untracked-files=all')
```

This direct path requires only Core. `-Output` must emit no incidental pipeline output; retain
only required business data in `runtime.Data`. `-Complete` returns at most one value; use the
unary comma when returning an array as one value. Unsupported commands without a compatible
handler or explicit analysis callbacks are rejected before business execution, except for the
explicit recording path described in the Recall contract.

Check the actual result before using it, and expose only a bounded delivery to Codex:

```powershell
if ($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count) {
    FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $result -MaxItems 8 -MaxOutputBytes 4096
    throw 'QuietCliExecutionOrAnalysisIncomplete'
}
$execution = $result.Execution
$completeness = $result.Completeness
FrenchExDev2.QuietCli.Core.PoSh\Out-QuietResult $result -MaxItems 8 -MaxOutputBytes 4096
```

`-AsObject` keeps `Data` local without enumerating or serializing it. Assigning `$result` in
the persistent shell makes it available for subsequent decisions without rerunning Git.
Converting it later with different bounds changes the delivery, not the observed repository
state. Run a new observation when freshness matters and the repository may have changed.

Use `ConvertTo-QuietJson` when the actual delivery string is needed. Avoid serializing the
whole envelope with general-purpose `ConvertTo-Json` or dumping all business data into tool
output. Native output is streamed through bounded buffers by default; it is not automatically
captured. Result retention keeps the selected business objects, not an implicit raw transcript.

## Session loss, Recall and evidence

PowerShell variables and `-AsObject` results disappear when their process exits. SQLite holds
metadata and measurements, not the business objects or native output needed to recreate them.
Restarting a conversation or using the same configuration directory does not restore `$result`.

When evidence must survive a process loss, explicitly choose [Recall](../recall.md): `-Recall`
retains bounded in-memory native evidence, while `-SaveRecall` records a durable journal and
allows later analysis by `RecallId`. Offline analysis does not rerun the original executable.
These opt-in features are distinct from shell persistence and from legacy RECORD APIs.

## Measure gains and run tests

The [persistent-shell benchmark](../../FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-PersistentShellBenchmark.ps1)
compares fresh processes, sequential requests to one persistent process and repeated delivery
of one retained result. It uses a copied disposable Git fixture, private default configurations
and dedicated Core `-Output`/`-Complete` callbacks. Neither Git companion is loaded by the subject.

From the monorepo root:

```powershell
./FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-PersistentShellBenchmark.ps1 -Iterations 3 -CommandCounts '1,5,10'
```

This launcher opens the required visible monitor and saves reports outside the checkout.
Read the [benchmark definitions and limitations](../../FrenchExDev2.QuietCli.Core.Tests.PoSh/README.md#persistent-powershell-benchmark)
before interpreting results. Compare paired samples with the same host, sources, configuration
and workload. The measurements include local process/profile/import/pipe/shutdown costs, but
exclude Codex tool transport and model time. Retained-result savings also avoid native work;
report them separately from persistent-shell savings. No universal acceleration factor follows
from one local run, and three repetitions are insufficient to characterize tail latency.

`Get-QuietCliGain` reports measured native/delivery volumes and available overhead measurements.
It does not replace the external process-startup comparison. Unknown native token counts and
unmeasured delivery sizes remain unknown; `-AsObject` alone establishes no serialization gain.

Native business calls keep using `quiet`. Repository CI/build orchestration retains the
engine-independent `scripts/Ci.Process.ps1` path, and read-only streaming monitors retain their
documented exception. Use existing monitored launchers for tests; test strategy, qualification
scope and release gates remain those of the supplied `AGENTS.md`. QuietCli grants no additional
permission for network access, retries, hook installation, profile edits, pushes or publication.
