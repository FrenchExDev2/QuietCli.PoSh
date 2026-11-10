#requires -Version 7.6
<#
.SYNOPSIS
Starts the complete planning-tooling suite and its existing visible read-only monitor.
.PARAMETER WorkspaceRoot
Monorepo root whose planning tooling is tested.
.PARAMETER RunDirectory
New external report directory; defaults to the shared temporary report root.
.PARAMETER TimeoutSeconds
Owned worker deadline; crash and timeout diagnostics are saved by the common supervisor.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,
    [ValidateRange(1,600)][int]$TimeoutSeconds=180)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
if(!$IsWindows){throw 'RoadmapLocalMonitorRequiresWindows'}
if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'tests') ('roadmaps-'+[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))}
if(Test-Path -LiteralPath $RunDirectory){throw 'TestRunDirectoryExists'}
[void][IO.Directory]::CreateDirectory($RunDirectory)
$runner=Join-Path $PSHOME 'pwsh.exe'
$workerPath=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/roadmap-tests/Invoke-RoadmapTests.ps1'
$monitorPath=Join-Path $PSScriptRoot 'Watch-Tests.ps1'
$worker=Start-Process -FilePath $runner -WindowStyle Hidden -ArgumentList @('-File',(ConvertTo-CiArgument $workerPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log') -PassThru
try {
    $monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log') -PassThru
} catch {if(!$worker.HasExited){$worker.Kill($true)};throw}
Write-Host "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
$summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
[pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$RunDirectory}
if($summary.State.State -ne 'Success'){throw "RoadmapTestsFailed:$RunDirectory"}
