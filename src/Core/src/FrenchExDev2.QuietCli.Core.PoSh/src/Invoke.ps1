function Invoke-QuietCli {
    <#
.SYNOPSIS
Executes a streaming command or registered handler; options precede the binary.
    .DESCRIPTION
    quiet [-Mode Agent|User|Script] [-AsObject|-AsJson|-AsYaml] executable arguments.
    User defaults to a dashboard and YAML, Script to a local object, Agent to JSON.
    Direct interactive prompt calls default to User. Other calls default to Script.
    -UI and -UI:$false override dashboard defaults.
    -Output receives every stream event. -StdOut and -StdErr run afterward for their stream.
    -Complete receives the runtime after streaming. Callbacks can read Mode and ArgvString.
    AsObject never serializes Data. Nested calls inherit their parent's context.
    Native arguments follow the executable verbatim; put QuietCli options first.
    -Script path.ps1 writes a reusable definition without executing the command.
    -DataFactory and -StateFactory initialize fresh business values once per real call.
    -Watch 200ms or -Watch 1s repeats the call after each completed execution.
    -WatchOnKeypress runs again on a console key and can be combined with -Watch.
    Watch uses a live dashboard at the console, or streams one result per execution when a format is selected.
    Press Ctrl+C to stop, or supply -CancellationToken or -CancellationFile.
    .EXAMPLE
    $result = quiet -AsObject -Data @{Bytes=0L} -Output {param($e,$r) $r.Data.Bytes+=$e.ByteCount} pwsh -Command '"hello"'
    .EXAMPLE
    quiet -Watch 200ms -WatchOnKeypress git status
    With the Git companion imported, refreshes the working-tree dashboard every 200 ms or on a keypress.
    #>
    $interactivePrompt = $Host.Name -eq 'ConsoleHost' -and !$MyInvocation.ScriptName -and
        ![Console]::IsInputRedirected -and ![Console]::IsOutputRedirected -and
        @(Get-PSCallStack).Count -le 2
    $request = Read-QuietArguments $args -InteractivePrompt:$interactivePrompt
    if ($request.ContainsKey('Script')) { return Export-QuietCallScript $request }
    Invoke-QuietCall $request
}
