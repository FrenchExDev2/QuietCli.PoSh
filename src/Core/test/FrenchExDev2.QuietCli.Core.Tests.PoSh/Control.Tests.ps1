function Test-QuietTypedControls {
    <#
    .SYNOPSIS
    Checks exact duplex bytes, callback-driven process exit and control rejection recovery in both modes.
    .PARAMETER Fixture
    Existing independent native byte fixture.
    .PARAMETER Dotnet
    Explicit runtime executable.
    #>
    param([string]$Fixture,[string]$Dotnet)
    & (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
        param($fixture,$dotnet)
        $previousMode=(Get-QuietTestConfiguration).Values['engine.hosting'];$previousTracking=(Get-QuietTestConfiguration).Values['telemetry.enabled']
        $bytes=[byte[]]::new(1048583)
        for($index=0;$index -lt $bytes.Length;$index++){$bytes[$index]=[byte]($index%251)}
        $expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        try{
            (Get-QuietTestConfiguration).Values['telemetry.enabled']=$false
            foreach($mode in @('InProcess','Process')){
                Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$mode;$before=Get-QuietEngine
                $data=@{Hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256);Bytes=0L;Rejected=0}
                try{
                    $interaction={param($runtime)
                        foreach($size in @(@(0,40),@(80,40))){
                            try{$runtime.Resize($size[0],$size[1]);throw 'PipeResizeAccepted'}
                            catch{if($_.Exception.ToString() -notmatch 'EngineRequestRejected'){throw};$runtime.Data.Rejected++}
                        }
                        $runtime.WriteBytes($bytes);$runtime.CompleteInput()
                        try{$runtime.WriteText('closed');throw 'WriteAfterEofAccepted'}catch{if($_.Exception.ToString() -notmatch 'InputAlreadyClosed'){throw}}
                    }.GetNewClosure()
                    $r=quiet -AsObject -TimeoutSeconds 30 -StdoutMode Bytes -Data $data -Interaction $interaction -Output {
                        param($event,$runtime)
                        if($event.Stream -eq 'stdout'){$runtime.Data.Hash.AppendData($event.Bytes);$runtime.Data.Bytes+=$event.ByteCount}
                    } $dotnet $fixture copy
                    if($r.Outcome -ne 'Success' -or $data.Bytes -ne $bytes.Length -or $r.Execution.Native.StdinBytesWritten -ne $bytes.Length -or $data.Rejected -ne 2 -or [Convert]::ToHexString($data.Hash.GetHashAndReset()) -cne $expected){throw 'TypedDuplexContractChanged'}
                    $after=Get-QuietEngine
                    if($after.Requests -ne $after.DirectRequests+$after.MetadataJsonRequests){throw 'RequestAccountingMismatch'}
                    if($mode -eq 'InProcess'){
                        if($after.MetadataJsonRequests-$before.MetadataJsonRequests -ne 0 -or $after.DirectRequests-$before.DirectRequests -lt 69 -or $after.ProtocolInputBytes+$after.ProtocolOutputBytes -ne 0){throw 'TypedControlsStillUseJsonOrPipes'}
                    }elseif($after.DirectRequests -ne 0 -or $after.ProtocolInputBytes+$after.ProtocolOutputBytes -le 0){throw 'IsolatedControlAccountingChanged'}
                }finally{$data.Hash.Dispose()}
                $onReady = {
                    param($event,$runtime)
                    if ($event.Text.Trim() -ceq 'ready') {
                        $runtime.Exit($runtime.Data.Code)
                        $runtime.Exit(42)
                        $runtime.Data.CallbackContinued = $true
                    }
                }
                foreach ($code in @(0, 37, [int]::MinValue, [int]::MaxValue)) {
                    $data = @{ Code = $code; CallbackContinued = $false; Completions = 0; Large = 'x' * 500 }
                    $r = quiet -AsObject -TimeoutSeconds 15 -RecordDelimiter "`n" -Data $data -Output $onReady -Complete {
                        param($runtime)
                        $runtime.Data.Completions++
                    } $dotnet $fixture ready-hang
                    $expectedOutcome = if ($code -eq 0) { 'Success' } else { 'Failed' }
                    if ($r.Outcome -cne $expectedOutcome -or $r.ExitCode -isnot [int] -or $r.ExitCode -eq 0 -or
                        $r.ExitCode -ne $r.Execution.Native.ExitCode -or $r.RequestedExitCode -ne $code -or
                        $r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count -or
                        !$data.CallbackContinued -or $data.Completions -ne 1) { throw "CallbackExitContractChanged: $mode $code" }
                    $json = ConvertTo-QuietJson -InputObject $r | ConvertFrom-Json
                    if ($json.ExitCode -ne $r.ExitCode -or $json.RequestedExitCode -ne $code) { throw "CallbackExitJsonChanged: $mode $code" }
                    $yaml = ConvertTo-QuietYaml -InputObject $r -MaxOutputBytes 256
                    if ($yaml -notmatch "(?m)^ExitCode: $($r.ExitCode)`r?$" -or $yaml -notmatch "(?m)^RequestedExitCode: $code`r?$" -or
                        $yaml -notmatch 'OutputBudget' -or [Text.Encoding]::UTF8.GetByteCount($yaml) -gt 256) {
                        throw "CallbackExitBoundedYamlChanged: $mode $code"
                    }
                }
                $natural = quiet -AsObject -RecordDelimiter "`n" -Output { param($event,$runtime) $runtime.Exit(42) } $dotnet $fixture fail
                if ($natural.ExitCode -ne 7 -or $null -ne $natural.RequestedExitCode -or
                    $natural.Outcome -cne 'Failed' -or !$natural.Completeness.Source -or $natural.Error.Count) {
                    throw "NaturalExitCodeChanged: $mode"
                }
                foreach($action in @('input','eof','cancel','exit','resize','release')){
                    $rejected=$false
                    try{$null=Send-QuietRequest @{Action=$action;InvocationId='missing-control';Columns=80;Rows=40;ExitCode=0}}
                    catch{$rejected=$_.Exception.Data['QuietCliRequestRejected'] -eq $true -and $_.Exception.Data['Code'] -eq 'KeyNotFoundException'}
                    if(!$rejected -or [FrenchExDev2.QuietCli.QuietSession]::Engine.Broken){throw 'ControlRejectionBrokeSession'}
                }
                $null=Send-QuietRequest @{Action='hello'}
                if($mode -eq 'InProcess'){
                    $rejected=$false
                    try{$null=[FrenchExDev2.QuietCli.QuietSession]::Engine.Host.ControlAsync([FrenchExDev2.QuietCli.LocalControl]::Input,'missing','bounded',[byte[]]::new(16385),0,0).GetAwaiter().GetResult()}
                    catch{$rejected=$_.Exception.ToString() -match 'InputBlockTooLarge'}
                    if(!$rejected){throw 'DirectOversizedInputAccepted'}
                    $rejected=$false
                    try{$null=[FrenchExDev2.QuietCli.QuietSession]::Engine.Host.ControlAsync([FrenchExDev2.QuietCli.LocalControl]::Eof,('x'*129),'bounded',[byte[]]@(),0,0).GetAwaiter().GetResult()}
                    catch{$rejected=$_.Exception.ToString() -match 'ControlIdentityTooLarge'}
                    if(!$rejected){throw 'DirectOversizedIdentityAccepted'}
                }
            }
        }finally{Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$previousMode;(Get-QuietTestConfiguration).Values['telemetry.enabled']=$previousTracking}
    } $Fixture $Dotnet
}
function Measure-QuietTypedControls {
    <#
    .SYNOPSIS
    Compares former local JSON controls and typed controls using identical input and native hashing.
    .PARAMETER Fixture
    Independent hashing fixture.
    .PARAMETER Dotnet
    Explicit runtime executable.
    #>
    param([string]$Fixture,[string]$Dotnet)
    & (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
        param($fixture,$dotnet)
        $previousMode=(Get-QuietTestConfiguration).Values['engine.hosting'];$previousTracking=(Get-QuietTestConfiguration).Values['telemetry.enabled']
        $blocks=[Collections.Generic.List[byte[]]]::new()
        foreach($index in 0..63){$block=[byte[]]::new(16384);[Array]::Fill[byte]($block,[byte]($index%251));$blocks.Add($block)}
        $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
        try{foreach($block in $blocks){$hash.AppendData($block)};$expected=[Convert]::ToHexString($hash.GetHashAndReset())}finally{$hash.Dispose()}
        try{
            Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']='InProcess';(Get-QuietTestConfiguration).Values['telemetry.enabled']=$false
            $null=Get-QuietEngine;$hostEngine=[FrenchExDev2.QuietCli.QuietSession]::Engine.Host
            foreach($iteration in 1..3){
                foreach($implementation in $(if($iteration%2){@('Json','Typed')}else{@('Typed','Json')})){
                    $stats=@{Controls=0L;ControlJsonBytes=0L};$data=[Text.StringBuilder]::new()
                    $interaction={param($runtime)
                        foreach($index in 0..$blocks.Count){
                            $action=if($index -eq $blocks.Count){'eof'}else{'input'}
                            $payload=[byte[]]@();if($action -eq 'input'){$payload=$blocks[$index]}
                            do{
                                $id=[guid]::NewGuid().ToString('N');$stats.Controls++
                                if($implementation -eq 'Typed'){
                                    $reply=$hostEngine.ControlAsync([FrenchExDev2.QuietCli.LocalControl]$action,$runtime.InvocationId,$id,$payload,0,0).GetAwaiter().GetResult()
                                    if($null -eq $reply.Header -or $null -ne $reply.HeaderJson){throw 'TypedReplyWasSerialized'}
                                    $header=$reply.Header
                                }else{
                                    $encoded=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{Version=1;RequestId=$id;Action=$action;InvocationId=$runtime.InvocationId} -Compress))
                                    $reply=$hostEngine.RequestAsync($encoded,$payload).GetAwaiter().GetResult()
                                    $stats.ControlJsonBytes+=$encoded.Length+[Text.Encoding]::UTF8.GetByteCount($reply.HeaderJson)
                                    $header=ConvertFrom-Json -InputObject $reply.HeaderJson
                                }
                                if(!$header.Ok -or $header.RequestId -cne $id){throw 'ControlSampleReplyMismatch'}
                                $accepted=$action -eq 'eof' -or $header.Data.Accepted
                                if(!$accepted){$null=$runtime.ReadEvent();if($runtime.Completed){throw 'ControlSampleExitedBeforeInput'}}
                            }while(!$accepted)
                        }
                    }.GetNewClosure()
                    $before=Get-QuietEngine;$watch=[Diagnostics.Stopwatch]::StartNew()
                    $r=quiet -AsObject -TimeoutSeconds 30 -Interaction $interaction -Data $data -Output {param($event,$runtime)if($event.Stream -eq 'stdout'){[void]$runtime.Data.Append($event.Text)}} $dotnet $fixture hash
                    $watch.Stop();$after=Get-QuietEngine
                    if($r.Outcome -ne 'Success' -or $r.Execution.Native.StdinBytesWritten -ne 1048576 -or $data.ToString() -cne $expected){throw 'ControlBenchmarkByteMismatch'}
                    @{Kind='InputControls';Implementation=$implementation;Iteration=$iteration;InputBytes=1048576;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Controls=$stats.Controls;ControlJsonBytes=$stats.ControlJsonBytes;ProtocolBytes=$after.ProtocolInputBytes+$after.ProtocolOutputBytes-$before.ProtocolInputBytes-$before.ProtocolOutputBytes;Scope='Local control boundary including native startup, stdin hashing, back-pressure and drainage; excludes assembly/session startup. No pipe IPC in either sample.'}
                }
            }
        }finally{Stop-QuietEngine;(Get-QuietTestConfiguration).Values['engine.hosting']=$previousMode;(Get-QuietTestConfiguration).Values['telemetry.enabled']=$previousTracking}
    } $Fixture $Dotnet
}
