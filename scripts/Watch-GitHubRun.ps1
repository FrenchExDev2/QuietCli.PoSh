# Objectif : Suivre un run GitHub existant avec une fenêtre visible et un rapport terminal sauvegardé.
#requires -Version 7.6
<#
.SYNOPSIS
Monitors one explicitly selected existing GitHub run; does not dispatch, retry or cancel it.
.PARAMETER RunId
Existing GitHub Actions run identifier.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER Repository
GitHub owner/repository to observe.
#>
[CmdletBinding()]param([Parameter(Mandatory)][long]$RunId,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repository='FrenchExDev2/FrenchExDev2.QuietCli.PoSh')
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1)
if(!$IsWindows){throw 'Use the Windows visible-monitor host launcher'}
$run=Join-Path $WorkspaceRoot ('artifacts/github/'+$RunId+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
[void][IO.Directory]::CreateDirectory($run)
$runner=(Get-Command pwsh -CommandType Application|Select-Object -First 1).Source
$worker=Start-Process -FilePath $runner -WindowStyle Hidden -ArgumentList @('-File',('"'+(Join-Path $PSScriptRoot Invoke-GitHubRunWorker.ps1)+'"'),'-RunId',$RunId,'-Repository',$Repository,'-WorkspaceRoot',('"'+$WorkspaceRoot+'"'),'-RunDirectory',('"'+$run+'"')) -PassThru -RedirectStandardOutput (Join-Path $run worker.stdout.log) -RedirectStandardError (Join-Path $run worker.stderr.log)
$monitorPath=Join-Path $PSScriptRoot Watch-Tests.ps1
$monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',('"'+$monitorPath+'"'),'-RunDirectory',('"'+$run+'"')) -PassThru
"Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$run`""
$summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $run -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds 3600
[pscustomobject]@{State=$summary.State.State;RunId=$RunId;RunDirectory=$run;Url="https://github.com/$Repository/actions/runs/$RunId"}
if($summary.State.State -ne 'Success'){throw "GitHub run did not succeed: $run"}
