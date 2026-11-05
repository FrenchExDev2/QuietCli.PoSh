# Objectif : Exécuter des reproductions d’audit confinées et ouvrir leur suivi PowerShell visible.
#requires -Version 7.6
<#
.SYNOPSIS
Runs isolated security and design checks without modifying product sources.
.PARAMETER WorkspaceRoot
QuietCli2 workspace to audit.
.PARAMETER RunDirectory
New directory for synthetic fixtures and evidence.
.PARAMETER SkipBuild
Uses already verified compiled fixtures.
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),[string]$RunDirectory,[switch]$SkipBuild)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
if(!$SkipBuild){$null=& (Join-Path $WorkspaceRoot 'scripts/Build-Workspace.ps1') -WorkspaceRoot $WorkspaceRoot}
if(!$RunDirectory){$RunDirectory=Join-Path $WorkspaceRoot ('artifacts/audit/'+[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))}
if(Test-Path -LiteralPath $RunDirectory){throw 'AuditRunDirectoryExists'}
[void][IO.Directory]::CreateDirectory($RunDirectory)
if(!$IsWindows){throw 'Use the Windows host to open the required visible audit monitor.'}
$pwsh=(Get-Command pwsh -CommandType Application|Select-Object -First 1).Source
$worker=Start-Process -FilePath $pwsh -WindowStyle Hidden -ArgumentList @('-File',('"'+(Join-Path $PSScriptRoot 'Invoke-AuditWorker.ps1')+'"'),'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$RunDirectory+'"')) -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log') -PassThru
$watch=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
$monitor=Start-Process -FilePath $pwsh -WindowStyle Normal -ArgumentList @('-File',('"'+$watch+'"'),'-RunDirectory',('"'+$RunDirectory+'"')) -PassThru
"Monitor: pwsh -File `"$watch`" -RunDirectory `"$RunDirectory`""
$deadline=[DateTimeOffset]::UtcNow.AddMinutes(4)
while(!$worker.HasExited){
    if([DateTimeOffset]::UtcNow -gt $deadline){$worker.Kill($true);$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh';Task='Audit sécurité et logiciel';Workspace=$WorkspaceRoot;ProjectDirectory=$WorkspaceRoot;Platform='win-x64';ProcessId=$worker.Id;StartedUtc=$deadline.AddMinutes(-4).ToString('o');FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');State='Timeout';Passed=$null;Failed=$null;Case='Audit worker timed out';Error='See worker logs'};Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state};Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state;break}
    if($monitor.HasExited){$monitor=Start-Process -FilePath $pwsh -WindowStyle Normal -ArgumentList @('-File',('"'+$watch+'"'),'-RunDirectory',('"'+$RunDirectory+'"')) -PassThru}
    [void][Threading.Tasks.Task]::Delay(500).GetAwaiter().GetResult()
}
if(!(Test-Path -LiteralPath (Join-Path $RunDirectory 'summary.json'))){
    $state=@{Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh';Task='Audit sécurité et logiciel';Workspace=$WorkspaceRoot;ProjectDirectory=$WorkspaceRoot;Platform='win-x64';ProcessId=$worker.Id;StartedUtc=$deadline.AddMinutes(-4).ToString('o');FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');State='Crash';Passed=$null;Failed=$null;Case='Audit worker exited without a report';Error='See worker logs'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state}
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
}
$report=Get-Content (Join-Path $RunDirectory 'summary.json') -Encoding utf8 -Raw|ConvertFrom-Json
[pscustomobject]@{State=$report.State.State;Checks=$report.Checks.Count;Resolved=$report.Resolved;Unresolved=$report.Unresolved;RunDirectory=$RunDirectory}
if($report.State.State -ne 'Success'){throw "Audit infrastructure failed: $RunDirectory"}
