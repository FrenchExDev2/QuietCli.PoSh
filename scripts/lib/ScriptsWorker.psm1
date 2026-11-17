#Objective: Shared supervised launch of a scripts tool worker: hidden pwsh worker, optional visible monitor, bounded wait.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Common.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietScriptsSupervisedWorker {
    <#
    .SYNOPSIS
    Runs a module's worker function in a hidden UTF-8 pwsh, opens the monitor unless headless, and returns the saved summary.
    .DESCRIPTION
    The worker writes status.json and summary.json in RunDirectory. Without Headless the read-only Watch-Tests.ps1 monitor
    opens on the same directory. Wait-WorkspaceWorker enforces the deadline and records Timeout or Crash when the worker
    ends without a summary. Returns the saved summary.
    .PARAMETER ModulePath
    Library that exports the worker function.
    .PARAMETER WorkerFunction
    Worker function name; it receives -RequestPath only.
    .PARAMETER RequestPath
    Request document read by the worker.
    .PARAMETER RunDirectory
    Dedicated run directory (worker logs, status and summary).
    .PARAMETER WorkspaceRoot
    Source workspace recorded in a synthesized terminal status.
    .PARAMETER Headless
    Disables the visible monitor (CI).
    .PARAMETER TimeoutSeconds
    Wall-clock limit before the worker tree is terminated.
    #>
    param([Parameter(Mandatory)][string]$ModulePath,[Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9-]*$')][string]$WorkerFunction,[Parameter(Mandatory)][string]$RequestPath,[Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][string]$WorkspaceRoot,[switch]$Headless,[Parameter(Mandatory)][int]$TimeoutSeconds)
    $runner=[IO.Path]::Combine($PSHOME,$(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
    # The supervisor decodes worker logs as strict UTF-8, so the worker must not write in the OEM console code page.
    $command='[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $OutputEncoding=[Console]::OutputEncoding; '+"Import-Module '"+$ModulePath.Replace("'","''")+"' -DisableNameChecking -ErrorAction Stop; $WorkerFunction -RequestPath '"+$RequestPath.Replace("'","''")+"'"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $options=@{FilePath=$runner;ArgumentList=@('-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',$encoded);PassThru=$true;RedirectStandardOutput=([IO.Path]::Combine($RunDirectory,'worker.stdout.log'));RedirectStandardError=([IO.Path]::Combine($RunDirectory,'worker.stderr.log'))}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $worker=Start-Process @options
    $monitor=$null
    if(!$Headless){
        $monitorPath=[IO.Path]::Combine(([IO.Path]::GetDirectoryName($PSScriptRoot)),'Watch-Tests.ps1')
        $monitor=Start-Process -FilePath $runner -WindowStyle Normal -ArgumentList @('-NoProfile','-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError ([IO.Path]::Combine($RunDirectory,'monitor.stderr.log')) -PassThru
    }
    Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds $TimeoutSeconds
}

Export-ModuleMember -Function Invoke-QuietScriptsSupervisedWorker
