#requires -Version 7.6
<#
.SYNOPSIS
Imports the engine-independent CI process commands without starting a process.
#>
[CmdletBinding(SupportsShouldProcess)]param()
if(!$PSCmdlet.ShouldProcess($PSScriptRoot,'Import CI process commands')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
