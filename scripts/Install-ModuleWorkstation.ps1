<#
.SYNOPSIS
Runs the workstation installer for each selected QuietCli companion.
.DESCRIPTION
Select companions that declare workstation support in build/companions.yaml. Each companion owns its
scripts/Install-Workstation.ps1 implementation.
.PARAMETER Modules
Companion names to install, in the given order.
.PARAMETER CheckOnly
Forwarded to every selected module's own script: probes only, no download, no installation.
.PARAMETER Download
Forwarded to every selected module's own script: best-effort pre-fetch, independent of readiness, never installs.
.OUTPUTS
One [pscustomobject] per selected module, as returned by that module's own Install-Workstation.ps1.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string[]]$Modules,
    [switch]$CheckOnly,
    [switch]$Download
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop

if ($CheckOnly -and $Download) { throw 'CheckOnlyAndDownloadAreMutuallyExclusive' }
$root = Split-Path $PSScriptRoot -Parent
$canonical = @(Get-QuietCompanions -WorkspaceRoot $root -Name $Modules -Capability Workstation)
foreach ($requested in $Modules) {
    $module = $canonical -eq $requested
    & ((Resolve-QuietWorkspacePath -WorkspaceRoot $root -RelativePath "FrenchExDev2.QuietCli.$module.PoSh/scripts/Install-Workstation.ps1")) -CheckOnly:$CheckOnly -Download:$Download -WhatIf:$WhatIfPreference
}
