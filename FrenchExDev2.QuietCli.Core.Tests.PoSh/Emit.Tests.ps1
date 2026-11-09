function Test-QuietEmitListeners {
    <#
    .SYNOPSIS
    Verifies live observers, native fragmentation and bounded JSON/YAML event delivery.
    .PARAMETER WorkspaceRoot
    Built workspace containing the independent native fixture.
    #>
    param([string]$WorkspaceRoot)
    $fixture=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $dotnet=(Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $seen=[Collections.Generic.List[string]]::new()
    $text="été`n漢字`n🙂`nlast"
    $options=@{
        AsObject=$true; RecordDelimiter="`n"; Data=[Collections.Generic.List[string]]::new()
        Listeners=@(
            {param($event,$runtime) [void]$seen.Add($event.Text)},
            {param($event,$runtime) throw 'ObserverFixtureFailure'}
        )
        Output={param($event,$runtime)
            if($event.Stream -eq 'stdout'){
                $line=$event.Text.TrimEnd("`r","`n")
                [void]$runtime.Data.Add($line)
                $runtime.Emit([pscustomobject]@{Text=$line})
            }
        }
        Complete={param($runtime) $runtime.Emit([pscustomobject]@{Text='completed'}); [pscustomobject]@{Lines=$runtime.Data.Count}}
        FilePath=$dotnet; ArgumentList=@($fixture,'chunks','20261108',$text)
    }
    $result=quiet @options
    if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw 'EmitNativeAnalysisIncomplete'}
    if($result.Data.Lines -ne 4 -or $result.Events.Count -ne 5 -or ($seen -join '|') -cne 'été|漢字|🙂|last|completed'){throw 'EmitNativeEventOrderLost'}
    if($result.Error.Count -ne 1 -or $result.Error[0].Code -cne 'ListenerFailed'){throw 'EmitObserverWasRetriedOrFailureLost'}
    foreach($format in @('AsJson','AsYaml')){
        $delivery=@{};foreach($key in $options.Keys){$delivery[$key]=$options[$key]}
        $delivery.Remove('AsObject');$delivery[$format]=$true;$delivery.MaxItems=2;$delivery.MaxOutputBytes=16384;$delivery.Tokenizer='off'
        $delivery.Data=[Collections.Generic.List[string]]::new()
        $serialized=quiet @delivery
        if($format -eq 'AsJson'){$decoded=$serialized | ConvertFrom-Json}
        else{
            # Use the shipped YAML codec, independent from the projection being asserted.
            [void][Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
            $reader=[IO.StringReader]::new($serialized)
            try{$decoded=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build().Deserialize[object]($reader)}finally{$reader.Dispose()}
        }
        if($format -eq 'AsJson'){
            $events=$decoded.Events;$first=$events[0].Text;$second=$events[1].Text;$truncated=$decoded.Truncation.Applied
        }else{
            # YamlDotNet's untyped dictionary has object keys, which require explicit indexers in PowerShell.
            $events=$decoded['Events'];$first=$events[0]['Text'];$second=$events[1]['Text'];$truncated=[bool]::Parse($decoded['Truncation']['Applied'])
        }
        if($events.Count -ne 2 -or $first -cne 'été' -or $second -cne '漢字' -or !$truncated){throw "EmitDeliveryBudgetLost: $format"}
    }
    if($result.Events.Count -ne 5){throw 'EmitDeliveryMutatedLocalEvents'}
}
