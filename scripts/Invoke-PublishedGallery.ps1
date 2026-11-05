# Objectif : Vérifier une vraie installation PSGallery dans un processus isolé avec le moniteur visible partagé.
#requires -Version 7.6
<#
.SYNOPSIS
Validates a published version with real dependency resolution, without changing the user's installed modules.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Version
Exact published version.
.PARAMETER Headless
Reserved for CI without a desktop.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z][A-Za-z0-9-]*)?$')][string]$Version,[switch]$Headless)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)
$run=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'gallery-validation') ([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
[void][IO.Directory]::CreateDirectory($run)
$runner=(Get-Command pwsh -CommandType Application|Select-Object -First 1).Source
$workerPath=Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.Tests.PoSh/audit/Probe-PublishedGallery.ps1
$arguments=@('-File',('"'+$workerPath+'"'),'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$run+'"'),'-Version',$Version)
$options=@{FilePath=$runner;ArgumentList=$arguments;PassThru=$true;RedirectStandardOutput=(Join-Path $run worker.stdout.log);RedirectStandardError=(Join-Path $run worker.stderr.log)}
if($IsWindows){$options.WindowStyle='Hidden'}elseif(!$Headless){throw 'Use the Windows host launcher for a local visible monitor.'}
$worker=Start-Process @options;$monitor=$null
$monitorPath=Join-Path $PSScriptRoot Watch-Tests.ps1
if(!$Headless){$monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',('"'+$monitorPath+'"'),'-RunDirectory',('"'+$run+'"')) -PassThru}
"Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$run`""
$summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $run -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds 300
[pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$run;Proof=$summary.Proof}
if($summary.State.State -ne 'Success'){throw ('Published gallery validation failed: '+$run)}
