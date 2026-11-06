# Keeping one PowerShell process alive across agent tool calls

QuietCli results (`-AsObject`) are ordinary PowerShell objects. They survive only as long as the
PowerShell process that created them. This guide describes the mechanism for Codex's
`exec_command` / `write_stdin` tools. Claude Code has no equivalent long-lived channel; see
[claude.md](claude.md) for what to do there.

Three identities are different: an agent conversation, an execution-tool `session_id` and the
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

## The command loop

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

## Operating rules

- Poll if a marker has not arrived; do not submit dependent commands concurrently into the same shell.
- A truncated response does not establish completion.
- Preserve the session identifier, PID, token, loaded installed-module path and retained variable
  names in task context. If those identities cannot be verified, initialize a fresh process and
  reconstruct read-only state as needed.
- Do not automatically repeat a mutation whose previous effect is unknown.
- Close an owned idle session with `__CLOSE_CODEX_PWSH__` followed by a newline and verify process termination.
- When evidence must outlive the process, use Recall (`-SaveRecall`); see [../recall.md](../recall.md).
