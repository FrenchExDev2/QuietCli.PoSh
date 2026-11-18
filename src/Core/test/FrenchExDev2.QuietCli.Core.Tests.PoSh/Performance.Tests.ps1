function Measure-QuietLocalOverhead {
    <#
    .SYNOPSIS
    Compares the former byte loop with compiled framing, then isolated and direct engine dispatch.
    .DESCRIPTION
    Uses identical synthetic bytes and existing fixture output; stores timing and counts only.
    These local samples establish neither cross-platform qualification nor a general speed claim.
    .PARAMETER Fixture
    Existing independent byte producer assembly.
    .PARAMETER Dotnet
    Explicit runtime executable.
    #>
    param([string]$Fixture,[string]$Dotnet)
    $samples=[Collections.Generic.List[object]]::new()
    # Load and JIT the verified .NET 10 helper before measuring steady-state work.
    $warm=New-QuietByteRecordFramer -Delimiter 0
    $null=@($warm.Push([byte[]]@(1,0)));$warm.Dispose()
    foreach($width in @(64,8192)){
        $block=[byte[]]::new(16384)
        for($i=$width-1;$i -lt $block.Length;$i+=$width){$block[$i]=10}
        foreach($iteration in 1..3){
            foreach($implementation in $(if($iteration%2){@('PowerShell','CSharp')}else{@('CSharp','PowerShell')})){
                $records=0L;$bytes=0L
                $watch=[Diagnostics.Stopwatch]::StartNew()
                if($implementation -eq 'PowerShell'){
                    $pending=[IO.MemoryStream]::new()
                    try{
                        foreach($chunk in 1..64){
                            $start=0
                            for($index=0;$index -lt $block.Length;$index++){
                                if($block[$index] -ne 10){continue}
                                $count=$index-$start
                                if($pending.Length+$count -gt 1048576){throw 'GitRecordTooLarge'}
                                if($count){$pending.Write($block,$start,$count)}
                                $record=$pending.ToArray();$pending.SetLength(0)
                                $records++;$bytes+=$record.Length;$start=$index+1
                            }
                            if($start -lt $block.Length){$pending.Write($block,$start,$block.Length-$start)}
                        }
                    }finally{$pending.Dispose()}
                }else{
                    $framer=New-QuietByteRecordFramer
                    try{foreach($chunk in 1..64){foreach($record in $framer.Push($block)){$records++;$bytes+=$record.Length}}}
                    finally{$framer.Dispose()}
                }
                $watch.Stop()
                if($records -ne 1048576/$width -or $bytes -ne 1048576-$records){throw 'FramingBenchmarkByteMismatch'}
                $samples.Add(@{Kind='RecordFraming';Implementation=$implementation;Iteration=$iteration;InputBytes=1048576;RecordWidth=$width;Records=$records;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Scope='Synthetic delimiter scan and record copies; no parser callback or IPC.'})
            }
        }
    }
    $previousMode=(Get-QuietTestConfiguration).Values['engine.hosting']
    try{
        foreach($mode in @('Process','InProcess')){
            Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$mode
            $cold=[Diagnostics.Stopwatch]::StartNew();$identity=Get-QuietEngine;$cold.Stop()
            if($mode -eq 'InProcess' -and $identity.Engine.ProcessId -ne $PID){throw 'DirectEngineStartedAChild'}
            $samples.Add(@{Kind='EngineStartup';Mode=$mode;ElapsedMs=$cold.Elapsed.TotalMilliseconds;Runtime=$identity.Engine.Runtime;Scope='Helper assembly already loaded; includes identity verification and hello.'})
            foreach($iteration in 1..3){
                $before=Get-QuietEngine;$watch=[Diagnostics.Stopwatch]::StartNew()
                $r=quiet -AsObject -Role Infrastructure -ReadBlockBytes 16384 -StdoutMode Bytes -Output {param($e,$r)} $Dotnet $Fixture emit 8388608
                $watch.Stop();$after=Get-QuietEngine
                if($r.Outcome -ne 'Success' -or $r.Execution.Native.StdoutBytesRead -ne 8388608){throw 'EngineBenchmarkSourceMismatch'}
                $wire=$after.ProtocolInputBytes+$after.ProtocolOutputBytes-$before.ProtocolInputBytes-$before.ProtocolOutputBytes
                if($mode -eq 'InProcess' -and $wire -ne 0){throw 'DirectEngineReportedPipeTraffic'}
                $samples.Add(@{Kind='EngineTransport';Mode=$mode;Iteration=$iteration;InputBytes=8388608;ElapsedMs=$watch.Elapsed.TotalMilliseconds;NativeMs=$r.Execution.Native.ElapsedMs;CallbackMs=$r.Execution.CallbackMs;Requests=$after.Requests-$before.Requests;ProtocolBytes=$wire;Scope='Includes producer startup, back-pressure, JSON metadata and callback dispatch; not pure IPC latency.'})
            }
            $counter=@{Count=0L}
            $nested=quiet -AsObject -StdoutMode Bytes -Data $counter -Output {
                param($event,$runtime)
                $runtime.Data.Count+=$event.ByteCount
                if(!$runtime.State.ContainsKey('Child')){
                    $runtime.State.Child=$true
                    $runtime.State.Result=quiet -AsObject -Output {param($e,$r)} -FilePath $Dotnet -ArgumentList @($Fixture,'emit','3')
                }
            }.GetNewClosure() $Dotnet $Fixture emit 3
            if($nested.Outcome -ne 'Success' -or $counter.Count -ne 3 -or $nested.Execution.Children -ne 1){throw 'DirectCallbackOrNestedInvocationChanged'}
        }
    }finally{Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$previousMode}
    return $samples.ToArray()
}

function New-QuietCountingListener {
    <#
    .SYNOPSIS
    Creates a listener that only counts events and checks their type and order.
    .PARAMETER Hits
    Box incremented once per delivered event.
    .PARAMETER Faults
    Box incremented when an event has the wrong type or arrives out of order.
    #>
    param([Runtime.CompilerServices.StrongBox[long]]$Hits,[Runtime.CompilerServices.StrongBox[long]]$Faults)
    {param($event,$runtime)
        if($event.Type -cne 'Sample' -or $event.Data.Index -ne $Hits.Value){$Faults.Value++}
        $Hits.Value++
    }.GetNewClosure()
}

function Measure-QuietEventEmission {
    <#
    .SYNOPSIS
    Times Emit alone for 0, 1 and 4 listeners, with and without -CollectEvents.
    .DESCRIPTION
    Each call runs the fixture briefly, then emits the events from -Complete with payloads allocated
    before the call, so EmitMs covers Emit, listener dispatch and retention only. One warm-up call is
    discarded. The order of the six configurations changes with each iteration, from a fixed seed.
    Every sample must deliver each event to every listener in order, retain events only when asked
    and report no error.
    .PARAMETER Fixture
    Existing independent byte producer assembly.
    .PARAMETER Dotnet
    Explicit runtime executable.
    .PARAMETER Events
    Events emitted per call.
    .PARAMETER Iterations
    Retained samples per configuration.
    .PARAMETER Seed
    Seed of the configuration order.
    #>
    param([string]$Fixture,[string]$Dotnet,[ValidateRange(1,65536)][int]$Events=512,[ValidateRange(1,64)][int]$Iterations=3,[int]$Seed=73601)
    $samples=[Collections.Generic.List[object]]::new()
    $payloads=[object[]]::new($Events)
    for($i=0;$i -lt $Events;$i++){$payloads[$i]=[pscustomobject]@{Index=$i;Text=('event '+$i)}}
    $grid=@(foreach($listeners in 0,1,4){foreach($collect in $false,$true){[pscustomobject]@{Listeners=$listeners;CollectEvents=$collect}}})
    $random=[Random]::new($Seed)
    $complete={param($runtime)
        $watch=[Diagnostics.Stopwatch]::StartNew()
        foreach($payload in $runtime.Data){$runtime.Emit('Sample',$payload)}
        $watch.Stop()
        [pscustomobject]@{EmitMs=$watch.Elapsed.TotalMilliseconds;Retained=$runtime.Events.Count}
    }
    $measure={param($configuration)
        $hits=@(for($i=0;$i -lt $configuration.Listeners;$i++){[Runtime.CompilerServices.StrongBox[long]]::new(0)})
        $faults=[Runtime.CompilerServices.StrongBox[long]]::new(0)
        $call=@{AsObject=$true;CollectEvents=$configuration.CollectEvents;Data=$payloads;StdoutMode='Bytes';Output={param($event,$runtime)};Complete=$complete;FilePath=$Dotnet;ArgumentList=@($Fixture,'emit','3')}
        if($hits.Count){$call.Listeners=@(foreach($box in $hits){New-QuietCountingListener -Hits $box -Faults $faults})}
        $watch=[Diagnostics.Stopwatch]::StartNew();$result=quiet @call;$watch.Stop()
        if($result.Outcome -ne 'Success' -or @($result.Error).Count){throw 'EventEmissionCallFailed'}
        if($faults.Value -or @($hits|Where-Object {$_.Value -ne $Events}).Count){throw 'EventEmissionDeliveryLost'}
        if([bool]$result.PSObject.Properties['Events'] -ne $configuration.CollectEvents -or $result.Data.Retained -ne $(if($configuration.CollectEvents){$Events}else{0})){throw 'EventEmissionCollectionNotExplicit'}
        if($configuration.CollectEvents -and ($result.Events.Count -ne $Events -or $result.Events[$Events-1].Data.Index -ne $Events-1 -or $result.Events[0].Type -cne 'Sample')){throw 'EventEmissionRetainedOrderLost'}
        [pscustomobject]@{EmitMs=[double]$result.Data.EmitMs;InvocationMs=$watch.Elapsed.TotalMilliseconds}
    }
    $null=& $measure $grid[$grid.Count-1]
    $mode=(Get-QuietEngine).Mode
    for($iteration=1;$iteration -le $Iterations;$iteration++){
        $order=[object[]]$grid.Clone()
        for($i=$order.Length-1;$i -gt 0;$i--){$j=$random.Next($i+1);$swap=$order[$i];$order[$i]=$order[$j];$order[$j]=$swap}
        foreach($configuration in $order){
            $timing=& $measure $configuration
            $samples.Add(@{Kind='EventEmission';Listeners=$configuration.Listeners;CollectEvents=$configuration.CollectEvents;Events=$Events;Iteration=$iteration;Seed=$Seed;EmitMs=$timing.EmitMs;InvocationMs=$timing.InvocationMs;EngineMode=$mode;Scope='Emit loop inside -Complete; counting listeners; payloads allocated before the call.'})
        }
    }
    return $samples.ToArray()
}
