function Test-QuietToolingResults {
    <#
    .SYNOPSIS
    Verifies independent job results, fail-closed gates, malformed inputs, previews and workflow wiring.
    .PARAMETER WorkspaceRoot
    Checkout supplying the authoritative helpers and workflows.
    .PARAMETER RunDirectory
    Owned temporary evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/ToolingResults.psm1')) -DisableNameChecking -ErrorAction Stop
    $oracle={
        param($subject)
        $states=@('success','failure','cancelled','skipped','')
        $count=0
        foreach($a in $states){foreach($b in $states){foreach($c in $states){foreach($d in $states){
            $inputJson=@{'core-independence'=@{result=$a};tooling=@{result=$b};'run-profiles-mutation'=@{result=$c};'mutation-complete'=@{result=$d}}|ConvertTo-Json -Compress
            $actual=& $subject -NeedsJson $inputJson
            $expected=if($a -eq '' -or $b -eq '' -or $a -eq 'failure' -or $b -eq 'failure'){'failure'}elseif($a -eq 'cancelled' -or $b -eq 'cancelled'){'cancelled'}elseif($a -eq 'skipped' -or $b -eq 'skipped'){'skipped'}else{'success'}
            if($actual.FunctionalResult -cne $expected -or $actual.MutationResult -cne $(if($c){$c}else{'failure'}) -or $actual.CompletionResult -cne $(if($d){$d}else{'failure'})){throw 'ToolingResultPropertyFailed'}
            $count++
        }}}}
        foreach($invalid in @('{}','{"core-independence":{"result":true}}','{"tooling":{"result":"SUCCESS"}}','{"tooling":{"result":"success\nfunctional_result=success"}}')){
            $r=& $subject -NeedsJson $invalid
            if($r.FunctionalResult -cne 'failure' -or $r.MutationResult -cne 'failure' -or $r.CompletionResult -cne 'failure'){throw 'ToolingResultMalformedAccepted'}
        }
        $count
    }
    $properties=& $oracle (Get-Command Get-QuietToolingResults)
    $source=(Get-Command Get-QuietToolingResults).Definition
    $mutations=@(
        @("`$results['tooling'] -ceq `$state",'$false'),
        @("CompletionResult=`$results['mutation-complete']","CompletionResult='success'"),
        @("else{'failure'}","else{'success'}")
    )
    $killed=0
    foreach($mutation in $mutations){
        if(!$source.Contains($mutation[0])){throw 'ToolingResultMutationAnchorMissing'}
        $rejected=$false
        try{$null=& $oracle ([scriptblock]::Create($source.Replace($mutation[0],$mutation[1])))}catch{if($_.Exception.Message -like 'ToolingResult*'){$rejected=$true}else{throw}}
        if(!$rejected){throw 'ToolingResultMutantSurvived'}
        $killed++
    }
    foreach($json in @('null','[]','{',(' '*65537))){
        $rejected=$false;try{$null=Get-QuietToolingResults -NeedsJson $json}catch{$rejected=$true}
        if(!$rejected){throw 'ToolingResultInvalidJsonAccepted'}
    }
    $writer=[IO.Path]::Combine($WorkspaceRoot,'scripts/Write-ToolingResults.ps1')
    $output=[IO.Path]::Combine($RunDirectory,'tooling-results.output')
    $null=& $writer -NeedsJson '{}' -OutputPath $output -WhatIf
    if(Test-Path -LiteralPath $output){throw 'ToolingResultPreviewWroteOutput'}
    $null=& $writer -NeedsJson '{}' -OutputPath $output
    if([IO.File]::ReadAllText($output,[Text.Encoding]::UTF8) -cne "functional_result=failure`nmutation_result=failure`ncompletion_result=failure`n"){throw 'ToolingResultOutputChanged'}
    $gate=[IO.Path]::Combine($WorkspaceRoot,'scripts/Assert-QualificationGate.ps1')
    $gateCases=0
    foreach($field in @('ToolingWorkflowResult','ToolingResult','ToolingMutationResult','ToolingCompletionResult')){
        foreach($value in @('success','failure','cancelled','skipped','','unknown')){
            $id=[guid]::NewGuid().ToString('N')
            $parameters=@{Suite='Git';Revision=('a'*40);WindowsResult='success';LinuxResult='success';MutationResult='skipped';PerformanceResult='skipped';RequireTooling=$true;ToolingWorkflowResult='success';ToolingResult='success';ToolingMutationResult='success';ToolingCompletionResult='success';ReceiptPath=([IO.Path]::Combine($RunDirectory,$id+'.json'));OutputPath=([IO.Path]::Combine($RunDirectory,$id+'.output'))}
            $parameters[$field]=$value
            $accepted=$false;try{$null=& $gate @parameters;$accepted=$true}catch{if($_.Exception.Message -notlike 'QualificationRejected:*'){throw}}
            if($accepted -ne ($value -ceq 'success') -or (Test-Path -LiteralPath $parameters.OutputPath) -ne $accepted){throw 'ToolingGateAcceptedMissingEvidence'}
            $receipt=Get-Content -LiteralPath $parameters.ReceiptPath -Encoding utf8 -Raw|ConvertFrom-Json
            $receiptField=@{ToolingWorkflowResult='ToolingWorkflow';ToolingResult='Tooling';ToolingMutationResult='ToolingMutation';ToolingCompletionResult='ToolingCompletion'}[$field]
            if($receipt.$receiptField -cne $value){throw 'ToolingGateLostIndependentResult'}
            $gateCases++
        }
    }
    $parser=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $tooling=$parser.Deserialize([IO.File]::ReadAllText([IO.Path]::Combine($WorkspaceRoot,'.github/workflows/tooling-ci.yml'),[Text.Encoding]::UTF8))
    $ci=$parser.Deserialize([IO.File]::ReadAllText([IO.Path]::Combine($WorkspaceRoot,'.github/workflows/ci.yml'),[Text.Encoding]::UTF8))
    $job=$tooling['jobs']['results']
    if([string]$job['if'] -cne '${{ always() }}' -or (@($job['needs']|Sort-Object) -join ',') -cne 'core-independence,mutation-complete,run-profiles-mutation,tooling'){throw 'ToolingResultPrerequisitesChanged'}
    foreach($name in @('functional_result','mutation_result','completion_result')){
        if([string]$tooling['on']['workflow_call']['outputs'][$name]['value'] -cne ('${{ jobs.results.outputs.'+$name+' }}') -or [string]$job['outputs'][$name] -cne ('${{ steps.results.outputs.'+$name+' }}')){throw 'ToolingResultWorkflowOutputChanged'}
    }
    $step=@($ci['jobs']['qualification-gate']['steps']|Where-Object {$_['id'] -ceq 'gate'})[0]
    foreach($binding in @(@('TOOLING_RESULT','functional_result','ToolingResult'),@('TOOLING_MUTATION_RESULT','mutation_result','ToolingMutationResult'),@('TOOLING_COMPLETION_RESULT','completion_result','ToolingCompletionResult'))){
        if([string]$step['env'][$binding[0]] -cne ('${{ !inputs.run_tooling && ''skipped'' || needs.tooling.outputs.'+$binding[1]+' }}') -or !([string]$step['run']).Contains(('-'+$binding[2]+' $env:'+$binding[0]))){throw 'ToolingGateOutputBindingChanged'}
    }
    if([string]$step['env']['TOOLING_WORKFLOW_RESULT'] -cne '${{ needs.tooling.result }}' -or !([string]$step['run']).Contains('-ToolingWorkflowResult $env:TOOLING_WORKFLOW_RESULT')){throw 'ToolingGateOverallResultMissing'}
    [pscustomobject]@{ResultProperties=$properties;MalformedCases=8;GateCases=$gateCases;MutantsKilled=$killed;PreviewNoWrite=$true}
}
