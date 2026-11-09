#requires -Version 7.6
<#
.SYNOPSIS
Reports and cleans expired, registered workstation smoke runs and their labelled disposable resources.
.DESCRIPTION
Unmanaged, active, foreign, linked and unverifiable directories are preserved. Default retention is
seven days with three latest runs retained. WhatIf performs no removal; read-only Podman probes
never initialize or start a machine.
Product installations under LocalAppData or ~/.local/share are outside this cleanup's scope.
.PARAMETER WorkspaceRoot
QuietCli source workspace owning these temporary reports.
.PARAMETER RetentionDays
Minimum age before a registered inactive run may be removed.
.PARAMETER KeepLatest
Minimum latest runs retained, including failed runs and their diagnostics.
.PARAMETER ActiveGraceMinutes
Additional recency protection beyond worker identity and the live lease.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateRange(0,3650)][int]$RetentionDays=7,[ValidateRange(0,1000)][int]$KeepLatest=3,[ValidateRange(0,1440)][int]$ActiveGraceMinutes=15)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ReportPaths.ps1')
Import-Module (Join-Path $PSScriptRoot 'lib/WorkstationResources.psm1')
$root=Get-QuietReportRoot $WorkspaceRoot workstation -ContinuousIntegration $false
if(!(Test-Path -LiteralPath $root)){return}
$directories=@(Get-ChildItem -LiteralPath $root -Directory -Force|Sort-Object LastWriteTimeUtc -Descending)
$now=[DateTimeOffset]::UtcNow
for($index=0;$index -lt $directories.Count;$index++){
    $directory=$directories[$index];$decision=Get-WorkstationCleanupDecision $directory.FullName $WorkspaceRoot
    $result=[ordered]@{Path=$directory.FullName;Owner=$(if($decision.Receipt){$decision.Receipt.Owner}else{$null});State=$decision.State;Reason=$decision.Reason;Resources=@()}
    if($decision.State -ne 'Inactive'){[pscustomobject]$result;continue}
    $timestamp=if($decision.Receipt.FinishedUtc){[DateTimeOffset]::Parse($decision.Receipt.FinishedUtc,[Globalization.CultureInfo]::InvariantCulture)}else{[DateTimeOffset]::Parse($decision.Receipt.CreatedUtc,[Globalization.CultureInfo]::InvariantCulture)}
    if($index -lt $KeepLatest -or $timestamp -gt $now.AddDays(-$RetentionDays) -or $directory.LastWriteTimeUtc -gt $now.AddMinutes(-$ActiveGraceMinutes).UtcDateTime){$result.State='Retained';$result.Reason='Latest-run, age or grace policy';[pscustomobject]$result;continue}
    if(!(Test-WorkstationDirectoryBoundary $root $directory.FullName)){$result.State='Protected';$result.Reason='Directory boundary or filesystem link';[pscustomobject]$result;continue}
    $lease=$null
    try{
        # A producer holds this lease for its lifetime. FileShare.Delete lets this owner delete
        # the directory while preventing a competing producer from obtaining a writable lease.
        $leasePath=Join-Path $directory.FullName 'run.lease'
        if(Test-Path -LiteralPath $leasePath){$lease=[IO.FileStream]::new($leasePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Delete)}
        elseif($decision.Receipt.Resources.Count){$result.State='Protected';$result.Reason='Resource lease missing';[pscustomobject]$result;continue}
        if($decision.Receipt.Resources.Count -and !(Test-WorkstationPodmanIdentity $decision.Receipt.PodmanIdentity)){$result.State='Protected';$result.Reason='Original Podman engine/store cannot be verified';[pscustomobject]$result;continue}
        $preview=@(foreach($resource in $decision.Receipt.Resources){$state=Remove-WorkstationOwnedResource $resource -Preview;[pscustomobject]@{Kind=$resource.Kind;Name=$resource.Name;State=$state;Consumers=$resource['Consumers']}})
        $result.Resources=$preview
        if(@($preview|Where-Object State -NotIn @('Eligible','Absent')).Count){$result.State='Protected';$result.Reason='Resources are in use, foreign or unverifiable';[pscustomobject]$result;continue}
        if(!$PSCmdlet.ShouldProcess($directory.FullName,'Release owned inactive resources and remove expired workstation evidence')){$result.State='Eligible';[pscustomobject]$result;continue}
        $resourceResults=@(foreach($resource in $decision.Receipt.Resources){$state=Remove-WorkstationOwnedResource $resource;[pscustomobject]@{Kind=$resource.Kind;Name=$resource.Name;State=$state}})
        $result.Resources=$resourceResults
        if(@($resourceResults|Where-Object State -NotIn @('Removed','Absent')).Count){$result.State='Protected';$result.Reason='Resources remain in use, foreign or unverifiable';[pscustomobject]$result;continue}
        if(!(Test-WorkstationDirectoryBoundary $root $directory.FullName)){throw 'WorkstationCleanupBoundaryChanged'}
        Remove-Item -LiteralPath $directory.FullName -Recurse -Force -Confirm:$false
        $result.State='Removed';$result.Reason='Registered inactive run and owned resources released'
    }catch{$result.State='Protected';$result.Reason=$_.Exception.Message}
    finally{if($lease){$lease.Dispose()}}
    [pscustomobject]$result
}
