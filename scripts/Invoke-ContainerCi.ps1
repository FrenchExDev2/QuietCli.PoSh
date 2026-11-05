# Objectif : Démarrer un run Podman avec les mêmes suites et un moniteur visible sur l’hôte Windows.
#requires -Version 7.6
<#
.SYNOPSIS
Runs existing prepared images; no pull, host installation or implicit dependency download.
.PARAMETER WorkspaceRoot
QuietCli2 root.
.PARAMETER Image
Prepared local image containing PowerShell, .NET 11 RC and Git.
.PARAMETER Platform
Platform label for the monitor.
.PARAMETER Headless
CI-only mode without a desktop window.
.PARAMETER TimeoutSeconds
Maximum worker duration, including staging and cleanup.
.PARAMETER ExpectedRuntimeIdentifier
Required guest RID; prevents a different architecture from being accepted as ARM qualification.
.PARAMETER Suite
Companion scope or native C mutation campaign selected by the dependency-aware workflow.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$Image,[ValidateSet('alpine','debian')][string]$Platform,[switch]$Headless,[ValidateRange(1,7200)][int]$TimeoutSeconds=900,[ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier,[ValidateSet('Core','Git','All','Mutation')][string]$Suite='All')
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$run=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'containers') ($Platform+'-'+[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
[void][IO.Directory]::CreateDirectory($run)
$runner=(Get-Command pwsh -CommandType Application|Select-Object -First 1).Source
$arguments=@('-File',('"'+(Join-Path $PSScriptRoot 'Invoke-ContainerWorker.ps1')+'"'),'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$run+'"'),'-Image',('"'+$Image+'"'),'-Platform',$Platform)
if($ExpectedRuntimeIdentifier){$arguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
$arguments+=@('-Suite',$Suite)
$options=@{FilePath=$runner;ArgumentList=$arguments;PassThru=$true;RedirectStandardOutput=(Join-Path $run 'worker.stdout.log');RedirectStandardError=(Join-Path $run 'worker.stderr.log')};if($IsWindows){$options.WindowStyle='Hidden'}
if(!$Headless -and !$IsWindows){throw 'A local visible monitor requires the Windows host launcher.'}
$worker=Start-Process @options
$monitor=$null
if(!$Headless){$monitorPath=Join-Path $PSScriptRoot 'Watch-Tests.ps1';$monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',('"'+$monitorPath+'"'),'-RunDirectory',('"'+$run+'"')) -PassThru;"Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$run`""}
$summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $run -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
[pscustomobject]@{State=$summary.State.State;Platform=$summary.State.Platform;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$run}
if($summary.State.State -ne 'Success'){throw "Container tests failed: $run"}
