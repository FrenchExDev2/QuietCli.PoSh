# Objectif : Observer le rejet ou la validation d’un paquet synthétique sans exposer de résultat QuietCli complet.
#requires -Version 7.6
<#
.SYNOPSIS
Executes the package verifier in isolation and returns its bounded decision as JSON.
.PARAMETER WorkspaceRoot
Workspace containing the verifier.
.PARAMETER PackageDirectory
Synthetic archive set.
.PARAMETER ExtractionDirectory
New isolated destination.
.PARAMETER MaxFiles
Requested test quota.
.PARAMETER MaxTotalBytes
Requested test quota.
#>
[CmdletBinding()]param([string]$WorkspaceRoot,[string]$PackageDirectory,[string]$ExtractionDirectory,[int]$MaxFiles=10000,[long]$MaxTotalBytes=536870912)
$ErrorActionPreference='Stop'
try{
    $result=& (Join-Path $WorkspaceRoot 'scripts/Test-WorkspacePackage.ps1') -PackageDirectory $PackageDirectory -ExtractionDirectory $ExtractionDirectory -MaxFiles $MaxFiles -MaxTotalBytes $MaxTotalBytes
    @{Rejected=$false;Verified=$result.Verified;ImportTested=$result.ImportTested}|ConvertTo-Json -Compress
}catch{@{Rejected=$true;Reason=$_.Exception.Message}|ConvertTo-Json -Compress}
