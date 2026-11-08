function Invoke-QuietCli {
    <#
.SYNOPSIS
Executes a streaming command or registered handler; options precede the binary.
    .DESCRIPTION
    quiet [-C context] [-AsObject|-AsJson|-AsYaml] [-Output {param($event,$runtime)}]
    [-Complete {param($runtime)}] executable arguments. AsObject never serializes Data.
    Nested calls default to AsObject and inherit their parent's context.
    Native arguments follow the executable verbatim; put QuietCli options first.
    -Script path.ps1 writes a reusable definition without executing the command.
    -DataFactory and -StateFactory initialize fresh business values once per real call.
    .EXAMPLE
    $result = quiet -AsObject -Data @{Bytes=0L} -Output {param($e,$r) $r.Data.Bytes+=$e.ByteCount} pwsh -Command '"hello"'
    #>
    $request = Read-QuietArguments $args
    if ($request.ContainsKey('Script')) { return Export-QuietCallScript $request }
    Invoke-QuietCall $request
}
