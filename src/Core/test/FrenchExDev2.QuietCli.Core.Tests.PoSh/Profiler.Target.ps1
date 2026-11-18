#requires -Version 7.6
<#
.SYNOPSIS
Profiles Core-only workloads one by one after collectors attach; writes source-level evidence separately from benchmarks.
.PARAMETER WorkspaceRoot
Local monorepo.
.PARAMETER RunDirectory
Owned profile artifact directory and handshake files.
.PARAMETER RepositoryPath
Owned completed bulk fixture.
.PARAMETER ProfilerModulePath
Explicit checksum-pinned Profiler 4.3.0 manifest.
#>
param([string]$WorkspaceRoot,[string]$RunDirectory,[string]$RepositoryPath,[string]$ProfilerModulePath)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false);[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/TestConfiguration.psm1') -DisableNameChecking -ErrorAction Stop
Initialize-QuietTestConfiguration -DatabasePath (Join-Path $RunDirectory 'profile.sqlite') -Hosting $(if($env:QUIETCLI_EXPECT_ENGINE_MODE){$env:QUIETCLI_EXPECT_ENGINE_MODE}else{'Auto'})
$env:GIT_OPTIONAL_LOCKS='0';$env:GIT_TERMINAL_PROMPT='0'
Import-Module (Join-Path $WorkspaceRoot 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
$null=Import-Module $ProfilerModulePath -PassThru
$module=Get-Module Profiler
if($module.Version -ne [version]'4.3.0' -or (Get-Module FrenchExDev2.QuietCli.Git.PoSh) -or @(Get-QuietHandler).Count){throw 'UnexpectedProfilerTargetModules'}
$engine=Get-QuietEngine
Write-WorkspaceJson (Join-Path $RunDirectory 'target-ready.json') @{PowerShellProcessId=$PID;EngineProcessId=$engine.Engine.ProcessId;EngineMode=$engine.Mode;RuntimeIdentifier=$engine.Engine.RuntimeIdentifier;PowerShellVersion=$PSVersionTable.PSVersion.ToString()}
$deadline=[DateTimeOffset]::UtcNow.AddSeconds(90)
while(!(Test-Path (Join-Path $RunDirectory 'release'))){if([DateTimeOffset]::UtcNow -gt $deadline){throw 'ProfilerAttachDeadline'};[Threading.Tasks.Task]::Delay(50).GetAwaiter().GetResult()}
try{
    $workload=Join-Path $PSScriptRoot 'Profiler.Workload.ps1'
    $coreRoot=[IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh'))+[IO.Path]::DirectorySeparatorChar
    # Each workload gets its own trace, so its lines and iteration times never mix with another workload's.
    $plan=@(
        @{Name='GitTransport';Iterations=8;Scope='quiet git status --porcelain=v2 -z bytes of the bulk fixture, -Output and -Complete'}
        @{Name='Framing';Iterations=8;Scope='Compiled NUL framing of 128 blocks of 16 KiB, 64-byte records'}
        @{Name='Metadata';Iterations=4;Scope='Four quiet git --version calls and 16 Get-QuietEngine queries'}
        @{Name='Events';Iterations=4;Scope='Emit of 256 events: 0 listeners, 1 listener with collection, 4 listeners'}
    )
    $lines=[Collections.Generic.List[object]]::new();$workloads=[Collections.Generic.List[object]]::new()
    foreach($step in $plan){
        $samples=[Collections.Generic.List[double]]::new()
        $speedscope='powershell.'+$step.Name+'.speedscope.json'
        $start=[DateTimeOffset]::UtcNow
        $trace=Trace-Script -ScriptBlock { & $workload -RepositoryPath $RepositoryPath -Workload $step.Name -Iterations $step.Iterations -Samples $samples } -ExportPath (Join-Path $RunDirectory $speedscope) 6>> (Join-Path $RunDirectory 'profiler.log')
        $end=[DateTimeOffset]::UtcNow
        if($samples.Count -ne $step.Iterations){throw ('PowerShellWorkloadIncomplete: '+$step.Name)}
        foreach($line in $trace.AllLines){
            if($line.HitCount -le 0){continue}
            $path=[string]$line.Path
            $category=if($path -eq $workload){'UserCallbacksAndWorkload'}elseif($path.StartsWith($coreRoot,[StringComparison]::OrdinalIgnoreCase)){'CorePowerShellFacade'}elseif($path.StartsWith($PSHOME,[StringComparison]::OrdinalIgnoreCase)){'PowerShellModules'}else{'ProfilerOrOtherScripts'}
            $lines.Add(@{Workload=$step.Name;Category=$category;Path=$path;Line=$line.Line;Hits=$line.HitCount;SelfMs=$line.SelfDuration.TotalMilliseconds;InclusiveMs=$line.Duration.TotalMilliseconds})
        }
        $workloads.Add(@{Name=$step.Name;Scope=$step.Scope;Iterations=$step.Iterations;SamplesMs=$samples.ToArray();Speedscope=$speedscope;StartUtc=$start.ToString('o');EndUtc=$end.ToString('o')})
    }
    if(!$lines.Count -or 'UserCallbacksAndWorkload' -notin $lines.Category -or 'CorePowerShellFacade' -notin $lines.Category){throw 'PowerShellProfileCoverageMissing'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'powershell-lines.json') @{Instrumented=$true;ProfilerVersion='4.3.0';Lines=$lines.ToArray();Workloads=$workloads.ToArray();NotProfiled=@(@{Name='ImportFirstCall';Reason='Collectors attach after module import and engine start.'});Limits='Line wall/self durations include untraced managed calls and waits. CLR traces supply managed stacks for the whole run, not per workload; these metrics are not an additive CPU partition or comparable to uninstrumented benchmark samples.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'target-result.json') @{State='Success';Lines=$lines.Count;Workloads=@($workloads|ForEach-Object {$_.Name});Engine=$engine;GitModuleLoaded=[bool](Get-Module FrenchExDev2.QuietCli.Git.PoSh)}
}finally{Stop-QuietEngine}
