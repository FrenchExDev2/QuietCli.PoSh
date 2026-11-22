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
.PARAMETER InTerminal
Show progress in the current terminal. This is the default outside Windows.
#>
[CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][long]$RunId,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repository='FrenchExDev2/QuietCli.PoSh',[switch]$InTerminal)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Watch-GitHubRun')){return}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$useWindow=$IsWindows -and !$InTerminal
$run=[IO.Path]::Combine($WorkspaceRoot,('artifacts/github/'+$RunId+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)))
[void][IO.Directory]::CreateDirectory($run)
$runner=(Get-Command pwsh -CommandType Application|Select-Object -First 1).Source
$workerOptions=if($IsWindows){@{WindowStyle='Hidden'}}else{@{}}
$worker=Start-Process @workerOptions -FilePath $runner -ArgumentList @('-File',(ConvertTo-CiArgument (([IO.Path]::Combine($PSScriptRoot,'Invoke-GitHubRunWorker.ps1')))),'-RunId',$RunId,'-Repository',$Repository,'-WorkspaceRoot',(ConvertTo-CiArgument ($WorkspaceRoot)),'-RunDirectory',(ConvertTo-CiArgument ($run))) -PassThru -RedirectStandardOutput ([IO.Path]::Combine($run,'worker.stdout.log')) -RedirectStandardError ([IO.Path]::Combine($run,'worker.stderr.log'))
$monitor=$null
if($useWindow){
    $monitorPath=[IO.Path]::Combine($PSScriptRoot,'Watch-Tests.ps1')
    $monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-File',(ConvertTo-CiArgument ($monitorPath)),'-RunDirectory',(ConvertTo-CiArgument ($run))) -PassThru
    "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$run`""
}else{
    Write-Host "Watching GitHub run $RunId in this terminal. Reports: $run"
}
$summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $run -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds 3600 -ShowRemoteJobs:(!$useWindow)
[pscustomobject]@{State=$summary.State.State;RunId=$RunId;RunDirectory=$run;Url="https://github.com/$Repository/actions/runs/$RunId"}
if($summary.State.State -ne 'Success'){throw "GitHub run did not succeed: $run"}
