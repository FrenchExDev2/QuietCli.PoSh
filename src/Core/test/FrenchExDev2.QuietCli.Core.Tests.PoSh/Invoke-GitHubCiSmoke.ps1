#requires -Version 7.6
<#
.SYNOPSIS
Exercises the direct GitHub entry inside a real local Docker container with the required local monitor.
.PARAMETER Image
Existing local Linux x64 toolchain image; no pull, build or publication is implicit.
.PARAMETER WorkspaceRoot
Source checkout containing built Linux publications.
.PARAMETER RunDirectory
New owned report directory.
.PARAMETER Worker
Internal background entry point.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Image,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,[switch]$Worker)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Run the owned Docker GitHub entry smoke with a visible local monitor')){return}
if(!$Worker){
    if(!$IsWindows){throw 'Use the Windows visible-monitor launcher.'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot tests) ('github-ci-smoke-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $runner=Join-Path $PSHOME pwsh.exe
    $process=Start-Process -FilePath $runner -WindowStyle Hidden -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $PSCommandPath),'-Worker','-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory),'-Image',(ConvertTo-CiArgument $Image)) -RedirectStandardOutput (Join-Path $RunDirectory worker.stdout.log) -RedirectStandardError (Join-Path $RunDirectory worker.stderr.log)
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $monitor=Start-Process -FilePath $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory))
    "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds 300
    [pscustomobject]@{State=$summary.State.State;RunDirectory=$RunDirectory}
    if($summary.State.State -ne 'Success'){throw "GitHub Docker smoke failed. See $RunDirectory"};return
}
& (Join-Path $WorkspaceRoot 'scripts/Invoke-ContainerWorker.ps1') -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Image $Image -Platform debian -Suite Import -ExpectedRuntimeIdentifier linux-x64 -ContainerRuntime docker -GitHubActions -SkipTty -TimeoutSeconds 240
