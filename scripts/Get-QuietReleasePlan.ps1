#requires -Version 7.6
<#
.SYNOPSIS
Validates a module-specific publication tag and optionally writes bounded GitHub job outputs.
.PARAMETER Tag
Exact pushed tag, such as FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview; must match its script module and manifest.
.PARAMETER WorkspaceRoot
Selected QuietCli2 source checkout.
.PARAMETER OutputPath
Optional GitHub output file receiving the validated module and version.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Tag,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$OutputPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/GalleryRelease.psm1') -Force
$plan=Resolve-QuietGalleryReleaseTag -WorkspaceRoot $WorkspaceRoot -Tag $Tag
if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Append validated Gallery release outputs')){
    [IO.File]::AppendAllText([IO.Path]::GetFullPath($OutputPath,$PWD.Path),"module=$($plan.Module)`nversion=$($plan.Version)`n",[Text.UTF8Encoding]::new($false))
}
$plan
