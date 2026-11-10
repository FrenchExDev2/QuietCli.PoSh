#requires -Version 7.6
function Test-LocalGalleryContainer {
    <#
    .SYNOPSIS
    Runs an owned exploratory BaGet roundtrip with Windows and Linux PowerShell clients.
    .PARAMETER Image
    Explicit server image reference. Tags are resolved to an immutable local image ID before execution.
    .PARAMETER LinuxClientImage
    Existing local Linux image containing pwsh and PSResourceGet; never pulled implicitly.
    .PARAMETER RunDirectory
    New external directory retaining request, logs and independent client results.
    .PARAMETER WorkspaceRoot
    Root providing the shared independent process supervisor and monitor.
    .PARAMETER DependencyStrategy
    Automatic tests client resolution; PinnedClosure explicitly restores every known preview before the consumer.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateLength(2,512)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9./:@_-]+\z')][string]$Image,
        [Parameter(Mandatory)][ValidateLength(2,512)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9./:@_-]+\z')][string]$LinuxClientImage,
        [ValidateSet('Automatic','PinnedClosure')][string]$DependencyStrategy='Automatic',
        [string]$RunDirectory,[string]$WorkspaceRoot=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
    $ErrorActionPreference='Stop'
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    if(!$IsWindows){throw 'LocalGalleryProbeMonitorRequiresWindowsHost'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'gallery-validation') ('local-'+[guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'GalleryProbeRunExists'}
    if(!$PSCmdlet.ShouldProcess($Image,'Pull selected image and run owned localhost gallery roundtrip with isolated Windows/Linux clients')){return}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    Write-WorkspaceJson (Join-Path $RunDirectory 'request.json') @{Image=$Image;LinuxClientImage=$LinuxClientImage;DependencyStrategy=$DependencyStrategy}
    $runner=Join-Path $PSHOME 'pwsh.exe'
    $workerPath=Join-Path $WorkspaceRoot 'scripts/workers/Invoke-LocalGalleryProbe.ps1'
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $worker=Start-Process $runner -WindowStyle Hidden -ArgumentList @('-File',(ConvertTo-CiArgument $workerPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log') -PassThru
    try{$monitor=Start-Process $runner -WindowStyle Normal -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log') -PassThru}catch{if(!$worker.HasExited){$worker.Kill($true)};throw}
    Write-Host "Monitor: pwsh -File `"$monitorPath`" -RunDirectory `"$RunDirectory`""
    $summary=Wait-WorkspaceWorker -Worker $worker -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -Runner $runner -Monitor $monitor -TimeoutSeconds 420
    [pscustomobject]@{State=$summary.State.State;RunDirectory=$RunDirectory;Qualification='Exploratory roundtrip only; not full PSREG1 lifecycle/platform qualification.'}
}
Export-ModuleMember -Function Test-LocalGalleryContainer
