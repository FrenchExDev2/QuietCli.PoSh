function Get-QuietCiProfilerModules {
    <#
    .SYNOPSIS
    Reads literal profiler selections from a parsed preparation command without executing workflow code.
    .PARAMETER Text
    PowerShell preparation step from the inspected workflow.
    #>
    param([string]$Text)
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'CiProfilerPreparationSyntaxInvalid'}
    $commands=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -match '(^|[\\/])Initialize-Profilers\.ps1$'},$true))
    if($commands.Count -ne 1){throw 'CiProfilerPreparationCommandRequired'}
    $elements=$commands[0].CommandElements
    $parameters=@(0..($elements.Count-1)|Where-Object {$elements[$_] -is [Management.Automation.Language.CommandParameterAst] -and $elements[$_].ParameterName -ieq 'Module'})
    if($parameters.Count -ne 1){throw 'CiProfilerModulesRequired'}
    $parameter=$elements[$parameters[0]]
    $argument=if($parameter.Argument){$parameter.Argument}elseif($parameters[0]+1 -lt $elements.Count){$elements[$parameters[0]+1]}else{$null}
    if(!$argument){throw 'CiProfilerModulesRequired'}
    try{$modules=@($argument.SafeGetValue()|ForEach-Object {([string]$_).ToLowerInvariant()})}catch{throw 'CiProfilerModulesMustBeLiteral'}
    if((($modules|Sort-Object) -join '|') -cne 'dottrace|profiler'){throw 'CiProfilerModulesIncomplete'}
    $modules
}

function Assert-QuietCiProfilerPreparation {
    <#
    .SYNOPSIS
    Separates optional product profiling from mandatory functional-tooling prerequisites.
    .PARAMETER ProductWorkflow
    Parsed reusable product workflow; only a restricted boolean condition is evaluated.
    .PARAMETER ToolingWorkflow
    Parsed tooling workflow whose preparation must precede its functional run.
    #>
    param($ProductWorkflow,$ToolingWorkflow)
    $prepare=@($ProductWorkflow['jobs']['windows']['steps']|Where-Object {[string]$_['run'] -match 'Initialize-Profilers\.ps1'})
    if($prepare.Count -ne 1){throw 'CiProductProfilerPreparationRequired'}
    $null=Get-QuietCiProfilerModules ([string]$prepare[0]['run'])
    $condition=([string]$prepare[0]['if']).Trim()
    if($condition.StartsWith('${{') -and $condition.EndsWith('}}')){$condition=$condition.Substring(3,$condition.Length-5).Trim()}
    # Whitelist the two declared inputs and boolean operators before translating to PowerShell.
    if($condition -cnotmatch "\A(?:(?:needs\.linux-matrix\.outputs\.has_core|inputs\.collect_performance|'true'|'false')|&&|\|\||==|!=|[!()]|\s)+\z"){throw 'CiProductProfilerConditionInvalid'}
    $expression=$condition.Replace('needs.linux-matrix.outputs.has_core','$hasCore').Replace('inputs.collect_performance','$collectPerformance').Replace('&&',' -and ').Replace('||',' -or ').Replace('==',' -eq ').Replace('!=',' -ne ').Replace('!',' -not ')
    try{$evaluate=[scriptblock]::Create($expression)}catch{throw 'CiProductProfilerConditionInvalid'}
    $properties=0
    foreach($hasCore in @('true','false','','unknown')){foreach($collectPerformance in @($false,$true)){
        $expected=$hasCore -ceq 'true' -and $collectPerformance
        if([bool](& $evaluate) -ne $expected){throw 'CiProductProfilerScopeChanged'}
        $properties++
    }}
    $steps=@($ToolingWorkflow['jobs']['tooling']['steps'])
    $prepareIndices=@(0..($steps.Count-1)|Where-Object {[string]$steps[$_]['run'] -match 'Initialize-Profilers\.ps1'})
    $runIndices=@(0..($steps.Count-1)|Where-Object {$steps[$_]['id'] -ceq 'run_profiles'})
    if($prepareIndices.Count -ne 1 -or $runIndices.Count -ne 1){throw 'CiToolingProfilerPreparationRequired'}
    $prepareIndex=$prepareIndices[0];$runIndex=$runIndices[0]
    if($prepareIndex -ge $runIndex){throw 'CiToolingProfilerPreparationTooLate'}
    $null=Get-QuietCiProfilerModules ([string]$steps[$prepareIndex]['run'])
    foreach($index in @($prepareIndex,$runIndex)){
        $condition=([string]$steps[$index]['if']).Trim()
        if($condition.StartsWith('${{') -and $condition.EndsWith('}}')){$condition=$condition.Substring(3,$condition.Length-5).Trim()}
        if($condition -and $condition -cne 'success()'){throw 'CiToolingProfilerMustRemainRequired'}
    }
    $preparation=[string]$steps[$prepareIndex]['run']
    foreach($name in @('GITHUB_ENV','QUIETCLI_PROFILER_MODULE','QUIETCLI_CLR_PROFILER')){if(!$preparation.Contains($name)){throw 'CiToolingProfilerPathsNotForwarded'}}
    if([string]$steps[$runIndex]['run'] -notmatch 'Invoke-GitHubCi\.ps1\s+-Suite\s+RunProfiles(?:\s|$)'){throw 'CiToolingProfilerFunctionalRunRequired'}
    [pscustomobject]@{ProductScopeProperties=$properties;ToolingPreparationPrecedesRun=$true}
}

function Test-QuietCiFailureRegression {
    <#
    .SYNOPSIS
    Rejects empty Docker parent defaults and exercises report-upload decisions from the actual workflow.
    .PARAMETER WorkspaceRoot
    Checkout containing the renderer and GitHub workflow under test.
    .PARAMETER RunDirectory
    Owned evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
    $assertRecipe={
        param($text,$parent)
        $default=[regex]::Match($text,'(?m)^ARG CORE_IMAGE=(\S+)$')
        if(!$default.Success -or $default.Groups[1].Value -cne $parent -or $parent -cnotmatch '\Alocalhost/quietcli2-ci-core-(?:debian|alpine)-(?:x64|arm64):[a-f0-9]{64}\z'){throw 'DockerParentDefaultInvalid'}
    }
    $plans=0
    foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){
        foreach($suite in @('Core','Git','All')){
            $plan=& (Join-Path $WorkspaceRoot 'scripts/New-CiSuiteImage.ps1') -WorkspaceRoot $WorkspaceRoot -Suite $suite -RuntimeIdentifier $rid -PlanOnly
            if($suite -ceq 'Core'){
                if($plan.ContainerfileText.Contains('${CORE_IMAGE}') -or $plan.Fingerprint -cnotmatch '\A[a-f0-9]{64}\z'){throw 'CoreImageDependsOnBusinessOverlay'}
            }else{
                & $assertRecipe $plan.ContainerfileText $plan.ParentReference
                if(!$plan.ParentReference.EndsWith(':'+$plan.Core.Fingerprint) -or !$plan.ParentReference.Contains('-'+$plan.Core.Architecture+':')){throw 'DockerParentDefaultLostIdentity'}
            }
            $plans++
        }
    }
    $stages=@([pscustomobject]@{Name='ci'})
    foreach($bad in @('','scratch','alpine:latest','localhost/quietcli2-ci-core-debian-x64:latest',"invalid`nparent")){
        $rejected=$false
        try{$null=Get-QuietModuleContainerfile -Platform debian -Objective fixture -Stages $stages -DefaultCoreImage $bad}catch{$rejected=$_.Exception.Message -ceq 'CiImageDefaultParentReferenceRequired'}
        if(!$rejected){throw 'UnsafeDockerParentDefaultAccepted'}
    }
    $reference='localhost/quietcli2-ci-core-debian-x64:'+('a'*64)
    $source=(Get-Command Get-QuietModuleContainerfile).ScriptBlock.ToString()
    $anchor="`$lines.Insert(1,'ARG CORE_IMAGE='+`$DefaultCoreImage)"
    if(!$source.Contains($anchor)){throw 'DockerParentDefaultMutationAnchorMissing'}
    $mutant=[scriptblock]::Create($source.Replace($anchor,"`$lines.Insert(1,'ARG CORE_IMAGE')"))
    $rendered=& $mutant -Platform debian -Objective fixture -Stages $stages -DefaultCoreImage $reference
    $rejected=$false;try{& $assertRecipe $rendered $reference}catch{$rejected=$_.Exception.Message -ceq 'DockerParentDefaultInvalid'}
    if(!$rejected){throw 'DockerEmptyDefaultMutantSurvived'}
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $yaml=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $workflow=$yaml.Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/tooling-ci.yml'),[Text.Encoding]::UTF8))
    $functional=@($workflow['jobs']['tooling']['steps'])
    $toolingUpload=@($functional|Where-Object {$_['with'] -and $_['with']['name'] -clike 'quietcli-tooling-*'})[0]
    $reportPaths=@(([string]$toolingUpload['with']['path']).Trim().Split("`n")|ForEach-Object {$_.Trim()})
    foreach($required in @('artifacts/tooling/tests/*.json','artifacts/tooling/tests/*.log','artifacts/run-profiles/tests/*.json','artifacts/core-independence/*/independence.json')){
        if($required -cnotin $reportPaths){throw 'ToolingReportEvidenceMissing'}
    }
    foreach($path in $reportPaths){if($path -cnotmatch '\.(json|log)\z'){throw 'ToolingFixtureTreeUploadedOnSuccess'}}
    $failureUpload=@($functional|Where-Object {$_['with'] -and $_['with']['name'] -clike 'quietcli-failed-tooling-fixtures-*'})
    if($failureUpload.Count -ne 1 -or [string]$failureUpload[0]['if'] -cnotmatch '^failure\(\) && ' -or $failureUpload[0]['with']['retention-days'] -ne 7){throw 'ToolingFailureFixturesNotBounded'}
    $mutation=@($workflow['jobs']['run-profiles-mutation']['steps'])
    $product=$yaml.Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/ci.yml'),[Text.Encoding]::UTF8))
    $profilerContract=Assert-QuietCiProfilerPreparation $product $workflow
    $productText=$product|ConvertTo-Json -Depth 60 -Compress
    $toolingText=$workflow|ConvertTo-Json -Depth 60 -Compress
    $productSteps=@($product['jobs']['windows']['steps'])
    $productIndex=@(0..($productSteps.Count-1)|Where-Object {[string]$productSteps[$_]['run'] -match 'Initialize-Profilers\.ps1'})[0]
    $prepareIndex=@(0..($functional.Count-1)|Where-Object {[string]$functional[$_]['run'] -match 'Initialize-Profilers\.ps1'})[0]
    $runIndex=@(0..($functional.Count-1)|Where-Object {$functional[$_]['id'] -ceq 'run_profiles'})[0]
    $profilerProperties=0;$seed=20261112;$random=[Random]::new($seed)
    $conditions=@(
        "needs.linux-matrix.outputs.has_core == 'true' && inputs.collect_performance",
        "inputs.collect_performance && needs.linux-matrix.outputs.has_core == 'true'",
        "!(needs.linux-matrix.outputs.has_core != 'true' || !inputs.collect_performance)"
    )
    foreach($iteration in 1..24){
        $candidateProduct=$productText|ConvertFrom-Json -AsHashtable
        $candidateTooling=$toolingText|ConvertFrom-Json -AsHashtable
        $condition=$conditions[$random.Next($conditions.Count)]
        $condition=(' '*$random.Next(1,4))+'('+$condition+')'+(' '*$random.Next(1,4))
        if($iteration%2){$condition='${{ '+$condition+' }}'}
        $candidateProduct['jobs']['windows']['steps'][$productIndex]['if']=$condition
        if($iteration%3){$candidateTooling['jobs']['tooling']['steps'][$prepareIndex]['run']=$candidateTooling['jobs']['tooling']['steps'][$prepareIndex]['run'].Replace('-Module profiler,dottrace','-Module dottrace,profiler')}
        $profilerProperties+=(Assert-QuietCiProfilerPreparation $candidateProduct $candidateTooling).ProductScopeProperties
    }
    $damages=@(
        @{Id='legacy-stable-row-condition';Change={param($p,$t)$p['jobs']['windows']['steps'][$productIndex]['if']="needs.linux-matrix.outputs.has_core == 'true' && (inputs.collect_performance || (matrix.rid == 'win-x64' && matrix.channel == 'stable' && matrix.mode == 'InProcess'))"}},
        @{Id='product-core-condition-only';Change={param($p,$t)$p['jobs']['windows']['steps'][$productIndex]['if']="needs.linux-matrix.outputs.has_core == 'true'"}},
        @{Id='product-performance-condition-only';Change={param($p,$t)$p['jobs']['windows']['steps'][$productIndex]['if']='inputs.collect_performance'}},
        @{Id='missing-product-preparation';Change={param($p,$t)$p['jobs']['windows']['steps'][$productIndex]['run']='Write-Host fixture'}},
        @{Id='missing-product-clr-tool';Change={param($p,$t)$p['jobs']['windows']['steps'][$productIndex]['run']=$p['jobs']['windows']['steps'][$productIndex]['run'].Replace('-Module profiler,dottrace','-Module profiler')}},
        @{Id='missing-tooling-ps-tool';Change={param($p,$t)$t['jobs']['tooling']['steps'][$prepareIndex]['run']=$t['jobs']['tooling']['steps'][$prepareIndex]['run'].Replace('-Module profiler,dottrace','-Module dottrace')}},
        @{Id='missing-tooling-preparation';Change={param($p,$t)$t['jobs']['tooling']['steps'][$prepareIndex]['run']='Write-Host fixture'}},
        @{Id='late-tooling-preparation';Change={param($p,$t)$steps=$t['jobs']['tooling']['steps'];$saved=$steps[$prepareIndex];$steps[$prepareIndex]=$steps[$runIndex];$steps[$runIndex]=$saved}},
        @{Id='optional-tooling-preparation';Change={param($p,$t)$t['jobs']['tooling']['steps'][$prepareIndex]['if']='inputs.collect_performance'}},
        @{Id='skipped-functional-run';Change={param($p,$t)$t['jobs']['tooling']['steps'][$runIndex]['if']='false'}},
        @{Id='missing-tool-path-forwarding';Change={param($p,$t)$t['jobs']['tooling']['steps'][$prepareIndex]['run']=$t['jobs']['tooling']['steps'][$prepareIndex]['run'].Replace('QUIETCLI_CLR_PROFILER','UNRELATED_VARIABLE')}},
        @{Id='dynamic-tool-selection';Change={param($p,$t)$t['jobs']['tooling']['steps'][$prepareIndex]['run']=$t['jobs']['tooling']['steps'][$prepareIndex]['run'].Replace('-Module profiler,dottrace','-Module $env:TOOLS')}}
    )
    foreach($damage in $damages){
        $candidateProduct=$productText|ConvertFrom-Json -AsHashtable;$candidateTooling=$toolingText|ConvertFrom-Json -AsHashtable
        & $damage.Change $candidateProduct $candidateTooling
        $rejected=$false;try{$null=Assert-QuietCiProfilerPreparation $candidateProduct $candidateTooling}catch{$rejected=$_.Exception.Message -match '^Ci(?:ProductProfiler|ToolingProfiler|Profiler)'}
        if(!$rejected){throw ('CiProfilerWorkflowMutationAccepted: '+$damage.Id)}
    }
    $conditionDamages=@('inputs.collect_performance; throw "must never execute"','$(throw "must never execute")',"needs.linux-matrix.outputs.has_core == 'true' && inputs.collect_performance`0")
    foreach($condition in $conditionDamages){
        $candidateProduct=$productText|ConvertFrom-Json -AsHashtable
        $candidateProduct['jobs']['windows']['steps'][$productIndex]['if']=$condition
        $rejected=$false;try{$null=Assert-QuietCiProfilerPreparation $candidateProduct $workflow}catch{$rejected=$_.Exception.Message -ceq 'CiProductProfilerConditionInvalid'}
        if(!$rejected){throw 'CiProfilerUnsafeConditionAccepted'}
    }
    if(@($functional|Where-Object {$_['id'] -ceq 'run_profiles'}).Count -ne 1 -or @($mutation|Where-Object {$_['id'] -ceq 'run_profiles_mutation'}).Count -ne 1){throw 'RunProfileEvidenceContractChanged'}
    $properties=0
    foreach($spec in @(@{Steps=$functional;Name='quietcli-tooling-*';Dual=$true},@{Steps=$mutation;Name='quietcli-run-profiles-mutation-*';Dual=$false})){
        $upload=@($spec.Steps|Where-Object {$_['with'] -and $_['with']['name'] -like $spec.Name})
        if($upload.Count -ne 1 -or $upload[0]['with']['if-no-files-found'] -cne 'error'){throw 'RunProfileEvidenceContractChanged'}
        $expression=([string]$upload[0]['if']).Replace('always()','$true').Replace('steps.tooling_tests.outcome','$toolingOutcome').Replace('steps.run_profiles_mutation.outcome','$mutationOutcome').Replace('steps.run_profiles.outcome','$functionalOutcome').Replace('&&','-and').Replace('||','-or').Replace('!=','-cne')
        $evaluate=[scriptblock]::Create($expression)
        foreach($toolingOutcome in @('','skipped','success','failure','cancelled')){
            foreach($functionalOutcome in @('','skipped','success','failure','cancelled')){
                foreach($mutationOutcome in @('','skipped','success','failure','cancelled')){
                    $expected=if($spec.Dual){@('success','failure','cancelled') -ccontains $toolingOutcome -or @('success','failure','cancelled') -ccontains $functionalOutcome}else{@('success','failure','cancelled') -ccontains $mutationOutcome}
                    if([bool](& $evaluate) -ne $expected){throw 'RunProfileUploadConditionChanged'}
                    $properties++
                }
            }
        }
        $toolingOutcome='skipped';$functionalOutcome='skipped';$mutationOutcome='skipped'
        if([bool](& $evaluate)){throw 'RunProfileSkippedUploadMutantNotDetected'}
    }
    Write-WorkspaceJson (Join-Path $RunDirectory 'ci-failure-regression.json') @{ImagePlans=$plans;InvalidParentDefaults=5;UploadDecisionProperties=$properties;MutantsKilled=2;ProfilerScopeProperties=($profilerProperties+$profilerContract.ProductScopeProperties);ProfilerWorkflowMutationsRejected=$damages.Count;MalformedProfilerConditionsRejected=$conditionDamages.Count;ProfilerSeed=$seed;DockerBuildExecuted=$false;RemoteWorkflowExecuted=$false}
}

function Test-QuietCiOptimization {
    <#
    .SYNOPSIS
    Exercises fail-closed qualification reuse, real parallel child isolation and offline host caches.
    .PARAMETER WorkspaceRoot
    Checkout containing the automation under test.
    .PARAMETER RunDirectory
    Owned output tree for fixtures and receipts.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
    $fixture=Join-Path $RunDirectory 'ci-optimization'
    [void][IO.Directory]::CreateDirectory($fixture)
    $revision='a'*40
    $receipt=[ordered]@{Ready=$true;Revision=$revision;Suite='All';Windows='success';Linux='success';Performance='success';PerformanceRequired=$true;Mutation='skipped';MutationRequired=$false;TtyQualification='Excluded';RunId='42';RunAttempt='2'}
    $path=Join-Path $fixture receipt.json;$output=Join-Path $fixture outputs.txt
    $validator=Join-Path $WorkspaceRoot scripts/Assert-QualificationReceipt.ps1
    Write-WorkspaceJson $path $receipt
    & $validator -ReceiptPath $path -Revision $revision -RunId 42 -RunAttempt 2 -OutputPath $output
    if((Get-Content $output -Raw -Encoding utf8) -cne "qualified_sha=$revision`n"){throw 'QualificationReceiptOutputChanged'}
    $rejections=0
    foreach($damage in @('Ready','Revision','Suite','Windows','Linux','Performance','PerformanceRequired','Mutation','MutationRequired','TtyQualification','RunId','RunAttempt')){
        $bad=[ordered]@{};foreach($key in $receipt.Keys){$bad[$key]=$receipt[$key]}
        $bad[$damage]=switch($damage){Ready{$false} MutationRequired{$true} PerformanceRequired{$false} default{'wrong'}}
        Write-WorkspaceJson $path $bad
        $before=(Get-FileHash $output).Hash;$rejected=$false
        try{& $validator -ReceiptPath $path -Revision $revision -RunId 42 -RunAttempt 2 -OutputPath $output}catch{$rejected=$true}
        if(!$rejected -or (Get-FileHash $output).Hash -cne $before){throw ('DamagedQualificationReceiptAccepted: '+$damage)}
        $rejections++
    }
    foreach($text in @('null','[]','{"Ready":true,"Ready":false}','{')){
        [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false));$rejected=$false
        try{& $validator -ReceiptPath $path -Revision $revision -RunId 42 -RunAttempt 2 -OutputPath $output}catch{$rejected=$true}
        if(!$rejected){throw 'MalformedQualificationReceiptAccepted'};$rejections++
    }
    & $validator -ReceiptPath (Join-Path $fixture absent.json) -Revision $revision -RunId 42 -RunAttempt 2 -OutputPath (Join-Path $fixture preview.txt) -WhatIf
    if(Test-Path (Join-Path $fixture preview.txt)){throw 'QualificationPreviewWroteOutput'}
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiCompanionWorkers.psm1') -Force
    $worker=Join-Path $fixture 'parallel-worker.ps1'
    $workerText=@'
param($WorkspaceRoot,$RunDirectory,$Suite,$MaxConcurrency,$ExpectedRuntimeIdentifier,[switch]$SkipTty)
Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
$started=[DateTimeOffset]::UtcNow.ToString('o')
$parent=Split-Path $RunDirectory -Parent
Write-WorkspaceJson (Join-Path $RunDirectory started.json) @{PID=$PID;Started=$started}
$other=if($Suite -eq 'Git'){'Vagrant'}else{'Git'}
$deadline=[DateTimeOffset]::UtcNow.AddSeconds(15)
while(!(Test-Path (Join-Path $parent "$other/started.json"))){
    if([DateTimeOffset]::UtcNow -gt $deadline){throw 'SiblingDidNotStartConcurrently'}
    [void][Threading.Tasks.Task]::Delay(25).GetAwaiter().GetResult()
}
if(Test-Path (Join-Path (Split-Path $parent -Parent) fail.txt)){exit 3}
Write-WorkspaceJson (Join-Path $RunDirectory summary.json) @{State=@{State='Success';Passed=1;Failed=0};Suites=@(@{Name=$Suite;PID=$PID;MaxConcurrency=$MaxConcurrency;SkipTty=[bool]$SkipTty;Rid=$ExpectedRuntimeIdentifier});Started=$started}
'@
    [IO.File]::WriteAllText($worker,$workerText,[Text.UTF8Encoding]::new($false))
    $selections=@([pscustomobject]@{Name='Git'},[pscustomobject]@{Name='Vagrant'})
    $core=[pscustomobject]@{Failed=0;Partial=$false;Incomplete=$false}
    $runs=Join-Path $fixture parallel
    $children=@(Invoke-QuietCiCompanionWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $runs -CoreSummary $core -Selections $selections -WorkerPath $worker -MaxConcurrency 2 -SkipTty -ExpectedRuntimeIdentifier fixture-rid)
    if($children.Count -ne 2 -or @($children.Suites.PID|Select-Object -Unique).Count -ne 2 -or @($children.Suites|Where-Object {$_.PID -eq $PID -or $_.MaxConcurrency -ne 1 -or !$_.SkipTty -or $_.Rid -cne 'fixture-rid'}).Count){throw 'CompanionProcessIsolationChanged'}
    $budgeted=@(Invoke-QuietCiCompanionWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $fixture budgeted) -CoreSummary $core -Selections $selections -WorkerPath $worker -MaxConcurrency 2 -WorkerBudget 4)
    if($budgeted.Count -ne 2 -or @($budgeted.Suites|Where-Object MaxConcurrency -NE 2).Count -or ($budgeted.Suites.MaxConcurrency|Measure-Object -Sum).Sum -gt 4){throw 'CompanionSharedBudgetNotDistributed'}
    foreach($field in @('Failed','Partial','Incomplete')){
        $bad=[pscustomobject]@{Failed=0;Partial=$false;Incomplete=$false};$bad.$field=1
        $target=Join-Path $fixture ('blocked-'+$field);$rejected=$false
        try{$null=Invoke-QuietCiCompanionWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $target -CoreSummary $bad -Selections $selections -WorkerPath $worker}catch{$rejected=$true}
        if(!$rejected -or (Test-Path $target)){throw 'FailedCoreStartedCompanions'}
    }
    $null=Invoke-QuietCiCompanionWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $fixture preview) -CoreSummary $core -Selections $selections -WorkerPath $worker -WhatIf
    if(Test-Path (Join-Path $fixture preview)){throw 'CompanionPreviewCreatedWorkers'}
    $failed=Join-Path $fixture failed;[void][IO.Directory]::CreateDirectory($failed)
    [IO.File]::WriteAllText((Join-Path $failed fail.txt),'fail',[Text.UTF8Encoding]::new($false))
    $rejected=$false
    try{$null=Invoke-QuietCiCompanionWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $failed -CoreSummary $core -Selections $selections -WorkerPath $worker}catch{$rejected=$_.Exception.Message -like 'CompanionWorker*'}
    if(!$rejected){throw 'ChildFailureAccepted'}
    # An independently constructed ZIP proves the host can be prepared with no HTTP request.
    $hostRoot=Join-Path $fixture host;[void][IO.Directory]::CreateDirectory((Join-Path $hostRoot build))
    $zipInput=Join-Path $fixture zip;[void][IO.Directory]::CreateDirectory($zipInput)
    [IO.File]::WriteAllText((Join-Path $zipInput pwsh.exe),'owned fixture',[Text.UTF8Encoding]::new($false))
    $zip=Join-Path $fixture host.zip;[IO.Compression.ZipFile]::CreateFromDirectory($zipInput,$zip)
    $hash=(Get-FileHash $zip).Hash
    Write-WorkspaceJson (Join-Path $hostRoot build/powershell-hosts.lock.json) @{SchemaVersion=1;Hosts=@(@{Channel='stable';Rid='win-x64';Version='7.6.7';SHA256=$hash;RuntimeMajor=10})}
    $cache=Join-Path $hostRoot '.cache/powershell-hosts';[void][IO.Directory]::CreateDirectory($cache)
    Copy-Item $zip (Join-Path $cache ($hash+'.zip'))
    foreach($index in 1..2){
        $hostInfo=& (Join-Path $WorkspaceRoot scripts/Initialize-PowerShellHost.ps1) -WorkspaceRoot $hostRoot -Channel stable -RuntimeIdentifier win-x64 -OutputDirectory (Join-Path $hostRoot "output-$index")
        if([IO.File]::ReadAllText($hostInfo.Executable) -cne 'owned fixture'){throw 'HostArchiveCacheChangedPayload'}
    }
    [IO.File]::WriteAllText((Join-Path $cache ($hash+'.zip')),'tampered',[Text.UTF8Encoding]::new($false))
    $rejected=$false
    try{$null=& (Join-Path $WorkspaceRoot scripts/Initialize-PowerShellHost.ps1) -WorkspaceRoot $hostRoot -Channel stable -RuntimeIdentifier win-x64 -OutputDirectory (Join-Path $hostRoot damaged)}catch{$rejected=$_.Exception.Message -ceq 'PowerShellHostCacheChecksumMismatch'}
    if(!$rejected){throw 'DamagedHostCacheAccepted'}
    $cacheModule=Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/CiImages.psm1')) -PassThru -DisableNameChecking -ErrorAction Stop
    $cacheAdapters=& $cacheModule { $saved=@{};foreach($name in @('Resolve-QuietVirtEngine','Get-QuietCiRegistryDigest','Invoke-CiProcess','Invoke-WorkspaceNative')){$saved[$name]=(Get-Command $name).ScriptBlock};$saved }
    try {
    $cacheChecks=& $cacheModule {
        param($WorkspaceRoot,$fixture)
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
        $script:ciCacheCalls=[Collections.Generic.List[string]]::new()
        $plan=[pscustomobject]@{Rid='linux-x64';Architecture='x64';Fingerprint=('a'*64);RegistryPath='fixture/image';Source='https://example.invalid/source';Base=$null;Dockerfile='fixture';Arguments=@{}}
        function script:Resolve-QuietVirtEngine {
            <#
            .SYNOPSIS
            Selects the owned Docker adapter without inspecting the host.
            .PARAMETER ContainerRuntime
            Requested adapter.
            .PARAMETER WorkspaceRoot
            Owned fixture checkout.
            #>
            param($ContainerRuntime,$WorkspaceRoot)
            'docker'
        }
        function script:Get-QuietCiRegistryDigest {
            <#
            .SYNOPSIS
            Supplies a synthetic immutable digest or an explicit cache miss without HTTP.
            .PARAMETER Plan
            Expected image plan.
            .PARAMETER Token
            Unused fixture credential.
            .PARAMETER Actor
            Unused registry actor.
            #>
            param($Plan,$Token,$Actor)
            if($script:ciCacheHit){'sha256:'+('b'*64)}
        }
        function script:Invoke-CiProcess {
            <#
            .SYNOPSIS
            Supplies synthetic daemon and image metadata to the actual validation callback.
            .PARAMETER FilePath
            Requested container executable.
            .PARAMETER ArgumentList
            Metadata operation being observed.
            .PARAMETER TimeoutSeconds
            Declared operation deadline.
            .PARAMETER State
            Caller-owned accumulator.
            .PARAMETER OnOutput
            Real metadata callback under test.
            #>
            param($FilePath,$ArgumentList,$TimeoutSeconds,$State,$OnOutput)
            $script:ciCacheCalls.Add($ArgumentList[0])
            $json=if($ArgumentList[0] -ceq 'info'){'{"OSType":"linux","Architecture":"amd64"}'}else{
                @{Id=('sha256:'+('1'*64));Architecture='amd64';Os='linux';Config=@{Labels=@{'org.frenchexdev.quietcli2.inputs'=('a'*64);'org.opencontainers.image.source'='https://example.invalid/source'}}}|ConvertTo-Json -Depth 6 -Compress
            }
            $null=& $OnOutput ([pscustomobject]@{Stream='stdout';Text=$json}) $State
            [pscustomobject]@{Outcome='Success';ExitCode=0;ElapsedMs=1}
        }
        function script:Invoke-WorkspaceNative {
            <#
            .SYNOPSIS
            Records requested image operations without pulling or building an image.
            .PARAMETER FilePath
            Requested adapter.
            .PARAMETER Arguments
            Exact native argument vector.
            .PARAMETER WorkingDirectory
            Owned fixture directory.
            .PARAMETER TimeoutSeconds
            Declared deadline.
            .PARAMETER LogPath
            Unused diagnostic destination.
            #>
            param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds,$LogPath)
            $script:ciCacheCalls.Add($Arguments[0])
        }
        $previous=$env:QUIETCLI_REGISTRY_TOKEN;$env:QUIETCLI_REGISTRY_TOKEN=$null
        try{
            foreach($hit in @($false,$true)){
                $script:ciCacheCalls.Clear();$script:ciCacheHit=$hit
                $result=Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory $fixture -WorkspaceRoot $fixture -ArtifactPrefix cache-only -RegistryCache -CacheOnly -ContainerRuntime docker
                if('build' -cin $script:ciCacheCalls -or @($script:ciCacheCalls|Where-Object {$_ -ceq 'pull'}).Count -ne [int]$hit -or [bool]$result -ne $hit){throw 'CacheOnlyPreparedMissingParents'}
            }
            $source=(Get-Command Invoke-QuietCiImageBuild).ScriptBlock.ToString()
            $anchor='if($CacheOnly -and !$digest){return}'
            if(!$source.Contains($anchor)){throw 'CacheOnlyMutationAnchorMissing'}
            $mutant=[scriptblock]::Create($source.Replace($anchor,''))
            $script:ciCacheHit=$false;$script:ciCacheCalls.Clear()
            $null=& $mutant -Plan $plan -ContextDirectory $fixture -WorkspaceRoot $fixture -ArtifactPrefix mutant -RegistryCache -CacheOnly -ContainerRuntime docker
            if('build' -cnotin $script:ciCacheCalls){throw 'CacheOnlyMutantNotDetected'}
        }finally{$env:QUIETCLI_REGISTRY_TOKEN=$previous}
        2
    } $WorkspaceRoot $fixture
    }finally{& $cacheModule {param($saved) foreach($name in $saved.Keys){Set-Item ('Function:script:'+$name) $saved[$name]}} $cacheAdapters}
    Write-WorkspaceJson $path $receipt
    $source=[IO.File]::ReadAllText($validator,[Text.Encoding]::UTF8)
    $mutant=[scriptblock]::Create($source.Replace('$receipt.Revision -cne $Revision','$false'))
    $damaged=[ordered]@{};foreach($key in $receipt.Keys){$damaged[$key]=$receipt[$key]};$damaged.Revision='b'*40;Write-WorkspaceJson $path $damaged
    $mutantOutput=Join-Path $fixture mutant-output.txt
    & $mutant -ReceiptPath $path -Revision $revision -RunId 42 -RunAttempt 2 -OutputPath $mutantOutput
    if(!(Test-Path $mutantOutput)){throw 'QualificationRevisionMutantNotExercised'}
    $warmRoot=Join-Path $fixture warm;$warmScripts=Join-Path $warmRoot scripts
    [void][IO.Directory]::CreateDirectory((Join-Path $warmScripts lib))
    Copy-Item (Join-Path $WorkspaceRoot scripts/lib/CiCompanions.psm1) (Join-Path $warmScripts lib/CiCompanions.psm1)
    $common='function Write-WorkspaceJson {param($Path,$Value); [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent));[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}'
    $images='function Get-QuietCiRegistryDigest {param($Plan,$Token,$Actor,[switch]$IncludeConfiguration); if(!$IncludeConfiguration){throw "ConfigurationNotVerified"}; [pscustomobject]@{Digest=("sha256:"+("b"*64));Reference=("ghcr.io/fixture@sha256:"+("b"*64))}}; function Invoke-QuietCiImageBuild {param($Plan,$ContextDirectory,$WorkspaceRoot,$ArtifactPrefix,[switch]$RegistryCache,[switch]$CacheOnly,$ContainerRuntime);if(!$CacheOnly){throw "UnexpectedBuild"};[pscustomobject]@{Image="verified-final-local";CacheHit=$true}}'
    $plan='param($WorkspaceRoot,$RuntimeIdentifier,$Module,$ParentPlan,[switch]$PlanOnly);if(!$PlanOnly){throw "ParentPreparedOnFinalHit"};[pscustomobject]@{Fingerprint=("a"*64);Rid=$RuntimeIdentifier}'
    foreach($entry in @{'lib/Common.psm1'=$common;'lib/CiImages.psm1'=$images;'New-CiImage.ps1'=$plan;'New-CiModuleImage.ps1'=$plan}.GetEnumerator()){[IO.File]::WriteAllText((Join-Path $warmScripts $entry.Key),$entry.Value,[Text.UTF8Encoding]::new($false))}
    $module=Import-Module (Join-Path $warmScripts lib/CiCompanions.psm1) -PassThru -Force
    try{
        $selection=[pscustomobject]@{Images=@('Core','Git')}
        $resolved=& $module {param($root,$selection) Invoke-QuietCiSuiteImage -WorkspaceRoot $root -Selection $selection -RuntimeIdentifier linux-x64 -RegistryCache -ResolveOnly -ContainerRuntime docker} $warmRoot $selection
        $probed=& $module {param($root,$selection) Invoke-QuietCiSuiteImage -WorkspaceRoot $root -Selection $selection -RuntimeIdentifier linux-x64 -RegistryCache -ProbeOnly -ContainerRuntime docker} $warmRoot $selection
        $pulled=& $module {param($root,$selection) Invoke-QuietCiSuiteImage -WorkspaceRoot $root -Selection $selection -RuntimeIdentifier linux-x64 -RegistryCache -ContainerRuntime docker} $warmRoot $selection
        if(!$resolved.RegistryOnly -or !$resolved.CacheHit -or $pulled.Image -cne 'verified-final-local'){throw 'WarmFinalImagePreparedParents'}
        if(!$probed.RegistryOnly -or !$probed.CacheHit){throw 'ProbePreparedWarmImage'}
        $missSource=$images.Replace('if(!$IncludeConfiguration)', 'if($true){return};if(!$IncludeConfiguration)')
        [IO.File]::WriteAllText(([IO.Path]::Combine($warmScripts,'lib/CiImages.psm1')),$missSource,[Text.UTF8Encoding]::new($false))
        & $module {param($path) Get-Module CiImages -All | Where-Object Path -EQ $path | Remove-Module -Force} ([IO.Path]::GetFullPath([IO.Path]::Combine($warmScripts,'lib/CiImages.psm1')))
        $miss=& $module {param($root,$selection) Invoke-QuietCiSuiteImage -WorkspaceRoot $root -Selection $selection -RuntimeIdentifier linux-x64 -RegistryCache -ProbeOnly -ContainerRuntime docker} $warmRoot $selection
        if(!$miss.RegistryOnly -or $miss.CacheHit){throw 'ProbePreparedMissingImage'}
    }finally{Remove-Module -ModuleInfo $module -Force}
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $yaml=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $workflows=@{}
    foreach($name in @('ci','companions-ci','preview-psgallery','publish-psgallery','release-tags')){$workflows[$name]=$yaml.Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot ".github/workflows/$name.yml"),[Text.Encoding]::UTF8))}
    $jobs=$workflows.ci['jobs']
    if($jobs.ContainsKey('linux-suite-images') -or @($jobs['linux-images']['needs']).Count -ne 1 -or @($jobs['linux-images']['needs'])[0] -cne 'linux-matrix'){throw 'DuplicateImageProducerMatrix'}
    $producer=@($jobs['linux-images']['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
    if(!$producer.Contains('-ResolveOnly') -or !$producer.Contains('-PublishCache')){throw 'ProducerDownloadsUnusedCachedImages'}
    if($workflows['preview-psgallery']['on'].ContainsKey('push') -or $workflows['companions-ci']['jobs'].ContainsKey('preview') -or $workflows['preview-psgallery']['jobs']['preview']['with']['publish'] -cne 'false'){throw 'DevelopStillPublishesGalleryPackages'}
    $publication=$workflows['publish-psgallery']['jobs']
    if($publication['qualification']['if'] -cne "inputs.qualified_sha == ''" -or $publication['reuse-qualification']['steps'][-1]['run'] -notmatch 'Assert-QualificationReceipt.ps1' -or $publication['package']['needs'] -cne 'checkpoint'){throw 'UnverifiedQualificationReuse'}
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/GalleryRelease.psm1) -Force
    $releaseFixture=Join-Path $fixture release-policy
    foreach($entry in @(@('Core','3.4.5'),@('Git','1.2.3'),@('Vagrant','8.9.0'))){
        $project="FrenchExDev2.QuietCli.$($entry[0]).PoSh";$root=Join-Path $releaseFixture $project
        [void][IO.Directory]::CreateDirectory($root)
        [IO.File]::WriteAllText((Join-Path $root "$project.psm1"),"throw 'ReleasePlanExecutedModule'`n",[Text.UTF8Encoding]::new($false))
        $text="@{RootModule='$project.psm1';ModuleVersion='$($entry[1])';PrivateData=@{PSData=@{Prerelease='preview'};QuietCli=@{Publishable=`$"+$(if($entry[0] -ceq 'Core'){'true'}else{'false'})+"}}}`n"
        [IO.File]::WriteAllText((Join-Path $root "$project.psd1"),$text,[Text.UTF8Encoding]::new($false))
    }
    $releasePlan=Resolve-QuietGalleryReleaseTag $releaseFixture 'FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview'
    if($releasePlan.Module -cne 'FrenchExDev2.QuietCli.Core.PoSh' -or $releasePlan.Component -cne 'Core' -or $releasePlan.Version -cne '3.4.5-preview'){throw 'ReleasePlanIdentityChanged'}
    $coreManifest=Join-Path $releaseFixture 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
    $savedManifest=[IO.File]::ReadAllText($coreManifest,[Text.Encoding]::UTF8)
    try{
        [IO.File]::WriteAllText($coreManifest,"@{RootModule='FrenchExDev2.QuietCli.Core.PoSh.psm1';ModuleVersion='3.4.5';PrivateData=@{PSData=@{};QuietCli=@{Publishable=`$true}}}`n",[Text.UTF8Encoding]::new($false))
        if((Resolve-QuietGalleryReleaseTag $releaseFixture 'FrenchExDev2.QuietCli.Core.PoSh/v3.4.5').Version -cne '3.4.5'){throw 'StableReleasePlanRejected'}
        foreach($policyValue in @('$false',"'true'",'$null')){
            [IO.File]::WriteAllText($coreManifest,"@{RootModule='FrenchExDev2.QuietCli.Core.PoSh.psm1';ModuleVersion='3.4.5';PrivateData=@{PSData=@{};QuietCli=@{Publishable=$policyValue}}}`n",[Text.UTF8Encoding]::new($false))
            $rejected=$false;try{$null=Resolve-QuietGalleryReleaseTag $releaseFixture 'FrenchExDev2.QuietCli.Core.PoSh/v3.4.5'}catch{$rejected=$_.Exception.Message -like 'GalleryReleaseModuleNotPublishable:*' -or $_.Exception.Message -ceq 'GalleryPublicationPolicyMustBeBoolean'}
            if(!$rejected){throw 'NonBooleanOrFalsePublicationPolicyAccepted'}
        }
    }finally{[IO.File]::WriteAllText($coreManifest,$savedManifest,[Text.UTF8Encoding]::new($false))}
    foreach($component in @('Git','Vagrant')){
        $project="FrenchExDev2.QuietCli.$component.PoSh";$companionManifest=Join-Path $releaseFixture "$project/$project.psd1"
        $data=[IO.File]::ReadAllText($companionManifest,[Text.Encoding]::UTF8)
        try{
            [IO.File]::WriteAllText($companionManifest,$data.Replace('Publishable=$false','Publishable=$true'),[Text.UTF8Encoding]::new($false))
            $tagVersion=if($component -ceq 'Git'){'1.2.3-preview'}else{'8.9.0-preview'}
            $enabled=Resolve-QuietGalleryReleaseTag $releaseFixture "$project/v$tagVersion"
            if($enabled.Module -cne $project -or $enabled.Version -cne $tagVersion){throw 'IndependentCompanionReleaseIdentityChanged'}
        }finally{[IO.File]::WriteAllText($companionManifest,$data,[Text.UTF8Encoding]::new($false))}
    }
    $releaseRejections=0
    foreach($tag in @('v3.4.5-preview','FrenchExDev2.QuietCli.Core.PoSh/v3.4.5','FrenchExDev2.QuietCli.Core.PoSh/v3.4.6-preview','FrenchExDev2.QuietCli.Core.PoSh/v03.4.5-preview','quietcli/v3.4.5-preview','FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview.1','FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview+42',"FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview`n",'../FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview','FrenchExDev2.QuietCli.Git.PoSh/v1.2.3-preview','FrenchExDev2.QuietCli.Vagrant.PoSh/v8.9.0-preview')){
        $rejected=$false;try{$null=Resolve-QuietGalleryReleaseTag $releaseFixture $tag}catch{$rejected=$true}
        if(!$rejected){throw ('InvalidReleaseTagAccepted: '+$tag)};$releaseRejections++
    }
    $planScript=Join-Path $WorkspaceRoot scripts/Get-QuietReleasePlan.ps1
    $planOutput=Join-Path $releaseFixture outputs.txt
    $null=& $planScript -WorkspaceRoot $releaseFixture -Tag 'FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview' -OutputPath $planOutput -WhatIf
    if(Test-Path -LiteralPath $planOutput){throw 'ReleasePlanPreviewWroteOutput'}
    $null=& $planScript -WorkspaceRoot $releaseFixture -Tag 'FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview' -OutputPath $planOutput -Confirm:$false
    if([IO.File]::ReadAllText($planOutput,[Text.Encoding]::UTF8) -cne "module=FrenchExDev2.QuietCli.Core.PoSh`ncomponent=Core`nversion=3.4.5-preview`n"){throw 'ReleasePlanOutputsChanged'}
    $releaseWorkflow=$workflows['release-tags']
    if($releaseWorkflow['jobs']['release']['if'] -cne "needs.plan.outputs.is_leader == 'true'" -or $releaseWorkflow['jobs']['release']['with']['release_tags'] -cne '${{ needs.plan.outputs.release_tags }}'){throw 'ReleaseBatchFollowerWouldStartQualification'}
    if($releaseWorkflow['on'].Count -ne 1 -or @($releaseWorkflow['on']['push']['tags']).Count -ne 1 -or $releaseWorkflow['on']['push']['tags'][0] -cne 'FrenchExDev2.QuietCli.*.PoSh/v*' -or $releaseWorkflow['jobs']['release']['needs'] -cne 'plan' -or $releaseWorkflow['jobs']['release']['with']['module'] -cne '${{ needs.plan.outputs.module }}' -or $releaseWorkflow['jobs']['release']['with']['version'] -cne '${{ needs.plan.outputs.version }}' -or $releaseWorkflow['jobs']['release']['with']['publish'] -cne 'true'){throw 'ReleaseTagRoutingChanged'}
    $condition=[string]$publication['publish']['if']
    $expression=$condition.Replace('${{','').Replace('}}','').Replace('!cancelled()','(-not $cancelled)').Replace('inputs.publish','$requestPublish').Replace('inputs.preview_build','$previewBuild').Replace('github.repository','$repository').Replace('github.event_name','$eventName').Replace("startsWith(github.ref, 'refs/tags/FrenchExDev2.QuietCli.')","`$releaseRef.StartsWith('refs/tags/FrenchExDev2.QuietCli.',[StringComparison]::Ordinal)").Replace('needs.checkpoint.result','$checkpointResult').Replace('needs.checkpoint.outputs.qualified_sha','$qualifiedSha').Replace('github.sha','$checkoutSha').Replace('&&','-and').Replace('!=','-cne').Replace('==','-ceq').Replace('true','$true')
    $evaluate=[scriptblock]::Create($expression);$releaseProperties=0
    foreach($eventName in @('push','workflow_dispatch','pull_request')){foreach($releaseRef in @('refs/heads/develop','refs/tags/FrenchExDev2.QuietCli.Core.PoSh/v3.4.5-preview','refs/tags/FrenchExDev2.QuietCli.Git.PoSh/v1.2.3-preview')){foreach($requestPublish in @($true,$false)){foreach($previewBuild in @($true,$false)){foreach($repository in @('FrenchExDev2/QuietCli.PoSh','fork/repo')){foreach($cancelled in @($true,$false)){foreach($checkpointResult in @('success','failure')){foreach($qualifiedSha in @('a','b')){
        $checkoutSha='a'
        $expected=$eventName -ceq 'push' -and $releaseRef.StartsWith('refs/tags/FrenchExDev2.QuietCli.',[StringComparison]::Ordinal) -and $requestPublish -and !$previewBuild -and $repository -ceq 'FrenchExDev2/QuietCli.PoSh' -and !$cancelled -and $checkpointResult -ceq 'success' -and $qualifiedSha -ceq $checkoutSha
        if([bool](& $evaluate) -ne $expected){throw 'ReleasePublicationBoundaryChanged'};$releaseProperties++
    }}}}}}}}
    . (Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.Tests.PoSh/PreviewTag.Tests.ps1)
    Invoke-QuietPreviewTagTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $releaseFixture
    . (Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.Tests.PoSh/ReleaseTags.Tests.ps1)
    Test-QuietReleaseTags -WorkspaceRoot $WorkspaceRoot -RunDirectory $releaseFixture
    Write-WorkspaceJson (Join-Path $releaseFixture campaign.json) @{MalformedOrUnavailableTags=$releaseRejections;PublicationProperties=$releaseProperties;RealLocalTagLifecycle=$true;RemotePublication=$false}
    foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){
        $declaration=& (Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1) -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $rid
        $packages=@($declaration.Containerfile.Stages|Where-Object Name -CEQ ci)[0].Packages.Split(' ')
        if('tar' -cnotin $packages -or 'zstd' -cnotin $packages){throw 'ContainerCacheArchiveToolsMissing'}
    }
    Write-WorkspaceJson (Join-Path $fixture campaign.json) @{QualificationRejections=$rejections;RealParallelProcesses=2;CorePrerequisiteRejections=3;ChildFailureRejected=$true;HostCacheHits=2;DamagedCacheRejected=$true;CacheOnlyCases=$cacheChecks;WarmFinalImageCases=2;MutantsKilled=2;NetworkRequests=0;ExternalPublication=$false}
}
