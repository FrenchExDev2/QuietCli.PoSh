function Invoke-QuietRecallLargeTests {
    <#
    .SYNOPSIS
    Qualifies actual output above four GiB using bounded recording, replay and ZIP64 import.
    .PARAMETER WorkspaceRoot
    Selected source root.
    .PARAMETER RunDirectory
    Owned monitored output directory; requires twelve GiB free space.
    .PARAMETER OnProgress
    Existing visible monitor callback, including observable byte heartbeats.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[scriptblock]$OnProgress)
    $length=4296015872L
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($RunDirectory))
    if($drive.AvailableFreeSpace -lt 12884901888L){throw 'LargeRecallRequiresTwelveGiBFreeSpace'}
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    $root=Join-Path $RunDirectory 'large-store'
    if($OnProgress){& $OnProgress 'Recording 4GiB+1MiB; native startup' Running 0 0}
    $r=quiet -AsObject -SaveRecall -RecallRoot $root -RecallName 'large-4gib' -StdoutMode Bytes -TimeoutSeconds 900 -Data @{N=0L;Last=0L} -Output {
        param($e,$r)
        $r.Data.N+=$e.ByteCount
        if($r.Data.N-$r.Data.Last -ge 67108864){
            $r.Data.Last=$r.Data.N
            if($OnProgress){& $OnProgress ('Recording '+[long]($r.Data.N/1048576)+'MiB; native PID '+$r.Execution.ProcessId) Running 0 0}
        }
    } dotnet $fixture emit $length
    Assert-QuietEqual $r.Outcome Success
    Assert-QuietEqual $r.Recall.RetainedBytes $length
    Assert-QuietEqual $r.Recall.DurableBytes $length
    Assert-QuietEqual $r.Data.N $length
    $before=Get-QuietEngine
    if($OnProgress){& $OnProgress 'Replaying saved identity without a native process' Running 0 0}
    $a=quiet -AsObject -RecallId $r.Recall.RecallId -RecallRoot $root -Data @{N=0L;Last=0L} -Output {
        param($e,$r)
        $r.Data.N+=$e.ByteCount
        if($r.Data.N-$r.Data.Last -ge 67108864){$r.Data.Last=$r.Data.N;if($OnProgress){& $OnProgress ('Replay '+[long]($r.Data.N/1048576)+'MiB') Running 0 0}}
    }
    $after=Get-QuietEngine
    Assert-QuietEqual $a.Outcome Success
    Assert-QuietEqual $a.Data.N $length
    Assert-QuietEqual $after.Requests $before.Requests
    if($OnProgress){& $OnProgress 'Writing ZIP64 transport at zlib level 1; elapsed heartbeat remains active' Running 0 0}
    $transport=Export-QuietRecall $r -Path (Join-Path $RunDirectory 'large.zip') -Zip -Compress 1 -PassThru
    $zip=[IO.Compression.ZipFile]::OpenRead($transport.Path)
    try{Assert-QuietEqual ($zip.GetEntry('events.bin').Length -gt [uint32]::MaxValue) $true}finally{$zip.Dispose()}
    if($OnProgress){& $OnProgress 'Importing and verifying ZIP64 with bounded buffers' Running 0 0}
    $imported=Import-QuietRecall $transport.Path -MaxBytes All -RecallRoot (Join-Path $RunDirectory 'large-import')
    Assert-QuietEqual $imported.RetainedBytes $length
    Assert-QuietEqual $imported.RecallId $r.Recall.RecallId
    $peak=[Diagnostics.Process]::GetCurrentProcess().PeakWorkingSet64
    if($peak -ge 1073741824L){throw ('LargeRecallExceededOneGiBWorkerWorkingSet: '+$peak)}
    $evidence=@{NativeBytes=$length;JournalBytes=(Get-Item -LiteralPath (Join-Path $r.Recall.StoragePath 'events.bin')).Length;EventCount=$r.Recall.EventCount;RecallId=$r.Recall.RecallId;PeakWorkingSetBytes=$peak;RecordingMs=$r.Execution.ElapsedMs;ReplayMs=$a.Execution.ElapsedMs;Transport=$transport;SourceComplete=$r.Recall.SourceComplete;ReplayedBytes=$a.Data.N;NativeRequestsDuringReplay=($after.Requests-$before.Requests);ImportedBytes=$imported.RetainedBytes;Scope='Actual 4GiB+1MiB controlled native output, not a sparse file or logical-offset-only test.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'recall-large.json') $evidence
    if($OnProgress){& $OnProgress 'Actual large recording replay ZIP64 and import passed' Passed 1 0}
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=1;Failed=0;Cases=@(@{Name='Actual output above four GiB';State='Passed'});Evidence=$evidence}
}
