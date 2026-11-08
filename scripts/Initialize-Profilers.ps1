<#
.SYNOPSIS
Explicitly downloads checksum-pinned diagnostic tools to an isolated cache, without global installation.
.PARAMETER OutputDirectory
Dedicated cache for the two exact packages and their extraction receipts.
.PARAMETER Offline
Verifies and extracts existing pinned archives without network access; fails on a cache miss.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[switch]$Offline)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/RunToolCache.psm1')
Initialize-RunToolCache -OutputDirectory $OutputDirectory -Packages (Get-RunProfilerPackages) -Offline:$Offline
