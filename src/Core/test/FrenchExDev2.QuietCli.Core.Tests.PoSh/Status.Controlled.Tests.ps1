function Invoke-QuietControlledStatusIntegration {
    <#
    .SYNOPSIS
    Runs mandatory portable Git fixtures in an isolated Core-only child and retains its evidence.
    .PARAMETER WorkspaceRoot
    Local monorepo supplying the built Core.
    .PARAMETER RunDirectory
    Current run directory; fixture evidence stays inside its uploaded artifact tree.
    .PARAMETER OnProgress
    Optional observer receiving a bounded scenario description.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[Alias('OnProgress')][scriptblock]$ProgressObserver)
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    $directory=Join-Path $RunDirectory 'controlled-status'
    $probeState=@{Evidence=$null;Progress=$ProgressObserver;Diagnostic=''}
    $result=quiet -AsObject -Role Infrastructure -TimeoutSeconds 600 -RecordDelimiter "`n" -MaxRecordBytes 262144 -Data $probeState -Output {
        param($event,$runtime)
        if($event.Stream -eq 'stderr'){
            if($runtime.Data.Diagnostic.Length -lt 8192){$runtime.Data.Diagnostic+=$event.Text}
            return
        }
        $row=$event.Text|ConvertFrom-Json
        if($row.Kind -eq 'Progress'){
            if($runtime.Data.Progress){$null=& $runtime.Data.Progress ("Controlled Git status: $($row.Scenario) ($($row.Completed)/8)")}
        }elseif($row.Kind -eq 'Result'){$runtime.Data.Evidence=$row.Evidence}else{throw 'UnknownControlledStatusMessage'}
    } -Complete {
        param($runtime)
        if($runtime.Data.Diagnostic){throw $runtime.Data.Diagnostic}
        if(!$runtime.Data.Evidence){throw 'ControlledStatusEvidenceMissing'}
        $runtime.Data.Evidence
    } -FilePath $runner -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'Status.ControlledProbe.ps1'),'-WorkspaceRoot',$WorkspaceRoot,'-RunDirectory',$directory)
    if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis){throw ('ControlledStatusProbeFailed: '+($result.Error|ConvertTo-Json -Compress))}
    if($result.Data.RuntimeIdentifier -cne [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier -or $result.Data.PowerShellVersion -cne $PSVersionTable.PSVersion.ToString()){throw 'ControlledStatusHostMismatch'}
    return $result.Data
}
