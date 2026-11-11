#requires -Version 7.6
<#
.SYNOPSIS
Imports only extracted packages and returns a small verification JSON document.
.PARAMETER PackageDirectory
Archives and manifests to verify.
.PARAMETER ExtractionDirectory
New extraction destination.
.PARAMETER TestImport
Explicitly executes fully verified modules after checking the entire package set.
#>
[CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$PackageDirectory,[Parameter(Mandatory)][string]$ExtractionDirectory,[switch]$TestImport)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Verify-Distribution')){return}
$ErrorActionPreference='Stop'
$result=& (Join-Path $PSScriptRoot 'Test-WorkspacePackage.ps1') -PackageDirectory $PackageDirectory -ExtractionDirectory $ExtractionDirectory -TestImport:$TestImport
ConvertTo-Json -InputObject $result -Depth 8 -Compress
