#requires -Version 7.6
<#
.SYNOPSIS
Checks the planning baseline or explicitly synchronizes generated delivery views.
.PARAMETER WorkspaceRoot
Monorepo root containing the roadmap contracts.
.PARAMETER Apply
Synchronizes generated views and delivery references; honors WhatIf and Confirm.
.PARAMETER PlanPath
Explicit optional Markdown mirror of the master plan; requires Apply.
.EXAMPLE
./scripts/Invoke-RoadmapContract.ps1
.EXAMPLE
./scripts/Invoke-RoadmapContract.ps1 -Apply -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent), [switch]$Apply,[string]$PlanPath)
Import-Module (Join-Path $PSScriptRoot 'lib/Roadmap.Contracts.psm1') -ErrorAction Stop
if ($PlanPath -and !$Apply) { throw 'PlanPathRequiresApply' }
if ($Apply) {
    $forward = @{WorkspaceRoot=$WorkspaceRoot}
    if ($PlanPath) { $forward.PlanPath=$PlanPath }
    foreach ($key in @('WhatIf','Confirm')) { if ($PSBoundParameters.ContainsKey($key)) { $forward[$key]=$PSBoundParameters[$key] } }
    Sync-RoadmapContractView @forward
    if ($WhatIfPreference) { return }
}
$report = Get-RoadmapAssessment -WorkspaceRoot $WorkspaceRoot
$report
if (!$report.Passed) { throw "RoadmapContractInvalid:$($report.Errors -join ';')" }
