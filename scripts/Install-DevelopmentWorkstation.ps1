#requires -Version 7.6
<#
.SYNOPSIS
Installs and checks a complete QuietCli development workstation for the detected host.
.DESCRIPTION
Uses the independent CI process helper, not QuietCli. Install PowerShell 7.6+ first using
README-development-workstation.md. CheckOnly and WhatIf are offline read-only modes.
The returned report distinguishes Ready, NeedsInstallation, RestartRequired and Failed.
Failed provisioning throws after emitting its report. A reboot is never initiated automatically.
.PARAMETER WorkspaceRoot
QuietCli monorepo containing global.json and reviewed artifact locks.
.PARAMETER InstallRoot
Isolated user tool directory; defaults to LocalAppData on Windows or ~/.local/share on Linux.
.PARAMETER Insiders
Selects VS Code Insiders; Stable is the default and existing other channels are preserved.
.PARAMETER PodmanMachineName
Explicit Windows Podman machine. Default/unique machines are reused; ambiguity is rejected.
.PARAMETER SkipEditor
Excludes editor and extension installation.
.PARAMETER SkipContainers
Excludes Podman and WSL/machine preparation.
.PARAMETER SkipNativeTools
Excludes Zig and Linux native property/fuzz/mutation compiler packages.
.PARAMETER SkipProfilers
Excludes the pinned PowerShell and CLR diagnostic tools.
.PARAMETER CheckOnly
Probes local tools and reports missing components without any download or write.
.PARAMETER ExtensionManifest
Saved VS Code/Insiders inventory, installed and updated during editor setup.
.EXAMPLE
./scripts/Install-DevelopmentWorkstation.ps1 -Insiders -WhatIf
.EXAMPLE
$report = ./scripts/Install-DevelopmentWorkstation.ps1
if ($report.RestartRequired) { Write-Host 'Restart Windows, then rerun the same command.' }
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [string]$InstallRoot,
    [switch]$Insiders,
    [string]$PodmanMachineName,
    [switch]$SkipEditor,
    [switch]$SkipContainers,
    [switch]$SkipNativeTools,
    [switch]$SkipProfilers,
    [switch]$CheckOnly,
    [string]$ExtensionManifest=(Join-Path $WorkspaceRoot 'build/vscode-extensions.json')
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/DevelopmentWorkstation.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/EditorExtensions.psm1')
$target=Get-DevelopmentHost
if(!$InstallRoot){$InstallRoot=if($target.Id -ceq 'windows'){Join-Path $env:LOCALAPPDATA 'QuietCli2/development'}else{Join-Path $HOME '.local/share/QuietCli2/development'}}
$skipped=@(if($SkipEditor){'Editor'};if($SkipContainers){'Containers'};if($SkipNativeTools){'Native'};if($SkipProfilers){'Profilers'})
$specification=Get-DevelopmentSpecification $WorkspaceRoot $target
$extensionIds=@(if(!$SkipEditor){Read-EditorExtensionManifest $ExtensionManifest|ForEach-Object Id})
$plan=New-DevelopmentPlan $target $WorkspaceRoot $InstallRoot $specification -Insiders ([bool]$Insiders) -Skipped $skipped -PodmanMachineName $PodmanMachineName -Extensions $extensionIds -ExtensionManifest $ExtensionManifest
$inventory=Get-DevelopmentInventory $plan
$installerCmdlet=$PSCmdlet
$apply={param($path,$action)$installerCmdlet.ShouldProcess($path,$action)}.GetNewClosure()
$report=Invoke-DevelopmentProvisioning $plan $inventory -ShouldApply $apply -CheckOnly:$CheckOnly
$report
if($report.RestartRequired){Write-Host 'Restart Windows, then rerun this command. Existing tools and machines will be reused.'}
if($report.ActivationScript){Write-Host ('Activate in each new PowerShell session: . '+"'"+$report.ActivationScript.Replace("'","''")+"'")}
if($report.State -eq 'Failed'){throw $report.Error}
