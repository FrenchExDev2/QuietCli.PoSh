#requires -Version 7.6
<#
.SYNOPSIS
Updates unambiguous RuntimeFrameworkVersion properties for one target framework.
.PARAMETER WorkspaceRoot
Selected checkout, default this checkout.
.PARAMETER Version
Exact runtime version; omitted derives it from the SDK pinned in global.json.
.PARAMETER Path
Optional exact .csproj/.props paths within this checkout.
.PARAMETER Framework
Target framework, default net11.0; other frameworks remain outside the selected scope.
.PARAMETER Preleases
Permit preview/RC runtime targets.
.PARAMETER AllowDowngrade
Permit lowering an existing runtime version.
.PARAMETER PlanOnly
Return proposed project text and changes without writing.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=$PSScriptRoot+'/..',[string]$Version,[string[]]$Path,
    [string]$Framework='net11.0',[Alias('Prerelease','Prereleases')][switch]$Preleases,
    [switch]$AllowDowngrade,[switch]$PlanOnly)
$ErrorActionPreference='Stop'
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Update the selected target framework runtime pins with backups')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/DotNetLocks.psm1')) -ErrorAction Stop -DisableNameChecking
$options=@{}+$PSBoundParameters;$options.Confirm=$false
Update-DotNetRuntimeFrameworkVersion @options
