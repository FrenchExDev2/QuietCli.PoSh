function Test-QuietEmitListeners {
    <#
    .SYNOPSIS
    Verifies live observers, native fragmentation and bounded JSON/YAML event delivery.
    .PARAMETER WorkspaceRoot
    Built workspace containing the independent native fixture.
    .PARAMETER RunDirectory
    Owned directory for reusable call regressions.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $fixture=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $dotnet=(Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $seen=[Collections.Generic.List[string]]::new()
    $text="été`n漢字`n🙂`nlast"
    $options=@{
        AsObject=$true; CollectEvents=$true; RecordDelimiter="`n"; Data=[Collections.Generic.List[string]]::new()
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
    foreach($mode in @('omitted','false','true')){
        $enabled=$mode -ceq 'true'
        $run=@{};foreach($key in $options.Keys){$run[$key]=$options[$key]}
        $run.CollectEvents=$enabled;$run.Data=[Collections.Generic.List[string]]::new()
        if($mode -ceq 'omitted'){$run.Remove('CollectEvents')}
        $run.Complete={param($runtime)$runtime.Emit([pscustomobject]@{Text='last'});[pscustomobject]@{Retained=$runtime.Events.Count}}
        $before=$seen.Count
        $observed=quiet @run
        if($seen.Count-$before -ne 5){throw 'UncollectedEventsNotDeliveredToListeners'}
        if([bool]$observed.PSObject.Properties['Events'] -ne $enabled -or $observed.Data.Retained -ne $(if($enabled){5}else{0})){throw 'EmitCollectionNotExplicit'}
        $json=ConvertTo-QuietJson $observed -MaxOutputBytes 16384 -MaxItems 20 -Tokenizer off|ConvertFrom-Json
        if([bool]$json.PSObject.Properties['Events'] -ne $enabled){throw 'EmitDeliveryExposedUnrequestedEvents'}
        $yaml=ConvertTo-QuietYaml $observed -MaxOutputBytes 16384 -MaxItems 20 -Tokenizer off
        $reader=[IO.StringReader]::new($yaml)
        try{$decoded=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build().Deserialize[object]($reader)}finally{$reader.Dispose()}
        if($decoded.ContainsKey('Events') -ne $enabled){throw 'EmitYamlExposedUnrequestedEvents'}
    }
    $nested=@{};foreach($key in $options.Keys){$nested[$key]=$options[$key]}
    $nested.Remove('Listeners');$nested.Data=[Collections.Generic.List[string]]::new()
    $nested.Complete={param($runtime)
        $inner=quiet -AsObject -FilePath $dotnet -ArgumentList @($fixture,'chunks','20261108','inner') -Output {param($event,$runtime)} -Complete {param($runtime)$runtime.Emit('inner');$runtime.Events.Count}
        [pscustomobject]@{OuterRetained=$runtime.Events.Count;InnerRetained=$inner.Data;InnerHasEvents=[bool]$inner.PSObject.Properties['Events'];InnerOutcome=$inner.Outcome}
    }
    $result=quiet @nested
    if($result.Outcome -ne 'Success' -or $result.Data.OuterRetained -ne 4 -or $result.Data.InnerOutcome -ne 'Success' -or $result.Data.InnerRetained -ne 0 -or $result.Data.InnerHasEvents){throw 'EmitCollectionInheritedByNestedInvocation'}
    foreach($enabled in @($false,$true)){
        $call=@{AsObject=$true;CollectEvents=$enabled;RecordDelimiter="`n";FilePath=$dotnet;ArgumentList=@($fixture,'chunks','20261108','saved');Script=(Join-Path $RunDirectory ('saved-events-'+$enabled+'.ps1'));Output={param($event,$runtime)if($event.Stream -eq 'stdout'){$runtime.Emit($event.Text)}};Complete={param($runtime)$runtime.Events.Count}}
        $definition=quiet @call
        if((Get-Content $definition.FullName -Encoding utf8 -TotalCount 1) -like '#Objective: *'){throw 'SavedCallUnexpectedObjectiveHeader'}
        $saved=& $definition.FullName
        if($saved.Outcome -ne 'Success' -or $saved.Data -ne $(if($enabled){1}else{0}) -or [bool]$saved.PSObject.Properties['Events'] -ne $enabled){throw 'SavedCallEventCollectionNotPreserved'}
    }
}
