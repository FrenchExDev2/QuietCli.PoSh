<#
.SYNOPSIS
Runs one named Core workload in an explicitly instrumented pass and records the duration of each iteration.
.DESCRIPTION
GitTransport: porcelain-v2 bytes of the bulk fixture through -Output and -Complete.
Framing: compiled NUL framing of 128 blocks of 16 KiB holding 64-byte records.
Metadata: short git --version calls and engine identity queries, so dispatch and projection dominate.
Events: Emit of 256 events with 0 listeners, 1 listener and collection, and 4 listeners.
Import and the first call are not here: collectors attach after them.
.PARAMETER RepositoryPath
Owned bulk fixture from the completed integration run.
.PARAMETER Workload
Workload to run.
.PARAMETER Iterations
Timed iterations.
.PARAMETER Samples
Receives the instrumented duration of each iteration in milliseconds.
#>
param(
    [string]$RepositoryPath,
    [ValidateSet('GitTransport','Framing','Metadata','Events')][string]$Workload='GitTransport',
    [ValidateRange(1,64)][int]$Iterations=8,
    [Collections.Generic.List[double]]$Samples=[Collections.Generic.List[double]]::new()
)
$git=(Get-Command git -CommandType Application|Select-Object -First 1).Source
$payloads=@(for($i=0;$i -lt 256;$i++){[pscustomobject]@{Index=$i}})
foreach($iteration in 1..$Iterations){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    switch($Workload){
        'GitTransport'{
            $result=quiet -AsObject -WorkingDirectory $RepositoryPath -StdoutMode Bytes -Data @{Bytes=0L} -Output {
                param($event,$runtime)
                $runtime.Data.Bytes+=$event.ByteCount
            } -Complete {param($runtime)$runtime.Data.Bytes} -FilePath $git -ArgumentList @('status','--porcelain=v2','-z','--untracked-files=all')
            if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Data -ne $result.Execution.Native.StdoutBytesRead){throw 'ProfiledBusinessResultMismatch'}
        }
        'Framing'{
            $framer=New-QuietByteRecordFramer -Delimiter 0
            try{
                # 64-byte records, as in the uninstrumented width=64 framing benchmark.
                $block=[byte[]]::new(16384);[Array]::Fill($block,[byte]1)
                for($i=63;$i -lt $block.Length;$i+=64){$block[$i]=0}
                $records=0
                foreach($chunk in 1..128){$records+=@($framer.Push($block)).Count}
                if($records -ne 128*256){throw 'ProfiledFramingRecordMismatch'}
            }finally{$framer.Dispose()}
        }
        'Metadata'{
            foreach($call in 1..4){
                $result=quiet -AsObject -Output {param($event,$runtime)} -FilePath $git -ArgumentList @('--version')
                if($result.Outcome -ne 'Success' -or !$result.Completeness.Source){throw 'ProfiledMetadataCallFailed'}
            }
            foreach($query in 1..16){$null=Get-QuietEngine}
        }
        'Events'{
            foreach($configuration in @(@{Listeners=0;Collect=$false},@{Listeners=1;Collect=$true},@{Listeners=4;Collect=$false})){
                $hits=[Runtime.CompilerServices.StrongBox[long]]::new(0)
                $call=@{AsObject=$true;CollectEvents=$configuration.Collect;Data=$payloads;Output={param($event,$runtime)};FilePath=$git;ArgumentList=@('--version')
                    Complete={param($runtime)foreach($payload in $runtime.Data){$runtime.Emit('Sample',$payload)};$runtime.Events.Count}}
                if($configuration.Listeners){$call.Listeners=@(for($i=0;$i -lt $configuration.Listeners;$i++){{param($event,$runtime)$hits.Value++}.GetNewClosure()})}
                $result=quiet @call
                if($result.Outcome -ne 'Success' -or $hits.Value -ne 256*$configuration.Listeners -or $result.Data -ne $(if($configuration.Collect){256}else{0})){throw 'ProfiledEventDeliveryMismatch'}
            }
        }
    }
    $watch.Stop()
    $Samples.Add($watch.Elapsed.TotalMilliseconds)
}
