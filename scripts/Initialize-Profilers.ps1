<#
.SYNOPSIS
Explicitly downloads checksum-pinned diagnostic tools to an isolated cache, without global installation.
.PARAMETER OutputDirectory
Dedicated cache for the two exact packages and their extraction receipts.
.PARAMETER Offline
Verifies and extracts existing pinned archives without network access; fails on a cache miss.
.PARAMETER Module
Tools to prepare: profiler, dottrace, or both (default). Unselected tools are not required.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$OutputDirectory,[switch]$Offline,[ValidateNotNullOrEmpty()][ValidateCount(1,2)][ValidateSet('profiler','dottrace')][string[]]$Module=@('profiler','dottrace'))
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Initialize-Profilers')){return}
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/RunToolCache.psm1')
Initialize-RunToolCache -OutputDirectory $OutputDirectory -Packages (Get-RunProfilerPackages -Module $Module) -Offline:$Offline
