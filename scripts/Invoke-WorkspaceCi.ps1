# Objectif : Démarrer les tests en arrière-plan et leur fenêtre de suivi, puis rendre les rapports persistants.
#requires -Version 7.6
<#
.SYNOPSIS
Runs companion suites with a dedicated local monitor; CI uses the same saved state.
.PARAMETER WorkspaceRoot
QuietCli2 root.
.PARAMETER Suite
Core, Git or All.
.PARAMETER RunDirectory
New output directory; generated when omitted.
.PARAMETER Headless
CI-only output mode, without a desktop window.
.PARAMETER SkipBuild
Uses already built engine and test fixture.
.PARAMETER TimeoutSeconds
Maximum worker time before a saved Timeout state.
.PARAMETER ExpectedRuntimeIdentifier
Required actual PowerShell and engine runtime identifier; detects accidental architecture emulation.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Core','Git','All')][string]$Suite='All',[string]$RunDirectory,[switch]$Headless,[switch]$SkipBuild,[ValidateRange(1,7200)][int]$TimeoutSeconds=1800,[ValidatePattern('^[a-z0-9-]+$')][string]$ExpectedRuntimeIdentifier)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
if(!$SkipBuild){& (Join-Path $PSScriptRoot 'Build-Workspace.ps1') -WorkspaceRoot $WorkspaceRoot}
if(!$RunDirectory){$RunDirectory=Join-Path $WorkspaceRoot ('artifacts/tests/'+[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))}
if(Test-Path -LiteralPath $RunDirectory){throw 'TestRunDirectoryExists'}
[void][IO.Directory]::CreateDirectory($RunDirectory)
$runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
$workerPath=Join-Path $PSScriptRoot 'Invoke-TestWorker.ps1'
$monitorPath=Join-Path $PSScriptRoot 'Watch-Tests.ps1'
$workerArguments=@('-File',('"'+$workerPath+'"'),'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$RunDirectory+'"'),'-Suite',$Suite)
if($ExpectedRuntimeIdentifier){$workerArguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
$options=@{FilePath=$runner;ArgumentList=$workerArguments;PassThru=$true;RedirectStandardOutput=(Join-Path $RunDirectory 'worker.stdout.log');RedirectStandardError=(Join-Path $RunDirectory 'worker.stderr.log')}
if($IsWindows){$options.WindowStyle='Hidden'}
$worker=Start-Process @options
$monitor=$null
if(!$Headless){
    if(!$IsWindows){$worker.Kill($true);throw 'Use the Windows host launcher for a visible local monitor; Headless is reserved for CI.'}
    $monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',('"'+$monitorPath+'"'),'-RunDirectory',('"'+$RunDirectory+'"')) -PassThru
}
"Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
$summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
[pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$RunDirectory}
if($summary.State.State -ne 'Success'){throw "Companion tests failed. See $RunDirectory"}
