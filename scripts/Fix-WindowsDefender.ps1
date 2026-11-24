#requires -Version 7.6
<#
.SYNOPSIS
Adds the workspace's development exclusions to Microsoft Defender Antivirus.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Fix-WindowsDefender.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptFixWindowsDefender @PSBoundParameters
