#requires -Version 7.6
<#
.SYNOPSIS
Blocking PSScriptAnalyzer check of scripts/ and test/scripts/ against the pinned analyzer, the repository rules and a shrink-only baseline.
.PARAMETER WorkspaceRoot
Working tree or exported snapshot to analyze; defaults to the parent of this scripts directory.
.PARAMETER CacheDirectory
Optional per-file analysis cache; defaults to .cache/script-analysis of the repository that owns this script.
.PARAMETER UpdateBaseline
Prunes stale entries from test/scripts/ScriptAnalyzer.baseline.json; never adds one.
.PARAMETER Offline
Requires the pinned PSScriptAnalyzer to be cached already.
.PARAMETER TimeoutSeconds
Wall-clock limit for the analyzer worker.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))),[string]$CacheDirectory,[switch]$UpdateBaseline,[switch]$Offline,[ValidateRange(1,7200)][int]$TimeoutSeconds=900)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Execute automation: Test-ScriptAnalysis')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Test-ScriptAnalysis.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptTestScriptAnalysis -WorkspaceRoot $WorkspaceRoot -ToolRoot ([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))) -CacheDirectory $CacheDirectory -UpdateBaseline:$UpdateBaseline -Offline:$Offline -TimeoutSeconds $TimeoutSeconds
