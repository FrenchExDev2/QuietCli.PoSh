# Objectif : Vérifier une distribution extraite dans un processus distinct des suites qui l’ont construite.
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
[CmdletBinding()]param([Parameter(Mandatory)][string]$PackageDirectory,[Parameter(Mandatory)][string]$ExtractionDirectory,[switch]$TestImport)
$ErrorActionPreference='Stop'
$result=& (Join-Path $PSScriptRoot 'Test-WorkspacePackage.ps1') -PackageDirectory $PackageDirectory -ExtractionDirectory $ExtractionDirectory -TestImport:$TestImport
ConvertTo-Json -InputObject $result -Depth 8 -Compress
