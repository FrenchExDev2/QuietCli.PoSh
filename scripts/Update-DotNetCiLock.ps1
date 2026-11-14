#requires -Version 7.6
<#
.SYNOPSIS
Synchronizes SDK/archive locks with global.json and optionally refreshes OS base-image digests.
.PARAMETER WorkspaceRoot
QuietCli checkout, default this checkout.
.PARAMETER IncludeDevelopmentLock
Also updates Windows SDK ZIP hashes, preserving unrelated workstation tool pins.
.PARAMETER RefreshBaseImages
Resolves current digests of the existing Debian/Alpine tags without pulling layers.
.PARAMETER DebianTag
Explicit alternate Debian tag; OS package compatibility still requires a build.
.PARAMETER AlpineTag
Explicit alternate Alpine tag; PowerShell package compatibility still requires a build.
.PARAMETER AlpineRuntimeVersion
Optional exact .NET 10 runtime for Alpine PowerShell, otherwise preserve the existing version.
.PARAMETER Preleases
Allow published preview/RC SDKs.
.PARAMETER PlanOnly
Read metadata and return proposed documents without writing them.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=$PSScriptRoot+'/..',[switch]$IncludeDevelopmentLock,
    [switch]$RefreshBaseImages,[string]$DebianTag,[string]$AlpineTag,[string]$AlpineRuntimeVersion,
    [Alias('Prerelease','Prereleases')][switch]$Preleases,[switch]$PlanOnly)
$ErrorActionPreference='Stop'
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Synchronize selected .NET archive and container base locks')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/DotNetLocks.psm1')) -ErrorAction Stop -DisableNameChecking
$options=@{}+$PSBoundParameters;$options.Confirm=$false
Update-DotNetCiLock @options
