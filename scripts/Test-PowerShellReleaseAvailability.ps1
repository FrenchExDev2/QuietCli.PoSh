#requires -Version 7.6
<#
.SYNOPSIS
Checks official PowerShell GA, next-preview archives and native Alpine package availability.
.PARAMETER AlpineBranch
Existing Alpine repository branch; this command changes no distribution or lock.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$AlpineBranch='v3.24')
if(!$PSCmdlet.ShouldProcess('Official PowerShell release resources','Read metadata and probe required resources')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PowerShellReleases.psm1')) -ErrorAction Stop -DisableNameChecking
Get-QuietPowerShellReleaseResources -AlpineBranch $AlpineBranch -Confirm:$false
