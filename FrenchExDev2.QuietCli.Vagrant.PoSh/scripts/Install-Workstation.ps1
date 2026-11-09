<#
.SYNOPSIS
Prepares the selected module's native tool independently from the full workstation pipeline.
.DESCRIPTION
Compatible installations are retained. Download verifies the locked artifact without installation,
including on an already ready host. CheckOnly and WhatIf never download or install anything.
A missing Vagrant container provider is reported separately; provider configuration stays explicit.
.PARAMETER CheckOnly
Only probes local tool/provider readiness.
.PARAMETER Download
Caches the selected artifact without extracting, installing or configuring it.
.OUTPUTS
Module readiness, observed version/path, action, cache path and reboot requirement.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param([switch]$CheckOnly,[switch]$Download)
if($CheckOnly -and $Download){throw 'CheckOnlyAndDownloadAreMutuallyExclusive'}
Import-Module (Join-Path $PSScriptRoot '../../scripts/lib/DevelopmentWorkstation.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../../scripts/lib/ModuleWorkstation.psm1') -ErrorAction Stop
$name='Vagrant'
$target=Get-DevelopmentHost
$report=Get-ModuleWorkstationStatus $name $target
if($Download){
    if($PSCmdlet.ShouldProcess($name,'Download verified module installer')){
        $report.CachePath=Save-ModuleWorkstationDownload $name $target
        $report.Action='Downloaded'
    }
}elseif(!$CheckOnly -and !$report.ToolReady -and $PSCmdlet.ShouldProcess($target.Id,"Install $name")){
    $restart=Install-ModuleWorkstationTool $name $target
    $report=Get-ModuleWorkstationStatus $name $target
    $report.Action='Installed'
    $report.RestartRequired=[bool]$restart
    if($restart){$report.State='RestartRequired'}
    elseif(!$report.ToolReady){$report.State='Failed';$report;throw 'ModuleInstallationVerificationFailed'}
}
$report
