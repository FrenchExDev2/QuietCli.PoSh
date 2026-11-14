#requires -Version 7.6
<#
.SYNOPSIS
Runs one explicit local workflow operation with pinned wrkflw and the shared visible monitor.
.PARAMETER WorkspaceRoot
Selected checkout, used as wrkflw's working directory.
.PARAMETER WrkflwPath
Existing verified wrkflw 0.8.0 executable. This script never installs or downloads it.
.PARAMETER Workflow
Workspace-relative workflow definition to validate or execute.
.PARAMETER Mode
Validate checks the definition; Run executes only the explicitly selected job.
.PARAMETER Job
Required job ID for execution. Publication and credentials are never selected implicitly.
.PARAMETER Runtime
Explicit local runtime. Podman is the default; emulation executes host commands.
.PARAMETER TimeoutSeconds
Deadline for the owned local wrkflw process tree.
.PARAMETER RunDirectory
New report directory, generated under the shared temporary report root when omitted.
.PARAMETER Worker
Internal background entry point. Use the monitored launcher locally.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$WrkflwPath,
    [ValidatePattern('^\.github/workflows/[\w.-]+\.ya?ml$')][string]$Workflow='.github/workflows/companions-ci.yml',
    [ValidateSet('Validate','Run')][string]$Mode='Validate',[ValidatePattern('^[\w.-]+$')][string]$Job,
    [ValidateSet('podman','docker','emulation')][string]$Runtime='podman',
    [ValidateRange(1,1800)][int]$TimeoutSeconds=180,[string]$RunDirectory,[switch]$Worker)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
if($Mode -eq 'Run' -and !$Job){throw 'LocalWorkflowExplicitJobRequired'}
if(!(Test-Path -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,$Workflow)) -PathType Leaf)){throw 'LocalWorkflowDefinitionMissing'}
$nativeArguments=if($Mode -eq 'Validate'){@('validate','--exit-code',$Workflow)}else{@('run','--runtime',$Runtime,'--job',$Job,$Workflow)}
if(!$Worker){
    if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,('wrkflw '+($nativeArguments -join ' ')))){return}
    if(!$IsWindows){throw 'Local workflow execution requires the Windows visible-monitor launcher.'}
    if(!$RunDirectory){$RunDirectory=[IO.Path]::Combine((Get-QuietReportRoot $WorkspaceRoot 'local-workflows'),([guid]::NewGuid().ToString('N')))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'LocalWorkflowRunDirectoryExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $runner=[IO.Path]::Combine($PSHOME,'pwsh.exe')
    $arguments=@('-File',(ConvertTo-CiArgument $PSCommandPath),'-Worker','-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-WrkflwPath',(ConvertTo-CiArgument $WrkflwPath),'-Workflow',$Workflow,'-Mode',$Mode,'-Runtime',$Runtime,'-TimeoutSeconds',$TimeoutSeconds,'-RunDirectory',(ConvertTo-CiArgument $RunDirectory))
    if($Job){$arguments+=@('-Job',$Job)}
    $process=Start-Process -FilePath $runner -WindowStyle Hidden -PassThru -ArgumentList $arguments -RedirectStandardOutput ([IO.Path]::Combine($RunDirectory,'worker.stdout.log')) -RedirectStandardError ([IO.Path]::Combine($RunDirectory,'worker.stderr.log'))
    $monitorPath=[IO.Path]::Combine($PSScriptRoot,'Watch-Tests.ps1')
    $monitor=Start-Process -FilePath $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory))
    "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds ($TimeoutSeconds+15)
    [pscustomobject]@{State=$summary.State.State;ExitCode=$summary.ExitCode;RunDirectory=$RunDirectory;Workflow=$Workflow;Job=$Job;Runtime=$Runtime}
    if($summary.State.State -ne 'Success'){throw "Local workflow failed. See $RunDirectory"}
    return
}
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task="Local workflow $Mode ($Workflow / $Job)";Workspace=$WorkspaceRoot;ProjectDirectory=([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh'));Platform='local-'+$Runtime;State='Running';ProcessId=$PID;Passed=$null;Failed=$null;StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;Error=$null;Case='Verify pinned wrkflw version'}
$exitCode=$null
try{
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'status.json')) $state
    $version=@{Text=''}
    $check=Invoke-CiProcess -FilePath $WrkflwPath -ArgumentList @('--version') -TimeoutSeconds 10 -State $version -OnOutput {param($e,$s)if($s.Text.Length -lt 256){$s.Text+=$e.Text}}
    if($check.Outcome -ne 'Success' -or $version.Text.Trim() -cne 'wrkflw 0.8.0'){throw 'LocalWorkflowVersionMismatch'}
    $state.Case='Execute explicit wrkflw operation; workflow/test counters remain unknown'
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'status.json')) $state
    $result=Invoke-CiProcess -FilePath $WrkflwPath -ArgumentList $nativeArguments -WorkingDirectory $WorkspaceRoot -TimeoutSeconds $TimeoutSeconds
    $exitCode=$result.ExitCode
    $state.State=switch($result.Outcome){Success{'Success'} Timeout{'Timeout'} default{'Failed'}}
}catch{$state.State='Crash';$state.Error=$_.Exception.Message}
finally{
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'summary.json')) @{State=$state;ExitCode=$exitCode;Workflow=$Workflow;Job=$Job;Runtime=$Runtime;Arguments=$nativeArguments;Qualification='Local tool execution only; no GitHub-hosted runner or release qualification.'}
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'status.json')) $state
}
if($state.State -ne 'Success'){exit 1}
