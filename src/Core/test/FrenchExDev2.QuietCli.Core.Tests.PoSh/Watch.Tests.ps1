function Test-QuietWatch {
    <#
    .SYNOPSIS
    Checks Watch through the public command with native execution, streaming delivery and cancellation.
    .PARAMETER Fixture
    Built native-process test fixture.
    .PARAMETER Dotnet
    Runtime executable for the fixture.
    #>
    param([string]$Fixture,[string]$Dotnet)

    $clock = [Diagnostics.Stopwatch]::StartNew()
    $starts = [Collections.Generic.List[double]]::new()
    $calls = @{
        FilePath = $Dotnet
        ArgumentList = @($Fixture,'args','watch')
        TimeoutSeconds = 5
        DataFactory = {
            $starts.Add($clock.Elapsed.TotalMilliseconds)
            @{ Iteration = $starts.Count }
        }.GetNewClosure()
        Complete = {param($runtime) $runtime.Data}
    }
    $cancel = [Threading.CancellationTokenSource]::new()
    try {
        $cancel.CancelAfter(60000)
        $results = [Collections.Generic.List[object]]::new()
        $null = quiet -Watch 200ms -AsObject -CancellationToken $cancel.Token @calls |
            ForEach-Object { $results.Add($_); $results.Count } | Select-Object -First 2
        if($results.Count -ne 2 -or $starts.Count -ne 2 -or ($starts[1] - $starts[0]) -lt 195){
            throw 'Watch did not stream exactly two executions separated by the requested delay.'
        }
        for($i = 0; $i -lt 2; $i++){
            Invoke-QuietConformance $results[$i]
            Assert-QuietEqual $results[$i].Outcome Success
            Assert-QuietEqual $results[$i].Data.Iteration ($i+1)
        }
        if($results[0].InvocationId -eq $results[1].InvocationId){throw 'Watch reused an invocation identity.'}
        $json = @(quiet -Mode User -Watch 1s -AsJson -CancellationToken $cancel.Token @calls | Select-Object -First 2)
        Assert-QuietEqual $json.Count 2
        Assert-QuietEqual ($json[0] | ConvertFrom-Json).Data.Iteration 3
        Assert-QuietEqual ($json[1] | ConvertFrom-Json).Data.Iteration 4
        $yaml = @(quiet -Watch 1ms -AsYaml -MaxOutputBytes 256 -CancellationToken $cancel.Token @calls | Select-Object -First 2)
        Assert-QuietEqual $yaml.Count 2
        foreach($document in $yaml){
            if(!$document.StartsWith("---`n") -or [Text.Encoding]::UTF8.GetByteCount($document) -gt 256 -or $document -notmatch '(?m)^Outcome: Success\r?$'){
                throw 'Watch YAML framing, outcome or delivery byte limit changed.'
            }
        }
    } finally { $cancel.Dispose() }

    $cancel = [Threading.CancellationTokenSource]::new()
    try {
        $output = {
            param($event,$runtime)
            if($event.Text.Trim() -eq 'ready'){$cancel.Cancel()}
        }.GetNewClosure()
        $result = @(quiet -Watch 1ms -AsObject -CancellationToken $cancel.Token -TimeoutSeconds 5 -RecordDelimiter "`n" -Output $output -FilePath $Dotnet -ArgumentList @($Fixture,'ready-hang'))
        Assert-QuietEqual $result.Count 1
        Assert-QuietEqual $result[0].Outcome Cancelled
        if(Get-Process -Id $result[0].Execution.Native.ProcessId -ErrorAction SilentlyContinue){throw 'Watch left the cancelled child running.'}
        $noStart = @(quiet -Watch 1ms -AsObject -CancellationToken $cancel.Token @calls)
        Assert-QuietEqual $noStart.Count 0
    } finally { $cancel.Dispose() }

    foreach($interval in @('0ms','-1s','200','1minute','2147484s','')){
        $code = $null
        try { $null = quiet -Watch $interval @calls } catch { $code = $_.Exception.Message }
        if($code -notlike 'InvalidWatchInterval*'){throw "An invalid Watch interval was accepted: '$interval'"}
    }
    $result = quiet -WatchOnKeypress:$false -AsObject @calls
    Assert-QuietEqual $result.Outcome Success
    if([Console]::IsInputRedirected){
        $code = $null
        try { $null = quiet -WatchOnKeypress @calls } catch { $code = $_.Exception.Message }
        Assert-QuietEqual $code WatchOnKeypressRequiresConsoleInput
    }
}
