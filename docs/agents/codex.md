# Using QuietCli with Codex

QuietCli turns native output into caller-local business objects. Codex can retain those objects
inside one PowerShell process and request bounded representations when needed. This avoids
repeated profile/module initialization and unnecessary native executions.

Use PowerShell Core 7.6+ with QuietCli Core installed. Git is required for the Git examples.
No Codex hook or profile edit is needed. The instructions below use the installed module's
public commands and the [production agent instructions](AGENTS.md).

## Generate the project's AGENTS.md after installation

Open PowerShell in the project that Codex will work on:

```powershell
# Objective: Install QuietCli's production instructions in the selected project.
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$repository = (Get-Location).Path
$installation = Add-QuietAgentInstruction -Path $repository -Agents
$installation.Files | Select-Object Path, ReferencePath, Status
```

`Add-QuietAgentInstruction` copies the installed production `AGENTS.md` and `SKILL.md` into
`.skills` and creates or updates only its delimited QuietCli reference block in the project's
`AGENTS.md`. Existing project instructions outside that block are preserved. Repeating the
same command leaves unchanged files untouched. Use `-WhatIf` to preview the operation and
`-DocumentDirectory` to choose another copy directory. For example:

```powershell
# Objective: Preview project instruction installation without writing files.
$preview = Add-QuietAgentInstruction -Path $repository -Agents -DocumentDirectory instructions/quietcli -WhatIf
$preview.Files | Select-Object Path, ReferencePath, Status

# Objective: Read the production rules distributed with the installed module.
$productionInstructions = Get-QuietAgentInstruction
```

These cmdlets manage files and return text or metadata; they do not start a native process or
return a QuietCli native execution envelope. `-Claude` and `-Skills` optionally select
`CLAUDE.md` and `SKILLS.md`; neither registers a native Codex skill. The source of the copied
rules is the [production AGENTS.md](AGENTS.md), not QuietCli's repository maintenance file.

Codex's instruction filename is **`AGENTS.md`**, plural. It discovers instructions from the
project root toward its working directory, together with global guidance and overrides.
See the [official instruction-discovery documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
Start Codex in the selected project after generating the instructions and ask it to identify
the files it loaded. This guide itself is reference documentation, not an automatically loaded
instruction file. `AGENTS.md` guides tool use; it does not keep a process alive or change permissions.

## Initialize the installed Core once per process

Run this inside the PowerShell process that Codex will reuse:

```powershell
# Objective: Load the installed Core and retain its identity for subsequent work.
Import-Module FrenchExDev2.QuietCli.Core.PoSh -ErrorAction Stop
$core = Get-Module FrenchExDev2.QuietCli.Core.PoSh
$core.Path
$PID
$repository = (Get-Location).Path
```

Reuse that module and its `quiet` alias. Keep modules with overlapping public command names in
separate processes; do not load legacy QuietCli or archived OPumper modules into this session.
An installed module includes its runtime resources; importing it does not compile C#.

Leave `engine.hosting` at `Auto`: a CLR 10 host selects the integrated `net10.0` build;
CLR 11+ selects the compatible `net11.0` build. Never load a .NET 11 assembly into CLR 10.
Explicit `Process` hosting requires its matching .NET runtime. After engine use,
`Get-QuietEngine` identifies the selected host; importing Core alone leaves it lazy.

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
PID, token, loaded installed-module path and retained variable names in task context. If those identities
cannot be verified, initialize a fresh process and reconstruct read-only state as needed.
Do not automatically repeat a mutation whose previous effect is unknown. Close an owned idle
session with `__CLOSE_CODEX_PWSH__` followed by a newline and verify process termination.

## Execute through QuietCli and keep the result local

Before execution, identify the question, the required business result and the smallest useful
delivery. Read the executable's help or official format documentation before writing a parser.
Facade options precede the executable; native arguments follow it verbatim.

For documented Git business semantics, import the installed Git companion once:

```powershell
Import-Module FrenchExDev2.QuietCli.Git.PoSh -ErrorAction Stop
$repository = (Get-Location).Path
$result = quiet -AsObject -C codex-status -WorkingDirectory $repository git status
```

Core can also analyze a native command directly through dedicated callbacks. The following
summary deliberately counts machine-output bytes and NUL records; it does not interpret the
records as a complete business status model. Porcelain v1 rename/copy entries have an extra
NUL-delimited path, so a record count must not be presented as a changed-file count:

```powershell
$repository = (Get-Location).Path
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

## Measure gains

Compare the same workload using fresh PowerShell processes, repeated requests to one process
and repeated delivery of an already retained result. Report the third optimization separately:
it avoids native work as well as initialization. Include process startup, profile and module
loading in the total duration; a stopwatch around `quiet` alone misses part of that cost.
Retain raw paired observations, host identities, sample counts and configuration. Local pipe
measurements do not include Codex tool transport or model time.

The [reproducible benchmark](../../FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-PersistentShellBenchmark.ps1)
and its [measurement definitions](../../FrenchExDev2.QuietCli.Core.Tests.PoSh/README.md#persistent-powershell-benchmark)
provide a separate validation tool with a disposable Git fixture, private default configurations,
Core callbacks and a visible monitor. It is a source-distributed benchmark, not an installed
Core cmdlet. A local run does not establish a universal acceleration factor.

`Get-QuietCliGain` reports measured native/delivery volumes and available overhead measurements.
It does not replace the external process-startup comparison. Unknown native token counts and
unmeasured delivery sizes remain unknown; `-AsObject` alone establishes no serialization gain.

Use the host project's existing monitored launchers for tests and its documented CI orchestration.
QuietCli grants no additional permission for network access, retries, hook installation, profile
edits, pushes or publication.
