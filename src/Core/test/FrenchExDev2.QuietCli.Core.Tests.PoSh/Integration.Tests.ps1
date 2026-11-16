. (Join-Path $PSScriptRoot 'Import.Tests.ps1')
. (Join-Path $PSScriptRoot 'Status.Controlled.Tests.ps1')
. (Join-Path $PSScriptRoot 'Integration.Gate.Tests.ps1')
. (Join-Path $PSScriptRoot 'Evidence.Tests.ps1')
function Invoke-QuietCoreIntegrationTests {
    <#
    .SYNOPSIS
    Runs the same mandatory import and controlled Git scenarios required by Core/All CI.
    .PARAMETER WorkspaceRoot
    Local monorepo.
    .PARAMETER RunDirectory
    Shared run directory containing all uploaded evidence and owned fixtures.
    .PARAMETER OnProgress
    Visible-monitor observer with name/state/passed/failed arguments.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[scriptblock]$OnProgress)
    $evidenceValidation=Test-QuietEvidenceBundle -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    $gateValidation=Test-QuietCoreIntegrationGate -WorkspaceRoot $WorkspaceRoot
    if($OnProgress){& $OnProgress 'Owned complex Git states with Core callbacks only' Running 0 0}
    $controlled=Invoke-QuietControlledStatusIntegration -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {
        param($name)
        if($OnProgress){& $OnProgress $name Running 0 0}
    }.GetNewClosure()
    if($OnProgress){& $OnProgress 'Fresh process import measurement' Running 1 0}
    $import=Invoke-QuietImportIntegration -WorkspaceRoot $WorkspaceRoot
    if($OnProgress){& $OnProgress 'Import diagnostics' Running 2 0}
    $diagnostics=Invoke-QuietImportDiagnostics -WorkspaceRoot $WorkspaceRoot
    $summary=[pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=3;Failed=0;Performance=@($import,$diagnostics);Integration=@($controlled);GateValidation=$gateValidation;EvidenceValidation=$evidenceValidation}
    & (Join-Path $WorkspaceRoot 'scripts/Assert-CoreIntegrationEvidence.ps1') -Summary $summary
    if($OnProgress){& $OnProgress 'Mandatory Core integration evidence verified' Passed 3 0}
    return $summary
}
