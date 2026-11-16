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
