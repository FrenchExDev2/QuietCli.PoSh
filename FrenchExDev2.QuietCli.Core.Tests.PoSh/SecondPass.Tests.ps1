function Invoke-QuietSecondPassChecks {
    <#
    .SYNOPSIS
    Verifies aggregate paging, exact budgets and parser semantics, then compares local mechanism costs.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace whose existing companion runner owns the visible monitor.
    #>
    param([string]$WorkspaceRoot)
    . (Join-Path $PSScriptRoot 'Gain.Output.Tests.ps1')
    $null=Test-QuietGainOutput
    . (Join-Path $PSScriptRoot 'Telemetry.Tests.ps1')
    Test-QuietAllocationTelemetry -WorkspaceRoot $WorkspaceRoot
    Measure-QuietProcessAllocations -WorkspaceRoot $WorkspaceRoot
    $module=Get-Module FrenchExDev2.QuietCli.Core.PoSh
    & $module {
        param($baseline)
        . $baseline
        $context='synthetic-gain-'+[guid]::NewGuid().ToString('N')
        foreach($index in 0..255){
            $id='synthetic-'+$index
            $metadata=@{InvocationId=$id;Context=$context;Command=$(if($index%2){'odd'}else{'even'});Role='Business';Outcome='Success';Completeness=@{Source=$true;Analysis=$true};Sources=@(@{InvocationId=$id;Role='Business';StdinBytesWritten=1L;StdoutBytesRead=64L;StderrBytesRead=0L;TerminalBytesRead=$null;Complete=$true})}
            $null=Send-QuietRequest @{Action='save';Kind='invocation';Metadata=$metadata}
            $delivery=$metadata.Clone();$delivery.DeliveryId='synthetic-delivery-'+$index;$delivery.OutputBytes=16L
            $null=Send-QuietRequest @{Action='save';Kind='delivery';Metadata=$delivery}
        }
        $previousMode=$env:QUIETCLI2_ENGINE_MODE
        try{
            foreach($mode in @('InProcess','Process')){
                Stop-QuietEngine;$env:QUIETCLI2_ENGINE_MODE=$mode
        foreach($iteration in 1..3){
            foreach($implementation in $(if($iteration%2){@('PowerShell','CSharp')}else{@('CSharp','PowerShell')})){
                $before=Get-QuietEngine;$watch=[Diagnostics.Stopwatch]::StartNew()
                $report=if($implementation -eq 'PowerShell'){Get-QuietCliGainBaseline -C $context -GroupBy Command -MaxEvents 512 -AsObject}else{Get-QuietCliGain -C $context -GroupBy Command -MaxEvents 512 -AsObject}
                $watch.Stop();$after=Get-QuietEngine
                if(!$report.Complete -or $report.Invocations -ne 256 -or $report.UniqueNativeSources -ne 256 -or $report.BusinessBytesObserved -ne 16384 -or $report.RootDeliveryBytes -ne 4096 -or $report.ReductionBytes -ne 12288 -or $report.Groups.Count -ne 2){throw 'SyntheticGainCounterMismatch'}
                @{Kind='GainAggregation';Implementation=$implementation;Iteration=$iteration;Mode=$mode;Events=512;Groups=2;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Requests=$after.Requests-$before.Requests;ProtocolBytes=$after.ProtocolInputBytes+$after.ProtocolOutputBytes-$before.ProtocolInputBytes-$before.ProtocolOutputBytes;Scope='Synthetic closed metadata, including database projection and report delivery; no business objects or native output.'}
            }
        }
            }
        }finally{Stop-QuietEngine;$env:QUIETCLI2_ENGINE_MODE=$previousMode}
        $limited=Get-QuietCliGain -C $context -MaxEvents 511 -AsObject
        if($limited.Complete -or $null -ne $limited.ReductionBytes){throw 'LimitedGainClaimedCompleteness'}
        $empty=Get-QuietCliGain -C ($context+'-absent') -AsObject
        if(!$empty.Complete -or $empty.Invocations -ne 0 -or $empty.Groups.Count -ne 0){throw 'EmptyGainReportChanged'}
        $paging=$context+'-groups'
        foreach($index in 0..259){
            $null=Send-QuietRequest @{Action='save';Kind='invocation';Metadata=@{InvocationId='group-'+$index;Context=$paging;Command=('command-'+$index);Outcome='Success'}}
        }
        $report=Get-QuietCliGain -C $paging -GroupBy Command -MaxEvents 260 -AsObject
        if(!$report.Complete -or $report.Invocations -ne 260 -or $report.Groups.Count -ne 260 -or @($report.Groups.Key|Select-Object -Unique).Count -ne 260){throw 'GainGroupPaginationLostCounters'}
        # More than eight complete reports must not consume the eight unfinished report slots.
        foreach($index in 1..9){$report=Get-QuietCliGain -C $paging -GroupBy Command -MaxEvents 260 -AsObject;if($report.Groups.Count -ne 260){throw 'GainReportSlotNotReleased'}}
    } (Join-Path $PSScriptRoot 'Gain.Baseline.ps1')
    & $module {
        foreach($shape in @('ShortRecords','LongFragment')){
            $block=if($shape -eq 'ShortRecords'){(('x'*63)+"`n")*256}else{'x'*1024}
            $chunks=if($shape -eq 'ShortRecords'){16}else{256}
            foreach($iteration in 1..3){
                foreach($implementation in $(if($iteration%2){@('PowerShell','CSharp')}else{@('CSharp','PowerShell')})){
                    $records=0;$characters=0L;$pending='';$framer=$null
                    if($implementation -eq 'CSharp'){Import-QuietManagedEngine;$framer=[FrenchExDev2.QuietCli.TextStreamState]::new("`n",1048576)}
                    $watch=[Diagnostics.Stopwatch]::StartNew()
                    try{
                        foreach($chunk in 1..$chunks){
                            if($implementation -eq 'PowerShell'){
                                $pending+=$block
                                while(($position=$pending.IndexOf("`n",[StringComparison]::Ordinal)) -ge 0){
                                    if([Text.Encoding]::UTF8.GetByteCount($pending.Substring(0,$position)) -gt 1048576){throw 'RecordTooLarge'}
                                    $text=$pending.Substring(0,$position);$records++;$characters+=$text.Length;$pending=$pending.Substring($position+1)
                                }
                                if([Text.Encoding]::UTF8.GetByteCount($pending) -gt 1048576){throw 'RecordTooLarge'}
                            }else{foreach($text in $framer.Frame($block)){$records++;$characters+=$text.Length}}
                        }
                        $tail=if($implementation -eq 'PowerShell'){$pending}else{$framer.Finish()}
                        if($tail.Length){$records++;$characters+=$tail.Length}
                    }finally{if($framer){$framer.Dispose()}}
                    $watch.Stop()
                    $expectedRecords=if($shape -eq 'ShortRecords'){4096}else{1}
                    $expectedCharacters=if($shape -eq 'ShortRecords'){258048}else{262144}
                    if($records -ne $expectedRecords -or $characters -ne $expectedCharacters){throw 'TextFramingBenchmarkChangedRecords'}
                    @{Kind='TextFraming';Implementation=$implementation;Shape=$shape;Iteration=$iteration;InputCharacters=262144;Records=$records;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Scope='Synthetic decoded text framing only; same record accounting, no decoder, callback or IPC.'}
                }
            }
        }
    }
}
