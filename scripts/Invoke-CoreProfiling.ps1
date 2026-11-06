<#
.SYNOPSIS
Runs separate PowerShell line profiling and real CLR EventPipe collectors for every owned target PID.
.PARAMETER WorkspaceRoot
Local monorepo.
.PARAMETER RunDirectory
Completed integration run containing its owned bulk fixture.
.PARAMETER ProfilerModulePath
Pinned Profiler 4.3.0 manifest.
.PARAMETER ClrProfilerPath
Pinned dotnet-trace 10.0.750501 DLL.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot,[string]$RunDirectory,[string]$ProfilerModulePath,[string]$ClrProfilerPath)
$ErrorActionPreference='Stop'
$env:DOTNET_ROLL_FORWARD_TO_PRERELEASE='1'
. (Join-Path $PSScriptRoot 'Common.ps1')
$directory=Join-Path $RunDirectory 'profiling';[void][IO.Directory]::CreateDirectory($directory)
$repository=Join-Path $RunDirectory 'controlled-status/fixtures/bulk'
if(!(Test-Path (Join-Path $repository '.git')) -or !(Test-Path $ProfilerModulePath) -or !(Test-Path $ClrProfilerPath)){throw 'ProfilingPrerequisiteMissing'}
$runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$owned=[Collections.Generic.List[Diagnostics.Process]]::new();$collectors=[Collections.Generic.List[object]]::new()
$report=@{State='Running';ProfilerVersion='4.3.0';ClrProfilerVersion='10.0.750501';Instrumented=$true;PowerShellLineReport='powershell-lines.json';Collectors=@();Error=$null}
try{
    $arguments=@('-NoProfile','-File',('"'+(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Profiler.Target.ps1')+'"'),'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$directory+'"'),'-RepositoryPath',('"'+$repository+'"'),'-ProfilerModulePath',('"'+$ProfilerModulePath+'"'))
    $options=@{FilePath=$runner;ArgumentList=$arguments;PassThru=$true;RedirectStandardOutput=(Join-Path $directory 'target.stdout.log');RedirectStandardError=(Join-Path $directory 'target.stderr.log')}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $target=Start-Process @options;$owned.Add($target)
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(120)
    $ready=Join-Path $directory 'target-ready.json'
    while(!(Test-Path $ready)){
        if($target.HasExited -or [DateTimeOffset]::UtcNow -gt $deadline){throw 'ProfilerTargetStartupFailed'}
        [Threading.Tasks.Task]::Delay(50).GetAwaiter().GetResult()
    }
    $identity=Get-Content $ready -Raw -Encoding utf8|ConvertFrom-Json
    if($identity.PowerShellProcessId -ne $target.Id){throw 'ProfilerTargetIdentityMismatch'}
    $report.TargetIdentity=$identity
    foreach($processId in @($identity.PowerShellProcessId,$identity.EngineProcessId)|Select-Object -Unique){
        $path=Join-Path $directory ("clr-$processId.nettrace")
        $signal=Join-Path $directory ("clr-$processId.ready")
        $collectorArguments=@('-File',('"'+(Join-Path $PSScriptRoot 'Invoke-ClrCollector.ps1')+'"'),'-ClrProfilerPath',('"'+$ClrProfilerPath+'"'),'-TargetProcessId',[string]$processId,'-OutputPath',('"'+$path+'"'),'-ReadyPath',('"'+$signal+'"'))
        $options=@{FilePath=$runner;ArgumentList=$collectorArguments;PassThru=$true;RedirectStandardOutput=($path+'.stdout.log');RedirectStandardError=($path+'.stderr.log')}
        if($IsWindows){$options.WindowStyle='Hidden'}
        $process=Start-Process @options;$owned.Add($process)
        $collectors.Add(@{Process=$process;TargetProcessId=$processId;Trace=$path;Ready=$signal})
    }
    foreach($collector in $collectors){
        while(!(Test-Path $collector.Ready) -or !(Test-Path $collector.Trace) -or (Get-Item $collector.Trace).Length -lt 32){
            if($collector.Process.HasExited -or [DateTimeOffset]::UtcNow -gt $deadline){throw 'ClrCollectorAttachFailed'}
            [Threading.Tasks.Task]::Delay(50).GetAwaiter().GetResult()
        }
        if($collector.Process.HasExited){throw 'ClrCollectorEndedBeforeWorkload'}
    }
    [void][IO.File]::WriteAllTextAsync((Join-Path $directory 'release'),'recording',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    foreach($process in $owned){
        while(!$process.HasExited){if([DateTimeOffset]::UtcNow -gt $deadline){throw 'ProfilingDeadlineExceeded'};[Threading.Tasks.Task]::Delay(100).GetAwaiter().GetResult()}
        if($process.ExitCode -ne 0){throw 'ProfilingOwnedProcessFailed'}
    }
    $targetResult=Get-Content (Join-Path $directory 'target-result.json') -Raw -Encoding utf8|ConvertFrom-Json
    if($targetResult.State -cne 'Success' -or $targetResult.GitModuleLoaded){throw 'ProfiledTargetFailed'}
    $reports=@(foreach($collector in $collectors){
        $execution=Get-Content ($collector.Trace+'.collector.json') -Raw -Encoding utf8|ConvertFrom-Json
        if(!$execution.Ready -or $execution.Execution.Outcome -cne 'Success'){throw 'ClrCollectionIncomplete'}
        $conversion=Invoke-CiProcess -FilePath dotnet -ArgumentList @('--roll-forward','LatestMajor',$ClrProfilerPath,'convert',$collector.Trace,'--format','Speedscope','--output',($collector.Trace+'.converted')) -TimeoutSeconds 60 -OnOutput {param($event,$state)}
        if($conversion.Outcome -ne 'Success'){throw 'ClrTraceConversionFailed'}
        $converted=@(Get-ChildItem -LiteralPath $directory -File -Filter (([IO.Path]::GetFileName($collector.Trace))+'*.speedscope.json'))
        if($converted.Count -ne 1){throw 'ClrSpeedscopeMissing'}
        $view=Get-Content $converted[0].FullName -Raw -Encoding utf8|ConvertFrom-Json
        if(!$view.profiles.Count -or !$view.shared.frames.Count){throw 'ClrManagedFramesMissing'}
        $buckets=@{CoreCSharp=0;PowerShellRuntime=0;DotNetLibraries=0;OtherOrUnresolved=0}
        foreach($frame in $view.shared.frames){
            if($frame.name -match 'FrenchExDev2\.QuietCli'){$buckets.CoreCSharp++}
            elseif($frame.name -match 'System\.Management\.Automation|Microsoft\.PowerShell'){$buckets.PowerShellRuntime++}
            elseif($frame.name -match 'System\.|CoreLib'){$buckets.DotNetLibraries++}
            else{$buckets.OtherOrUnresolved++}
        }
        @{TargetProcessId=$collector.TargetProcessId;Trace=[IO.Path]::GetFileName($collector.Trace);Speedscope=$converted[0].Name;ObservedFrameNames=$buckets;TraceBytes=(Get-Item $collector.Trace).Length;SHA256=(Get-FileHash $collector.Trace -Algorithm SHA256).Hash}
    })
    if($identity.EngineMode -eq 'Process' -and $reports.Count -ne 2){throw 'IsolatedEngineClrTraceMissing'}
    if($identity.EngineMode -eq 'InProcess' -and $reports.Count -ne 1){throw 'IntegratedClrTraceIdentityMismatch'}
    $report.Collectors=$reports;$report.State='Success'
    $report.Limits='PS line self/inclusive wall time and CLR sampled stacks are different observations. Frame-name buckets identify code origins, not additive CPU percentages. CLR conversion preserves raw traces and sample timelines; unresolved/native Git work is not relabeled as C#.'
}catch{
    $report.State='Failed';$report.Error=$_.Exception.Message
    throw
}finally{
    foreach($process in $owned){if(!$process.HasExited){try{$process.Kill($true)}catch{}}}
    Write-WorkspaceJson (Join-Path $directory 'summary.json') $report
}
[pscustomobject]$report
