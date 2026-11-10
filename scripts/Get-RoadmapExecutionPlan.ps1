#requires -Version 7.6
<#
.SYNOPSIS
Returns a typed, read-only production plan including parallel waves and downstream consumers.
.PARAMETER WorkspaceRoot
Monorepo containing canonical roadmap and execution JSON.
.PARAMETER Target
Exact configured delivery node, such as I3 or CON; not a static ValidateSet because the graph is configurable.
#>
[CmdletBinding()]
param([ValidateNotNullOrEmpty()][string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$Target)
Import-Module (Join-Path $PSScriptRoot 'lib/Roadmap.Progression.psm1') -ErrorAction Stop
$docs=Join-Path $WorkspaceRoot 'docs/requirements'
$model=Get-Content -LiteralPath (Join-Path $docs 'software-ecosystem-factory.roadmaps.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 64
$execution=Get-Content -LiteralPath (Join-Path $docs 'software-ecosystem-factory.execution.json') -Raw -Encoding utf8 | ConvertFrom-Json -Depth 32
$forward=@{Model=$model;Execution=$execution}
if($Target){$forward.Target=$Target}
Get-RoadmapExecutionPlan @forward
