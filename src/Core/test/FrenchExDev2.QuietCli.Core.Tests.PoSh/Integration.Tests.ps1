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
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/PesterProgress.psm1')) -DisableNameChecking -ErrorAction Stop
    $evidence=@{}
    $cases=[ordered]@{
        'Owned complex Git states with Core callbacks only'={
            $evidence.Bundle=Test-QuietEvidenceBundle -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
            $evidence.Gate=Test-QuietCoreIntegrationGate -WorkspaceRoot $WorkspaceRoot
            $evidence.Controlled=Invoke-QuietControlledStatusIntegration -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {
                param($name)
                if($OnProgress){& $OnProgress $name Running 0 0}
            }.GetNewClosure()
        }
        'Fresh process import measurement'={
            $evidence.Import=Invoke-QuietImportIntegration -WorkspaceRoot $WorkspaceRoot
        }
        'Import diagnostics and startup'={
            $evidence.Diagnostics=Invoke-QuietImportDiagnostics -WorkspaceRoot $WorkspaceRoot
            $evidence.Startup=Invoke-QuietStartupIntegration -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        }
    }
    $tested=Invoke-QuietPesterCaseTable -WorkspaceRoot $WorkspaceRoot -Suite Integration -Cases $cases -OnProgress $OnProgress -InvokePester {
        param($configuration,$body)
        if($body){& $body}else{Pester\Invoke-Pester -Configuration $configuration}
    }
    $summary=[pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$tested.Passed;Failed=$tested.Failed;Cases=$tested.Cases;Performance=@($evidence.Import,$evidence.Diagnostics,$evidence.Startup);Integration=@($evidence.Controlled);GateValidation=$evidence.Gate;EvidenceValidation=$evidence.Bundle}
    if(!$summary.Failed){& ([IO.Path]::Combine($WorkspaceRoot,'scripts/Assert-CoreIntegrationEvidence.ps1')) -Summary $summary}
    return $summary
}
