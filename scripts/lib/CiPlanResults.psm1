#requires -Version 7.6
function Assert-QuietCiPlanResults {
    <#
    .SYNOPSIS
    Rejects failed, cancelled, missing or wrongly skipped jobs required by the selective plan.
    .PARAMETER Needs
    GitHub needs object with planning outputs and actual results.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Needs)
    $issues=[Collections.Generic.List[string]]::new()
    foreach($name in @('plan','source-checks','layout-tests')){
        if(!$Needs.Contains($name) -or $Needs[$name].result -cne 'success'){$issues.Add('CiPlanPrerequisiteRequired: '+$name)}
    }
    $requirements=[ordered]@{products='run_products';smokes='run_smokes';'tooling-only'='run_tooling';distribution='run_distribution'}
    foreach($name in $requirements.Keys){
        $flag=if($Needs.Contains('plan') -and $Needs.plan.outputs){$Needs.plan.outputs[$requirements[$name]]}
        if($flag -cnotin @('true','false')){$issues.Add('CiPlanOutputMissing: '+$requirements[$name])}
        if(!$Needs.Contains($name)){$issues.Add('CiPlanJobMissing: '+$name);continue}
        if($flag -cnotin @('true','false')){continue}
        $expected=if($flag -ceq 'true'){'success'}else{'skipped'}
        if($Needs[$name].result -cne $expected){$issues.Add('CiPlanScopeResultMismatch: '+$name+' expected '+$expected+'; observed '+$Needs[$name].result)}
    }
    foreach($name in @($Needs.Keys|Sort-Object)){
        if($name -cnotin @('plan','source-checks','layout-tests') -and !$requirements.Contains($name) -and $Needs[$name].result -cnotin @('success','skipped')){$issues.Add('CiPlanJobFailed: '+$name)}
    }
    if($issues.Count){throw ($issues -join "`n")}
    [pscustomobject]@{SchemaVersion=2;Ready=$true;QualificationMode='selected';Jobs=$Needs}
}
Export-ModuleMember -Function Assert-QuietCiPlanResults
