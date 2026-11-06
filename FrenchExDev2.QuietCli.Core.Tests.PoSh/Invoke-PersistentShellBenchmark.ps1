#requires -Version 7.6
<#
.SYNOPSIS
Compares fresh PowerShell processes, duplex persistent sessions and retained Core result objects.
.DESCRIPTION
Loads only the selected Core module. Uses normal profiles and local pipes, never the Git
business module or Git test companion. Reports include process startup, profile, Core import,
local request/response overhead and shutdown, but exclude Codex tool transport and model time.
.PARAMETER Iterations
Retained paired repetitions after one discarded warm-up triple.
.PARAMETER CommandCounts
Sequence lengths, serialized to workers as a comma-separated list.
.PARAMETER RunDirectory
New report directory; defaults to the shared temporary report root.
.PARAMETER TimeoutSeconds
Whole-run deadline enforced by the launcher.
.PARAMETER Role
Internal launcher, coordinator or stdin-driven session role.
.PARAMETER Repository
Internal owned fixture path.
.PARAMETER Mode
Internal session policy: execute each time or retain the first result.
#>
[CmdletBinding()]
param(
    [ValidateRange(1,100)][int]$Iterations=7,
    [ValidatePattern('^[1-9][0-9]*(,[1-9][0-9]*)*$')][string]$CommandCounts='1,5,10,20',
    [string]$RunDirectory,
    [ValidateRange(30,7200)][int]$TimeoutSeconds=1800,
    [ValidateSet('Launch','Coordinator','Session')][string]$Role='Launch',
    [string]$Repository,
    [ValidateSet('Execute','Retain')][string]$Mode='Execute'
)
$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest=Join-Path $workspace 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
$runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$self=$PSCommandPath
. (Join-Path $PSScriptRoot 'PersistentShell.Support.ps1')
. (Join-Path $workspace 'scripts/Common.ps1')
$counts=@($CommandCounts.Split(',')|ForEach-Object {[int]$_})
if(@($counts|Where-Object {$_ -gt 100}).Count){throw 'PersistentCommandCountExceeds100'}

if($Role -eq 'Session'){
    $importWatch=[Diagnostics.Stopwatch]::StartNew()
    Import-Module $manifest -ErrorAction Stop
    $loaded=Get-Module FrenchExDev2.QuietCli.Core.PoSh
    if($loaded.ModuleBase -ne [IO.Path]::GetDirectoryName($manifest)){throw 'PersistentWrongCoreModule'}
    if(Get-Module '*QuietCli*' | Where-Object Name -NE 'FrenchExDev2.QuietCli.Core.PoSh'){throw 'PersistentUnexpectedCompanion'}
    $importWatch.Stop()
    $token=[guid]::NewGuid().ToString('N');$index=0;$executions=0;$retained=$null;$reference=$null
    try{
        [Console]::Out.WriteLine('@@BENCH@@'+(ConvertTo-Json @{Kind='Ready';Token=$token;ProcessId=$PID;ImportMs=$importWatch.Elapsed.TotalMilliseconds;PowerShell=$PSVersionTable.PSVersion.ToString();Runtime=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;CorePath=$loaded.Path;Configuration=(Get-QuietCliConfiguration).Path} -Compress))
        while($null -ne ($request=[Console]::In.ReadLineAsync().GetAwaiter().GetResult())){
            if($request -cne 'RUN'){throw 'PersistentUnknownRequest'}
            $watch=[Diagnostics.Stopwatch]::StartNew();$index++
            if($Mode -eq 'Execute' -or $null -eq $retained){$retained=Invoke-QuietPersistentStatus $Repository;$executions++;$reference=$retained}
            Assert-QuietPersistentResult $retained (Get-QuietPersistentOracle)
            $delivery=FrenchExDev2.QuietCli.Core.PoSh\ConvertTo-QuietJson $retained -MaxItems 8 -MaxOutputBytes 4096
            $watch.Stop();$process=Get-Process -Id $PID
            $frame=@{Kind='Sample';Index=$index;Token=$token;ProcessId=$PID;SameReference=[object]::ReferenceEquals($retained,$reference);NativeExecutions=$executions;CommandMs=$watch.Elapsed.TotalMilliseconds;DeliveryBytes=[Text.Encoding]::UTF8.GetByteCount($delivery);WorkingSetBytes=$process.WorkingSet64;PrivateBytes=$process.PrivateMemorySize64;Bytes=$retained.Data.Bytes;Records=$retained.Data.Records;SHA256=$retained.Data.SHA256}
            [Console]::Out.WriteLine('@@BENCH@@'+(ConvertTo-Json $frame -Compress))
        }
    }finally{Stop-QuietEngine}
    return
}

if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $workspace 'tests') ('persistent-shell-'+[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))}
$RunDirectory=[IO.Path]::GetFullPath($RunDirectory,$PWD.Path)
if($Role -eq 'Launch'){
    if(!$IsWindows){throw 'PersistentLocalBenchmarkRequiresWindowsVisibleMonitor'}
    if(Test-Path -LiteralPath $RunDirectory){throw 'PersistentRunDirectoryExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $workerArgs=@('-File',('"'+$self+'"'),'-Role','Coordinator','-RunDirectory',('"'+$RunDirectory+'"'),'-Iterations',"$Iterations",'-CommandCounts',$CommandCounts)
    $worker=Start-Process -FilePath $runner -WindowStyle Hidden -ArgumentList $workerArgs -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log') -PassThru
    $monitorPath=Join-Path $workspace 'scripts/Watch-Tests.ps1'
    $monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',('"'+$monitorPath+'"'),'-RunDirectory',('"'+$RunDirectory+'"')) -PassThru
    Write-Host "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    $summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $workspace -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
    [pscustomobject]@{State=$summary.State.State;RunDirectory=$RunDirectory;Statistics=$summary.Statistics;Comparisons=$summary.Comparisons}
    if($summary.State.State -ne 'Success'){throw "Persistent benchmark failed: $RunDirectory"}
    return
}

$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Persistent PowerShell benchmark';Workspace=$workspace;ProjectDirectory=(Split-Path $manifest -Parent);Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;State='Running';Passed=0;Failed=0;Case='Preparing isolated configuration and fixture';Error=$null}
$samples=[Collections.Generic.List[object]]::new();$statistics=@();$comparisons=@();$validation=$null
$previousConfig=[Environment]::GetEnvironmentVariable('QUIETCLI_CONFIG_DIRECTORY')
$gitEnvironment=@{}
try{
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
    $env:QUIETCLI_CONFIG_DIRECTORY=Join-Path $RunDirectory 'configuration-coordinator'
    Import-Module $manifest -ErrorAction Stop
    $null=Initialize-QuietPersistentConfiguration $env:QUIETCLI_CONFIG_DIRECTORY -Activate
    . (Join-Path $PSScriptRoot 'Import.Tests.ps1')
    . (Join-Path $PSScriptRoot 'PersistentShell.Tests.ps1')
    $validation=@{Statistics=(Test-QuietImportStatistics);Contracts=(Test-QuietPersistentContracts)}
    $hooks=Join-Path $RunDirectory 'empty-hooks';[void][IO.Directory]::CreateDirectory($hooks)
    $gitConfig=Join-Path $RunDirectory 'fixture.gitconfig'
    [void][IO.File]::WriteAllTextAsync($gitConfig,"[core]`n hooksPath = $($hooks.Replace('\','/'))`n autocrlf = false`n[commit]`n gpgsign = false`n[init]`n templateDir = $($hooks.Replace('\','/'))`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $gitEnvironment=@{GIT_CONFIG_GLOBAL=$gitConfig;GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_COUNT='0';GIT_CEILING_DIRECTORIES=$RunDirectory;GIT_TERMINAL_PROMPT='0';GIT_OPTIONAL_LOCKS='0';GIT_AUTHOR_NAME='Persistent shell fixture';GIT_COMMITTER_NAME='Persistent shell fixture';GIT_AUTHOR_EMAIL='fixture@example.invalid';GIT_COMMITTER_EMAIL='fixture@example.invalid';GIT_AUTHOR_DATE='2020-01-01T00:00:00+0000';GIT_COMMITTER_DATE='2020-01-01T00:00:00+0000';LC_ALL='C';LANG='C'}
    foreach($name in @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_CONFIG_PARAMETERS','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_TEMPLATE_DIR')){Remove-Item -LiteralPath ('Env:'+$name) -ErrorAction SilentlyContinue}
    $repository=New-QuietGitRepositoryFixture $RunDirectory $gitEnvironment
    [void][IO.File]::WriteAllTextAsync((Join-Path $repository 'file.txt'),"changed`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [void][IO.File]::WriteAllTextAsync((Join-Path $repository 'é漢 space.txt'),"untracked`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()

    function Invoke-BenchmarkSession {
        <#
        .SYNOPSIS
        Launches one normal-profile PowerShell and sends each next RUN only after its prior reply.
        .PARAMETER Count
        Number of sequential requests.
        .PARAMETER Policy
        Execute or Retain policy.
        #>
        param([int]$Count,[string]$Policy)
        $config=Join-Path $RunDirectory ('configuration-'+[guid]::NewGuid().ToString('N'))
        $null=Initialize-QuietPersistentConfiguration $config
        $environment=$gitEnvironment.Clone();$environment.QUIETCLI_CONFIG_DIRECTORY=$config
        $data=@{Ready=$null;Frames=[Collections.Generic.List[object]]::new();ExpectedCount=$Count;Policy=$Policy;SentAt=0L;Diagnostics=[Collections.Generic.Queue[string]]::new()}
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $result=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Environment $environment -RecordDelimiter "`n" -Data $data -Interaction {param($runtime)} -Output {
            param($event,$runtime)
            $data=$runtime.Data
            if($event.Stream -ne 'stdout' -or !$event.Text.StartsWith('@@BENCH@@')){
                if($data.Diagnostics.Count -ge 8){$null=$data.Diagnostics.Dequeue()};$data.Diagnostics.Enqueue($event.Text);return
            }
            $frame=$event.Text.Substring(9)|ConvertFrom-Json
            if($frame.Kind -eq 'Ready'){
                if($null -ne $data.Ready){throw 'PersistentDuplicateReady'}
                $data.Ready=$frame
            }else{
                if($null -eq $data.Ready){throw 'PersistentResponseBeforeReady'}
                Assert-QuietPersistentFrame $frame ($data.Frames.Count+1) $data.Ready.Token $data.Ready.ProcessId $data.Policy
                $frame|Add-Member RoundTripMs ([Diagnostics.Stopwatch]::GetElapsedTime($data.SentAt).TotalMilliseconds)
                $data.Frames.Add($frame)
            }
            if($data.Frames.Count -lt $data.ExpectedCount){$data.SentAt=[Diagnostics.Stopwatch]::GetTimestamp();$runtime.WriteText("RUN`n")}else{$runtime.CompleteInput()}
        } -FilePath $runner -ArgumentList @('-NoLogo','-NonInteractive','-File',$self,'-Role','Session','-Repository',$repository,'-Mode',$Policy)
        $watch.Stop()
        if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $data.Frames.Count -ne $Count){throw ('PersistentSessionFailed: '+($result.Error|ConvertTo-Json -Compress)+' / '+($data.Diagnostics.ToArray() -join ' | '))}
        if([IO.Path]::GetFullPath($data.Ready.Configuration) -ne (Join-Path $config 'config.yaml')){throw 'PersistentConfigurationNotIsolated'}
        [pscustomobject]@{ElapsedMs=$watch.Elapsed.TotalMilliseconds;Ready=$data.Ready;Frames=$data.Frames.ToArray()}
    }

    foreach($count in $counts){
        for($iteration=0;$iteration -le $Iterations;$iteration++){
            $order=if($iteration%2){@('Retained','Persistent','Fresh')}else{@('Fresh','Persistent','Retained')}
            foreach($arm in $order){
                $state.Case="Count $count | repetition $iteration/$Iterations | $arm";Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
                $sessions=@(if($arm -eq 'Fresh'){foreach($number in 1..$count){Invoke-BenchmarkSession 1 Execute}}else{Invoke-BenchmarkSession $count $(if($arm -eq 'Retained'){'Retain'}else{'Execute'})})
                $frames=@($sessions|ForEach-Object {$_.Frames})
                $sample=[pscustomobject]@{Arm=$arm;CommandCount=$count;Iteration=$iteration;ElapsedMs=($sessions.ElapsedMs|Measure-Object -Sum).Sum;ImportMs=($sessions.Ready.ImportMs|Measure-Object -Sum).Sum;FirstCommandMs=$frames[0].CommandMs;SubsequentCommandMs=@($frames|Select-Object -Skip 1|ForEach-Object CommandMs);MaxWorkingSetBytes=($frames.WorkingSetBytes|Measure-Object -Maximum).Maximum;MaxPrivateBytes=($frames.PrivateBytes|Measure-Object -Maximum).Maximum;Sessions=$sessions}
                $state.Passed++;Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
                if($iteration){$samples.Add($sample);Write-WorkspaceJson (Join-Path $RunDirectory 'samples.json') $samples.ToArray()}
            }
        }
    }
    $statistics=@(foreach($count in $counts){foreach($arm in @('Fresh','Persistent','Retained')){
        $subset=@($samples|Where-Object {$_.Arm -eq $arm -and $_.CommandCount -eq $count})
        [pscustomobject]@{CommandCount=$count;Arm=$arm;ElapsedMs=(Get-QuietImportStatistics @($subset.ElapsedMs));ImportMs=(Get-QuietImportStatistics @($subset.ImportMs));MaxWorkingSetBytes=(Get-QuietImportStatistics @($subset.MaxWorkingSetBytes));MaxPrivateBytes=(Get-QuietImportStatistics @($subset.MaxPrivateBytes))}
    }})
    $comparisons=@(foreach($count in $counts){foreach($arm in @('Persistent','Retained')){
        $pairs=@(foreach($iteration in 1..$Iterations){$fresh=$samples|Where-Object {$_.CommandCount -eq $count -and $_.Iteration -eq $iteration -and $_.Arm -eq 'Fresh'};$other=$samples|Where-Object {$_.CommandCount -eq $count -and $_.Iteration -eq $iteration -and $_.Arm -eq $arm};[pscustomobject]@{Iteration=$iteration;SavedMs=$fresh.ElapsedMs-$other.ElapsedMs;ReductionPercent=100*($fresh.ElapsedMs-$other.ElapsedMs)/$fresh.ElapsedMs;Speedup=$fresh.ElapsedMs/$other.ElapsedMs}})
        [pscustomobject]@{CommandCount=$count;ComparedToFresh=$arm;SavedMs=(Get-QuietImportStatistics @($pairs.SavedMs));ReductionPercent=(Get-QuietImportStatistics @($pairs.ReductionPercent));Speedup=(Get-QuietImportStatistics @($pairs.Speedup));Pairs=$pairs}
    }})
    $state.State='Success';$state.Case='All sequences validated against the literal fixture oracle'
}catch{$state.State='Failed';$state.Failed++;$state.Error=$_.Exception.ToString();throw}
finally{
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    $report=@{State=$state;Iterations=$Iterations;WarmupTriplesPerCount=1;CommandCounts=$counts;Statistics=$statistics;Comparisons=$comparisons;Samples=$samples.ToArray();Validation=$validation;Repository=$repository;PowerShell=$PSVersionTable.PSVersion.ToString();CLR=[Environment]::Version.ToString();ScriptSHA256=(Get-FileHash -LiteralPath $self -Algorithm SHA256).Hash;Limits='Local pipes and normal profiles; elapsed includes parent QuietCli dispatch, child startup/profile/import, sequential request/reply and shutdown. Configuration creation and fixture setup are outside samples. Fresh OS caches are not enforced. Codex tool latency, model time, PTY echo, parent memory and aggregate engine-process memory are not measured. Memory is an observed child snapshot, not a retained-memory guarantee. Retained saves native executions and is a separate optimization. No speed threshold. Small iteration counts give descriptive p95 only.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') $report
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
    if(Get-Module FrenchExDev2.QuietCli.Core.PoSh){Stop-QuietEngine}
    [Environment]::SetEnvironmentVariable('QUIETCLI_CONFIG_DIRECTORY',$previousConfig)
}
