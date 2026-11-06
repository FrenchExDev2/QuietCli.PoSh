function Invoke-QuietRecallTests {
    <#
    .SYNOPSIS
    Runs independent Recall regressions and records performance without claiming release qualification.
    .PARAMETER WorkspaceRoot
    QuietCli2 source root.
    .PARAMETER RunDirectory
    Shared monitored report directory.
    .PARAMETER OnProgress
    Existing visible monitor callback.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[scriptblock]$OnProgress)
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    $engineTests=Join-Path $PSScriptRoot 'lib/engine-tests/QuietCli.Engine.Tests.dll'
    $cases=[ordered]@{};$metrics=[Collections.Generic.List[object]]::new()
    $cases['Recall compiled unit properties and malformed archive fuzz']={
        $r=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r) if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r) $r.Data.ToString()|ConvertFrom-Json} dotnet $engineTests --recall-only
        Assert-QuietEqual $r.Outcome Success (($r.Data|ConvertTo-Json -Depth 8 -Compress))
        Assert-QuietEqual $r.Data.Failed 0
        Write-WorkspaceJson (Join-Path $RunDirectory 'recall-csharp.json') $r.Data
    }
    $cases['Recall rejects invalid capture options before native execution']={
        foreach($options in @(@('-Recall'),@('-AsObject','-RecallMaxBytes','1KiB'),@('-Recall','-AsObject','-RecallMaxBytes','0'),@('-Recall','-AsObject','-RecallMaxBytes','All','-RecallPolicy','Tail'))){
            $rejected=$false
            try{$null=quiet @options -Output {} dotnet $fixture emit 1}catch{$rejected=$true}
            Assert-QuietEqual $rejected $true
        }
    }
    $cases['Recall generated PowerShell bindings preserve byte counts and reject malformed sizes seed 11606']={
        $random=[Random]::new(11606)
        foreach($iteration in 1..50){
            $size=$random.Next(1,200);$bytes=[byte[]]::new($size);$random.NextBytes($bytes)
            $collector=[FrenchExDev2.QuietCli.RecallCollector]::new([FrenchExDev2.QuietCli.RecallOptions]::new('All','Head'))
            $collector.Append('stdout',$bytes)
            $settings=[FrenchExDev2.QuietCli.RecallAnalysisSettings]::new('Bytes','Bytes',[NullString]::Value,1024)
            $capture=$collector.Snapshot($true,$settings)
            $a=Invoke-QuietRecall $capture -Data @{Count=0L} -Output {param($e,$r)$r.Data.Count+=$e.ByteCount}
            Assert-QuietEqual $a.Data.Count $size
            $bad=([string]$size)+'KiB-invalid-'+$iteration
            $rejected=$false;try{$null=quiet -AsObject -Recall -RecallMaxBytes $bad -Output {} dotnet $fixture emit 1}catch{$rejected=$true}
            Assert-QuietEqual $rejected $true
        }
    }
    $cases['Recall captures mixed streams and reanalyzes without a new native request in both hosts']={
        $oldMode=$env:QUIETCLI2_ENGINE_MODE
        try{
            foreach($mode in @('InProcess','Process')){
                Stop-QuietEngine;$env:QUIETCLI2_ENGINE_MODE=$mode
                $r=quiet -AsObject -Recall -RecallMaxBytes All -StdoutMode Bytes -StderrMode Bytes -Output {} dotnet $fixture mixed 92161 11000
                Assert-QuietEqual $r.Outcome Success
                Assert-QuietEqual $r.Recall.ReceivedBytes 103161
                Assert-QuietEqual $r.Recall.CaptureComplete $true
                $before=Get-QuietEngine
                foreach($iteration in 1..2){
                    $a=Invoke-QuietRecall $r -Data @{stdout=0L;stderr=0L} -Output {param($e,$r) $r.Data[$e.Stream]+=$e.ByteCount}
                    Assert-QuietEqual $a.Data.stdout 92161;Assert-QuietEqual $a.Data.stderr 11000
                    Assert-QuietEqual $a.Completeness.Analysis $true
                    $null=Out-QuietResult $a
                }
                $after=Get-QuietEngine
                Assert-QuietEqual $after.Requests $before.Requests 'Offline analysis and delivery must not contact the engine'
                Assert-QuietEqual $r.Data $null
                $ref=New-QuietRecallReference $r -Stream stderr -Offset 2 -ByteCount 7
                $events=Get-QuietRecall $r -Reference $ref
                Assert-QuietEqual (($events|ForEach-Object ByteCount|Measure-Object -Sum).Sum) 7
            }
        }finally{Stop-QuietEngine;$env:QUIETCLI2_ENGINE_MODE=$oldMode}
    }
    $cases['Recall survives callback failures and preserves invalid UTF8 for byte reanalysis']={
        $r=quiet -AsObject -Recall -Output {throw 'independent parser defect'} dotnet $fixture emit 18000
        Assert-QuietEqual $r.Outcome Failed;Assert-QuietEqual $r.Recall.RetainedBytes 18000
        $a=Invoke-QuietRecall $r -StdoutMode Bytes -Data @{Count=0L} -Output {param($e,$r) $r.Data.Count+=$e.ByteCount}
        Assert-QuietEqual $a.Data.Count 18000
        $bad=quiet -AsObject -Recall -Output {} dotnet $fixture invalid
        Assert-QuietEqual $bad.Outcome Failed
        $fixed=Invoke-QuietRecall $bad -StdoutMode Bytes -Data @{Count=0L} -Output {param($e,$r) $r.Data.Count+=$e.ByteCount}
        Assert-QuietEqual $fixed.Data.Count 1
    }
    $cases['Recall policies expose gaps and partial analysis never claims completeness']={
        foreach($policy in @('Head','Tail','HeadAndTail')){
            $r=quiet -AsObject -Recall -RecallMaxBytes 9 -RecallPolicy $policy -StdoutMode Bytes -Output {} dotnet $fixture emit 100
            Assert-QuietEqual $r.Recall.RetainedBytes 9
            Assert-QuietEqual $r.Recall.OmittedBytes 91
            $rejected=$false;try{$null=Invoke-QuietRecall $r -Output {}}catch{$rejected=$true}
            Assert-QuietEqual $rejected $true
            $a=Invoke-QuietRecall $r -AllowPartial -Output {} -Complete {param($r) 99}
            Assert-QuietEqual $a.Data 99;Assert-QuietEqual $a.Completeness.Analysis $false
        }
    }
    $cases['Recall completion framing and native controls remain distinct']={
        $r=quiet -AsObject -Recall -RecordDelimiter ([string][char]0) -Output {} dotnet $fixture unicode
        $a=Invoke-QuietRecall $r -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r) $r.Data.Add($e.Text)}
        Assert-QuietEqual ($a.Data -join '|') 'é漢🙂|fin'
        $blocked=Invoke-QuietRecall $r -Output {param($e,$r) $r.WriteText('must not execute')}
        Assert-QuietEqual $blocked.Outcome Failed
        $nested=Invoke-QuietRecall $r -Output {$null=quiet -AsObject -Output {} dotnet --version}
        Assert-QuietEqual $nested.Outcome Failed
        $ignored=Invoke-QuietRecall $r -StdoutMode Bytes -RecordDelimiter $null -Output {param($e,$r) $r.MarkIgnored()}
        Assert-QuietEqual ($ignored.Cursor.DeclaredIgnoredSequences.Count -gt 0) $true
    }
    $cases['Recall native failure empty timeout and terminal retain their actual source status']={
        $r=quiet -AsObject -Recall -Output {} dotnet $fixture fail
        Assert-QuietEqual $r.Outcome Failed;Assert-QuietEqual $r.Recall.RetainedBytes 17
        $empty=quiet -AsObject -Recall -Output {} dotnet $fixture emit 0
        Assert-QuietEqual $empty.Recall.Events.Count 0;Assert-QuietEqual $empty.Recall.CaptureComplete $true
        $timeout=quiet -AsObject -Recall -TimeoutSeconds 0.2 -Output {} dotnet $fixture hang
        Assert-QuietEqual $timeout.Outcome Timeout
        Assert-QuietEqual $timeout.Recall.SourceComplete $false
        $cancel=quiet -AsObject -Recall -Interaction {param($r)$r.Cancel()} -Output {} dotnet $fixture hang
        Assert-QuietEqual $cancel.Outcome Cancelled;Assert-QuietEqual $cancel.Recall.SourceComplete $false
        $pty=quiet -AsObject -Recall -Transport Pty -Output {} dotnet $fixture terminal
        Assert-QuietEqual $pty.Outcome Success
        Assert-QuietEqual @($pty.Recall.Events|Where-Object Stream -NE terminal).Count 0
    }
    $cases['Recall export import comparison fixture and reducer are independent offline tools']={
        $r=quiet -AsObject -Recall -StdoutMode Bytes -Output {} dotnet $fixture emit 30
        $path=Join-Path $RunDirectory 'roundtrip.qrecall';Export-QuietRecall $r $path
        $imported=Import-QuietRecall $path -MaxBytes 30
        Assert-QuietEqual $imported.CaptureId $r.Recall.CaptureId
        $comparison=Compare-QuietRecallAnalysis $imported -First @{Output={param($e,$r) $r.Data.Count+=$e.ByteCount}} -Second @{Output={param($e,$r) $r.Data.Count+=$e.ByteCount}} -DataFactory {@{Count=0L}}
        Assert-QuietEqual $comparison.Equal $true
        $different=Compare-QuietRecallAnalysis $imported -First @{Complete={1}} -Second @{Complete={2}}
        Assert-QuietEqual $different.Equal $false
        $destination=Export-QuietRecallFixture $r (Join-Path $RunDirectory 'fixture')
        $rejected=$false;try{& (Join-Path $destination 'Regression.Tests.ps1')}catch{$rejected=$true};Assert-QuietEqual $rejected $true
        $reduced=Reduce-QuietRecall $imported -FailurePredicate {param($c) $c.RetainedBytes -gt 0} -MaxAttempts 8
        Assert-QuietEqual ($reduced.Capture.RetainedBytes -gt 0) $true
        Assert-QuietEqual $reduced.ProvenMinimal $false
    }
    $cases['Recall performance reports capture and reanalysis separately']={
        foreach($variant in @('Disabled','Bounded','All')){
            foreach($iteration in 1..3){
                $options=@();if($variant -ne 'Disabled'){$options=@('-Recall','-RecallMaxBytes',$(if($variant -eq 'All'){'All'}else{'64KiB'}))}
                $watch=[Diagnostics.Stopwatch]::StartNew()
                $r=quiet -AsObject @options -StdoutMode Bytes -Output {} dotnet $fixture emit 1048576
                Assert-QuietEqual $r.Outcome Success
                $metrics.Add(@{Variant=$variant;Iteration=$iteration;ElapsedMs=$watch.Elapsed.TotalMilliseconds;Allocation=$r.Measurement.Allocation;Received=1048576;Retained=$(if($variant -eq 'Disabled'){0}else{$r.Recall.RetainedBytes});DeliveryBytes=$null})
                if($variant -eq 'All'){
                    $a=Invoke-QuietRecall $r -Output {}
                    $metrics.Add(@{Variant='Reanalysis';Iteration=$iteration;ElapsedMs=$a.Execution.ElapsedMs;Allocation=$a.Measurement.Allocation;Received=0;Retained=$r.Recall.RetainedBytes;DeliveryBytes=$null})
                }
            }
        }
        Write-WorkspaceJson (Join-Path $RunDirectory 'recall-performance.json') $metrics.ToArray()
        $rtk=Invoke-QuietRecallRtkComparison -RunDirectory $RunDirectory
        Write-WorkspaceJson (Join-Path $RunDirectory 'recall-rtk.json') $rtk
    }
    $cases['SaveRecall persists all disk bytes independently of bounded memory and replays by id']={
        $root=Join-Path $RunDirectory 'durable-store'
        $saved=quiet -AsObject -SaveRecall -Recall -RecallMaxBytes 1024 -RecallName 'build-é' -RecallRoot $root -StdoutMode Bytes -StderrMode Bytes -Output {} dotnet $fixture mixed 16384 2048
        Assert-QuietEqual $saved.Outcome Success
        Assert-QuietEqual $saved.Recall.IsSaved $true
        Assert-QuietEqual $saved.Recall.RetainedBytes 18432
        Assert-QuietEqual $saved.Recall.MemoryCapture.RetainedBytes 1024
        Assert-QuietEqual $saved.Recall.CaptureId $saved.Recall.RecallId
        $id=$saved.Recall.RecallId
        $listed=@(Get-QuietSavedRecall -RecallRoot $root -RecallName 'build-*')
        Assert-QuietEqual $listed.Count 1;Assert-QuietEqual $listed[0].RecallId $id
        $before=Get-QuietEngine
        $analysis=quiet -AsObject -RecallId $id -RecallRoot $root -Data @{N=0L} -Output {param($e,$r)$r.Data.N+=$e.ByteCount} -Complete {param($r)@{Bytes=$r.Data.N}} -Projection {param($data,$budget)@{Final=$data.Bytes}}
        Assert-QuietEqual $analysis.Data.Bytes 18432
        $delivery=Out-QuietResult $analysis|ConvertFrom-Json
        Assert-QuietEqual $delivery.Data.Final 18432
        $after=Get-QuietEngine;Assert-QuietEqual $after.Requests $before.Requests
        $rejected=$false;try{$null=quiet -AsObject -RecallId $id -RecallRoot $root -Output {} dotnet $fixture emit 1}catch{$rejected=$true};Assert-QuietEqual $rejected $true
        $manifest=[IO.File]::ReadAllTextAsync((Join-Path $saved.Recall.StoragePath 'manifest.json')).GetAwaiter().GetResult()
        Assert-QuietEqual $manifest.Contains('FilePath') $false
        $worker=Join-Path $RunDirectory 'restart-recall.ps1'
        $code=@'
<#
.SYNOPSIS
Reanalyzes a saved identity in a fresh process without executable metadata.
.PARAMETER ModulePath
Selected Core manifest.
.PARAMETER Root
Durable test store.
.PARAMETER Id
Saved identity.
#>
param([string]$ModulePath,[string]$Root,[string]$Id)
$ErrorActionPreference='Stop'
Import-Module $ModulePath
$r=quiet -AsObject -RecallId $Id -RecallRoot $Root -Data @{N=0L} -Output {param($e,$r)$r.Data.N+=$e.ByteCount} -Complete {param($r)$r.Data.N+7}
if($r.Outcome -ne 'Success' -or $null -ne $r.Execution.Native){throw 'RestartReplayFailed'}
$r.Data|ConvertTo-Json -Compress
'@
        [void][IO.File]::WriteAllTextAsync($worker,$code.Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $module=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
        $r=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $worker -ModulePath $module -Root $root -Id $id
        Assert-QuietEqual $r.Outcome Success;Assert-QuietEqual $r.Data 18439
    }
    $cases['SaveRecall host crash recovers complete records in a fresh session']={
        $root=Join-Path $RunDirectory 'crash-store';$worker=Join-Path $RunDirectory 'crash-recall.ps1'
        $code=@'
<#
.SYNOPSIS
Exits the recording host deliberately after a complete journal append.
.PARAMETER ModulePath
Selected Core manifest.
.PARAMETER Root
Owned crash-test store.
.PARAMETER Fixture
Independent finite native producer.
#>
param([string]$ModulePath,[string]$Root,[string]$Fixture)
Import-Module $ModulePath
$null=quiet -AsObject -SaveRecall -RecallName crash -RecallRoot $Root -StdoutMode Bytes -Output {[Environment]::Exit(83)} dotnet $Fixture emit 32768
throw 'CrashCallbackNotExecuted'
'@
        [void][IO.File]::WriteAllTextAsync($worker,$code.Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $module=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
        $crash=quiet -AsObject -Role Infrastructure -TimeoutSeconds 20 -Output {} pwsh -File $worker -ModulePath $module -Root $root -Fixture $fixture
        Assert-QuietEqual $crash.Outcome Failed
        Assert-QuietEqual $crash.Execution.Native.ExitCode 83
        $entries=@(Get-QuietSavedRecall -RecallRoot $root -RecallName crash)
        Assert-QuietEqual $entries.Count 1;Assert-QuietEqual $entries[0].State Interrupted
        $replay=quiet -AsObject -RecallId $entries[0].RecallId -RecallRoot $root -Data @{N=0L} -Output {param($e,$r)$r.Data.N+=$e.ByteCount}
        Assert-QuietEqual ($replay.Data.N -gt 0 -and $replay.Data.N -le 32768) $true
        Assert-QuietEqual $replay.Recall.Recovered $true
        Assert-QuietEqual $replay.Completeness.Source $false
    }
    $cases['durable transport ZIP compression reports measurements and imports by stable id']={
        $root=Join-Path $RunDirectory 'zip-store'
        $r=quiet -AsObject -SaveRecall -RecallRoot $root -RecallName zipped -Zip -Compress 9 -StdoutMode Bytes -Output {} dotnet $fixture emit 65536
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Recall.Transport.CompressionLevel 9
        Assert-QuietEqual ($r.Recall.Transport.Ratio -gt 0 -and $r.Recall.Transport.Ratio -lt 1) $true
        $importRoot=Join-Path $RunDirectory 'zip-imports'
        $imported=Import-QuietRecall $r.Recall.Transport.Path -MaxBytes All -RecallRoot $importRoot
        Assert-QuietEqual $imported.RecallId $r.Recall.RecallId
        $analysis=Invoke-QuietRecall -RecallId $imported.RecallId -RecallRoot $importRoot -Data @{N=0L} -Output {param($e,$r)$r.Data.N+=$e.ByteCount}
        Assert-QuietEqual $analysis.Data.N 65536
        $copy=Export-QuietRecall $r -Path (Join-Path $RunDirectory 'transport-copy.zip') -Zip -Compress 0 -PassThru
        Assert-QuietEqual $copy.CompressionLevel 0
        $duplicate=quiet -AsObject -SaveRecall -RecallRoot $root -RecallName zipped -Output {} dotnet $fixture emit 1
        Assert-QuietEqual (@(Get-QuietSavedRecall -RecallRoot $root -RecallName zipped).Count) 2
        Assert-QuietEqual ($duplicate.Recall.RecallId -ne $r.Recall.RecallId) $true
    }
    $cases['disk failure remains visible while the finite native source is fully drained']={
        $r=quiet -AsObject -SaveRecall -RecallRoot (Join-Path $RunDirectory 'failed-store') -ReadBlockBytes 1024 -StdoutMode Bytes -Data @{N=0L;Calls=0} -Output {
            param($e,$r)
            $r.Data.N+=$e.ByteCount
            if($r.Data.N -eq $e.ByteCount){[void]$r.RecallWriter.DisposeAsync().GetAwaiter().GetResult()}
        } -Complete {param($r)$r.Data.Calls++} dotnet $fixture emit 32768
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Execution.Native.ExitCode 0
        Assert-QuietEqual $r.Data.N 32768;Assert-QuietEqual $r.Data.Calls 1
        Assert-QuietEqual $r.Recall.State Failed
        Assert-QuietEqual ($r.Recall.RecallId.Length -eq 32) $true
    }
    $cases['Recall companion development tools work in source-free packages']={
        $packages=Join-Path $RunDirectory 'recall-packages'
        $null=& (Join-Path $WorkspaceRoot 'scripts/New-WorkspacePackage.ps1') -WorkspaceRoot $WorkspaceRoot -OutputDirectory $packages
        Assert-QuietEqual (Test-Path (Join-Path $packages 'FrenchExDev2.QuietCli.Core.Tests.PoSh/recall-tools')) $false
        $worker=Join-Path $RunDirectory 'package-recall.ps1'
        $code=@'
<#
.SYNOPSIS
Checks packaged offline tools without source or orchestration helpers.
.PARAMETER PackageRoot
Extracted four-module package root.
#>
param([string]$PackageRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PackageRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
Import-Module (Join-Path $PackageRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -WarningAction SilentlyContinue
$r=quiet -AsObject -Recall -Output {} pwsh -Command "'fixture'"
if($r.Outcome -ne 'Success'){throw 'PackagedCaptureFailed'}
$comparison=Compare-QuietRecallAnalysis $r -First @{Complete={1}} -Second @{Complete={1}}
$reduction=Reduce-QuietRecall $r -FailurePredicate {param($c)$c.RetainedBytes -gt 0} -MaxAttempts 5
if(!$comparison.Equal -or $reduction.Capture.RetainedBytes -lt 1){throw 'PackagedToolsFailed'}
[pscustomobject]@{Equal=$comparison.Equal;ProvenMinimal=$reduction.ProvenMinimal}|ConvertTo-Json -Compress
'@
        [void][IO.File]::WriteAllTextAsync($worker,$code.Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $worker -PackageRoot $packages
        Assert-QuietEqual $r.Outcome Success (($r.Error|ConvertTo-Json -Compress))
        Assert-QuietEqual $r.Data.Equal $true
        $framework=if([Environment]::Version.Major -ge 11){'net11.0'}else{'net10.0'}
        $binary=Join-Path $packages ('FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/recall-tools/'+$framework+'/QuietCli.Recall.Tools.dll')
        $bytes=[IO.File]::ReadAllBytesAsync($binary).GetAwaiter().GetResult();$bytes[-1]=$bytes[-1] -bxor 1
        [void][IO.File]::WriteAllBytesAsync($binary,$bytes).GetAwaiter().GetResult()
        $broken=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)[void]$r.Data.Append($e.Text)} -Complete {param($r)$r.Data.ToString()} pwsh -File $worker -PackageRoot $packages
        Assert-QuietEqual $broken.Outcome Failed
        Assert-QuietEqual $broken.Data.Contains('RecallToolsBinaryIntegrityFailed') $true
    }
    $passed=0;$failed=0;$results=[Collections.Generic.List[object]]::new()
    foreach($case in $cases.GetEnumerator()){
        $errorText=$null
        try{& $case.Value;$passed++;$state='Passed'}catch{$failed++;$state='Failed';$errorText=$_.ToString()+"`n"+$_.ScriptStackTrace}
        $results.Add(@{Name=$case.Key;State=$state;Error=$errorText})
        if($OnProgress){& $OnProgress $case.Key $state $passed $failed}
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$passed;Failed=$failed;Cases=$results.ToArray();Performance=$metrics.ToArray()}
}
