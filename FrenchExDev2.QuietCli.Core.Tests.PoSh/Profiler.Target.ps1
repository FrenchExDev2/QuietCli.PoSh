#requires -Version 7.6
<#
.SYNOPSIS
Profiles a Core-only workload after collectors attach; writes source-level evidence separately from benchmarks.
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
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
. (Join-Path $WorkspaceRoot 'scripts/TestConfiguration.ps1')
Initialize-QuietTestConfiguration -DatabasePath (Join-Path $RunDirectory 'profile.sqlite') -Hosting $(if($env:QUIETCLI_EXPECT_ENGINE_MODE){$env:QUIETCLI_EXPECT_ENGINE_MODE}else{'Auto'})
$env:GIT_OPTIONAL_LOCKS='0';$env:GIT_TERMINAL_PROMPT='0'
Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
$null=Import-Module $ProfilerModulePath -PassThru
$module=Get-Module Profiler
if($module.Version -ne [version]'4.3.0' -or (Get-Module FrenchExDev2.QuietCli.Git.PoSh) -or @(Get-QuietHandler).Count){throw 'UnexpectedProfilerTargetModules'}
$engine=Get-QuietEngine
Write-WorkspaceJson (Join-Path $RunDirectory 'target-ready.json') @{PowerShellProcessId=$PID;EngineProcessId=$engine.Engine.ProcessId;EngineMode=$engine.Mode;RuntimeIdentifier=$engine.Engine.RuntimeIdentifier;PowerShellVersion=$PSVersionTable.PSVersion.ToString()}
$deadline=[DateTimeOffset]::UtcNow.AddSeconds(90)
while(!(Test-Path (Join-Path $RunDirectory 'release'))){if([DateTimeOffset]::UtcNow -gt $deadline){throw 'ProfilerAttachDeadline'};[Threading.Tasks.Task]::Delay(50).GetAwaiter().GetResult()}
try{
    $workload=Join-Path $PSScriptRoot 'Profiler.Workload.ps1'
    $trace=Trace-Script -ScriptBlock { & $workload -RepositoryPath $RepositoryPath } -ExportPath (Join-Path $RunDirectory 'powershell.speedscope.json') 6> (Join-Path $RunDirectory 'profiler.log')
    $coreRoot=[IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh'))+[IO.Path]::DirectorySeparatorChar
    $lines=@(foreach($line in $trace.AllLines){
        if($line.HitCount -le 0){continue}
        $path=[string]$line.Path
        $category=if($path -eq $workload){'UserCallbacksAndWorkload'}elseif($path.StartsWith($coreRoot,[StringComparison]::OrdinalIgnoreCase)){'CorePowerShellFacade'}elseif($path.StartsWith($PSHOME,[StringComparison]::OrdinalIgnoreCase)){'PowerShellModules'}else{'ProfilerOrOtherScripts'}
        @{Category=$category;Path=$path;Line=$line.Line;Hits=$line.HitCount;SelfMs=$line.SelfDuration.TotalMilliseconds;InclusiveMs=$line.Duration.TotalMilliseconds}
    })
    if(!$lines.Count -or 'UserCallbacksAndWorkload' -notin $lines.Category -or 'CorePowerShellFacade' -notin $lines.Category){throw 'PowerShellProfileCoverageMissing'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'powershell-lines.json') @{Instrumented=$true;ProfilerVersion='4.3.0';Lines=$lines;Limits='Line wall/self durations include untraced managed calls and waits. CLR traces supply managed stacks; these metrics are not an additive CPU partition or comparable to uninstrumented benchmark samples.'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'target-result.json') @{State='Success';Lines=$lines.Count;Engine=$engine;GitModuleLoaded=[bool](Get-Module FrenchExDev2.QuietCli.Git.PoSh)}
}finally{Stop-QuietEngine}
