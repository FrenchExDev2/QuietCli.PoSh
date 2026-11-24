#requires -Version 7.6
<#
.SYNOPSIS
Sets or bumps the versions of QuietCli business module manifests.
.PARAMETER Version
Exact three-part version, optionally followed by a Gallery prerelease label.
.PARAMETER Bump
Increments major, minor or patch for a stable version, or increments the local preview counter.
.PARAMETER Module
Business module aliases or full names. Defaults to all business modules.
.PARAMETER WorkspaceRoot
Workspace containing the module manifests. Defaults to this script's checkout.
.EXAMPLE
./scripts/New-Version.ps1 -Version 0.2.0-preview3
.EXAMPLE
./scripts/New-Version.ps1 -Bump patch
.EXAMPLE
./scripts/New-Version.ps1 -Bump preview
.EXAMPLE
./scripts/New-Version.ps1 -Bump minor -Module Core,Git -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Version')]
param(
    [Parameter(Mandatory, ParameterSetName='Version')][string]$Version,
    [Parameter(Mandatory, ParameterSetName='Bump')][ValidateSet('major','minor','patch','preview')][string]$Bump,
    [ValidateNotNullOrEmpty()][string[]]$Module = @('All'),
    [string]$WorkspaceRoot = [IO.Path]::GetDirectoryName($PSScriptRoot)
)

Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ModuleVersion.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptNewVersion @PSBoundParameters
