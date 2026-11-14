<#
.SYNOPSIS
Runs the per-module workstation installer for each selected QuietCli module ('Git' and/or 'Vagrant').
.DESCRIPTION
Deliberately named differently from Install-DevelopmentWorkstation.ps1, which this script neither replaces nor
changes the behavior of. -Modules is mandatory, with no 'All' default, so the caller always chooses explicitly
which modules to touch; extending the ValidateSet to another module is adding that module's own
scripts/Install-Workstation.ps1 plus a value here, explicitly out of scope today.
.PARAMETER Modules
Module names to install, in the given order. Only 'Git' and 'Vagrant' are supported today.
.PARAMETER CheckOnly
Forwarded to every selected module's own script: probes only, no download, no installation.
.PARAMETER Download
Forwarded to every selected module's own script: best-effort pre-fetch, independent of readiness, never installs.
.OUTPUTS
One [pscustomobject] per selected module, as returned by that module's own Install-Workstation.ps1.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][ValidateSet('Git', 'Vagrant')][string[]]$Modules,
    [switch]$CheckOnly,
    [switch]$Download
)
if ($CheckOnly -and $Download) { throw 'CheckOnlyAndDownloadAreMutuallyExclusive' }
$root = Split-Path $PSScriptRoot -Parent
foreach ($module in $Modules) {
    & ([IO.Path]::Combine($root,"FrenchExDev2.QuietCli.$module.PoSh/scripts/Install-Workstation.ps1")) -CheckOnly:$CheckOnly -Download:$Download -WhatIf:$WhatIfPreference
}
