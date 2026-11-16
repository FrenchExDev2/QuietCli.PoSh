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
    foreach($name in @('plan','source-checks','layout-tests')){
        if(!$Needs.Contains($name) -or $Needs[$name].result -cne 'success'){throw ('CiPlanPrerequisiteRequired: '+$name)}
    }
    $requirements=@{products='run_products';smokes='run_smokes';'tooling-only'='run_tooling';distribution='run_distribution'}
    foreach($name in $requirements.Keys){
        $flag=$Needs.plan.outputs[$requirements[$name]]
        if($flag -cnotin @('true','false')){throw ('CiPlanOutputMissing: '+$requirements[$name])}
        if(!$Needs.Contains($name)){throw ('CiPlanJobMissing: '+$name)}
        $expected=if($flag -ceq 'true'){'success'}else{'skipped'}
        if($Needs[$name].result -cne $expected){throw ('CiPlanScopeResultMismatch: '+$name+' expected '+$expected)}
    }
    foreach($name in $Needs.Keys){if($Needs[$name].result -cnotin @('success','skipped')){throw ('CiPlanJobFailed: '+$name)}}
    [pscustomobject]@{SchemaVersion=2;Ready=$true;QualificationMode='selected';Jobs=$Needs}
}
Export-ModuleMember -Function Assert-QuietCiPlanResults
