#requires -Version 7.6
<#
.SYNOPSIS
Enables long paths for Windows applications that opt in to long-path support.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Enable-WindowsLongPaths.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptEnableWindowsLongPaths @PSBoundParameters
