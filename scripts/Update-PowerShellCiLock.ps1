#requires -Version 7.6
<#
.SYNOPSIS
Verifies published GA/next-preview resources and updates PowerShell host/image pins.
.PARAMETER WorkspaceRoot
Checkout owning the reviewed locks.
.PARAMETER AllowAlpineVersionLag
Explicitly preserve native Alpine PowerShell when the requested GA is unavailable.
.PARAMETER PlanOnly
Query metadata and return proposed locks without creating files or backups.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$AllowAlpineVersionLag,[switch]$PlanOnly)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Verify and update PowerShell release resource locks')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PowerShellReleases.psm1')) -ErrorAction Stop -DisableNameChecking
Update-QuietPowerShellCiLock -WorkspaceRoot $WorkspaceRoot -AllowAlpineVersionLag:$AllowAlpineVersionLag -PlanOnly:$PlanOnly -Confirm:$false
