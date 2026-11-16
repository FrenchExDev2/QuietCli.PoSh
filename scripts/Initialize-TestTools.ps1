#requires -Version 7.6
<#
.SYNOPSIS
Prepares the checksum-pinned script test tools (Pester 6.2.0, PSScriptAnalyzer 1.25.0) in an isolated cache, without global installation.
.PARAMETER WorkspaceRoot
Repository root; defaults to the parent of this scripts directory.
.PARAMETER OutputDirectory
Optional cache directory; defaults to <workspace>/.cache/test-tools.
.PARAMETER Tool
Tools to prepare: pester, scriptanalyzer, or both (default).
.PARAMETER Offline
Verifies and extracts existing pinned archives without network access; fails on a cache miss.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))),[string]$OutputDirectory,[ValidateNotNullOrEmpty()][ValidateCount(1,2)][ValidateSet('pester','scriptanalyzer')][string[]]$Tool=@('pester','scriptanalyzer'),[switch]$Offline)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Initialize-TestTools')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/RunToolCache.psm1')) -DisableNameChecking -ErrorAction Stop
Initialize-QuietTestTools -WorkspaceRoot $WorkspaceRoot -OutputDirectory $OutputDirectory -Tool $Tool -Offline:$Offline
