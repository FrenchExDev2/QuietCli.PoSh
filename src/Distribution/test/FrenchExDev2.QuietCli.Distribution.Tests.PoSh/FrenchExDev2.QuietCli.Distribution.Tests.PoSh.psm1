#requires -Version 7.6
function Invoke-QuietDistributionTests {
    <#
    .SYNOPSIS
    Qualifies complete Core distribution packages once, independently of the native product matrix.
    .PARAMETER WorkspaceRoot
    Verified checkout with all six Core distributions and no required Git business module.
    .PARAMETER RunDirectory
    Owned evidence directory.
    .PARAMETER OnProgress
    Classified case progress callback.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[scriptblock]$OnProgress)
    $distributionRoot=$PSScriptRoot
    & (Get-Module FrenchExDev2.QuietCli.Core.Tests.PoSh) {
        param($WorkspaceRoot,$RunDirectory,$OnProgress,$distributionRoot)
        . (Join-Path $distributionRoot 'Cases.ps1')
        $galleryEvidence=[Collections.Generic.List[object]]::new()
        $cases=[ordered]@{}
        $cases['all six embedded engines have matching native and managed architectures']={Test-QuietEmbeddedDistributions $WorkspaceRoot $RunDirectory}
        $cases['PSGallery Core installs outside sources with its embedded engine and no Git companion']={Test-QuietCoreGalleryDistribution $WorkspaceRoot $RunDirectory}
        $cases['Recall companion development tools work in source-free packages']={Test-QuietRecallDistribution $WorkspaceRoot $RunDirectory}
        $caseMetadata=@{
            'all six embedded engines have matching native and managed architectures'=@{TestKind='Integration';Dependencies=@('FileSystem')}
            'PSGallery Core installs outside sources with its embedded engine and no Git companion'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
            'Recall companion development tools work in source-free packages'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        }
        Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys) -Metadata $caseMetadata
        $policy=Get-QuietTestExecutionPolicy -ManifestPath (Join-Path $distributionRoot 'FrenchExDev2.QuietCli.Distribution.Tests.PoSh.psd1') -CaseNames @($cases.Keys)
        $selected=@($cases.Keys|Where-Object {!$env:QUIETCLI_TEST_CASE -or $_ -like $env:QUIETCLI_TEST_CASE})
        $plan=Get-QuietTestExecutionPlan -CaseNames $selected -Policy $policy -MaxConcurrency 1
        if(@($plan.Stages|Where-Object Mode -CNE Ordered).Count){throw 'DistributionExecutionMustRemainOrdered'}
        Write-WorkspaceJson (Join-Path $RunDirectory 'distribution-execution-plan.json') $plan
        $results=[Collections.Generic.List[object]]::new();$passed=0;$failed=0;$stoppedAt=$null
        foreach($name in $selected){
            if($stoppedAt){continue}
            if($OnProgress){& $OnProgress ('[Integration] '+$name) Running $passed $failed}
            $errorText=$null
            try{$null=& $cases[$name];$passed++;$state='Passed'}catch{$failed++;$state='Failed';$errorText=$_.ToString()+"`n"+$_.ScriptStackTrace}
            $results.Add([pscustomobject]@{Name=$name;State=$state;Error=$errorText;TestKind=$caseMetadata[$name].TestKind;Dependencies=$caseMetadata[$name].Dependencies})
            if($OnProgress){& $OnProgress ('[Integration] '+$name) $state $passed $failed}
            if($failed -and $env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE -ceq '1'){$stoppedAt='stopped at case '+$results.Count+' of '+$cases.Count}
        }
        [pscustomobject]@{Project='FrenchExDev2.QuietCli.Distribution.Tests.PoSh';Passed=$passed;Failed=$failed;Partial=[bool]$env:QUIETCLI_TEST_CASE;Incomplete=[bool]$stoppedAt;StoppedAt=$stoppedAt;Skipped=($cases.Count-$results.Count);Cases=$results.ToArray();Gallery=$galleryEvidence.ToArray();ExecutionPlan=$plan}
    } $WorkspaceRoot $RunDirectory $OnProgress $distributionRoot
}
Export-ModuleMember -Function Invoke-QuietDistributionTests
