function Assert-QuietNuGetCacheLifecycle {
    <#
    .SYNOPSIS
    Requires a dependency cache to save its resolved restore key without a late workspace hash.
    .PARAMETER Workflow
    Parsed product workflow; only restricted boolean expressions are evaluated.
    #>
    param($Workflow)
    $steps=@($Workflow['jobs']['linux']['steps'])
    $restore=@(0..($steps.Count-1)|Where-Object {$steps[$_]['uses'] -clike 'actions/cache/restore@*' -and $steps[$_]['with']['path'] -ceq '~/.nuget/packages'})
    $save=@(0..($steps.Count-1)|Where-Object {$steps[$_]['uses'] -clike 'actions/cache/save@*' -and $steps[$_]['with']['path'] -ceq '~/.nuget/packages'})
    if($restore.Count -ne 1 -or $save.Count -ne 1){throw 'NuGetCacheRestoreSaveRequired'}
    $restoreIndex=$restore[0];$saveIndex=$save[0]
    $restoreStep=$steps[$restoreIndex];$saveStep=$steps[$saveIndex];$id=[string]$restoreStep['id']
    if($id -cnotmatch '\A[A-Za-z_][A-Za-z0-9_-]*\z' -or $restoreStep['uses'] -cnotmatch '\Aactions/cache/restore@[a-f0-9]{40}\z' -or $saveStep['uses'] -cne ([string]$restoreStep['uses']).Replace('/restore@','/save@')){throw 'NuGetCacheIdentityChanged'}
    $build=@(0..($steps.Count-1)|Where-Object {[string]$steps[$_]['run'] -match 'Build-Workspace\.ps1'})
    $tests=@(0..($steps.Count-1)|Where-Object {[string]$steps[$_]['run'] -match 'Invoke-GitHubCi\.ps1'})
    if($build.Count -ne 1 -or $tests.Count -ne 1 -or $restoreIndex -ge $build[0] -or $build[0] -ge $tests[0] -or $tests[0] -ge $saveIndex -or $saveIndex -ne $steps.Count-1){throw 'NuGetCacheLifecycleOrderChanged'}
    $key=[string]$restoreStep['with']['key']
    foreach($input in @('runner.os','runner.arch','**/*.csproj','Directory.Packages.props','Directory.Build.props','global.json')){
        if(!$key.Contains($input)){throw 'NuGetCacheDependencyScopeChanged'}
    }
    if(!$key.Contains('hashFiles(')){throw 'NuGetCacheDependencyHashRequired'}
    $expected='${{ steps.'+$id+'.outputs.cache-primary-key }}'
    if([string]$saveStep['with']['key'] -cne $expected){throw 'NuGetCacheSaveMustReuseResolvedKey'}
    $condition=([string]$saveStep['if']).Trim()
    if($condition.StartsWith('${{') -and $condition.EndsWith('}}')){$condition=$condition.Substring(3,$condition.Length-5).Trim()}
    $hitExpression='steps.'+$id+'.outputs.cache-hit'
    $allowed='\A(?:(?:success\(\)|'+[regex]::Escape($hitExpression)+"|'true'|'false')|&&|\|\||==|!=|[!()]|\s)+\z"
    if($condition -cnotmatch $allowed){throw 'NuGetCacheSaveConditionInvalid'}
    $expression=$condition.Replace('success()','$successful').Replace($hitExpression,'$hit').Replace('&&',' -and ').Replace('||',' -or ').Replace('==',' -ceq ').Replace('!=',' -cne ').Replace('!',' -not ')
    try{$evaluate=[scriptblock]::Create($expression)}catch{throw 'NuGetCacheSaveConditionInvalid'}
    $properties=0
    foreach($successful in @($false,$true)){foreach($hit in @('true','false','','unknown')){
        if([bool](& $evaluate) -ne ($successful -and $hit -cne 'true')){throw 'NuGetCacheSaveDecisionChanged'}
        $properties++
    }}
    [pscustomobject]@{Properties=$properties;RestoreIndex=$restoreIndex;SaveIndex=$saveIndex}
}

function Test-QuietNuGetCacheLifecycle {
    <#
    .SYNOPSIS
    Checks immutable dependency-cache handoff, malformed policies and historical post-job regressions.
    .PARAMETER WorkspaceRoot
    Checkout providing the actual product workflow.
    .PARAMETER RunDirectory
    Owned contract evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $yaml=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $workflow=$yaml.Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/ci.yml'),[Text.Encoding]::UTF8))
    $baseline=Assert-QuietNuGetCacheLifecycle $workflow
    $serialized=$workflow|ConvertTo-Json -Depth 60 -Compress
    $restoreIndex=$baseline.RestoreIndex;$saveIndex=$baseline.SaveIndex
    $id=[string]$workflow['jobs']['linux']['steps'][$restoreIndex]['id']
    $conditions=@(
        "success() && steps.$id.outputs.cache-hit != 'true'",
        "steps.$id.outputs.cache-hit != 'true' && success()",
        "!(!success() || steps.$id.outputs.cache-hit == 'true')"
    )
    $properties=$baseline.Properties
    foreach($condition in $conditions){
        $candidate=$serialized|ConvertFrom-Json -AsHashtable
        $candidate.jobs.linux.steps[$saveIndex]['if']=$condition
        $properties+=(Assert-QuietNuGetCacheLifecycle $candidate).Properties
    }
    $damages=@('combined cache','late hash','matched key','wrong path','save before tests','save after failure','save exact hits','missing project input','floating action','unsafe condition','empty condition')
    foreach($damage in $damages){
        $candidate=$serialized|ConvertFrom-Json -AsHashtable
        $steps=$candidate.jobs.linux.steps
        switch($damage){
            'combined cache' {$steps[$restoreIndex].uses=([string]$steps[$restoreIndex].uses).Replace('/restore@','@');$candidate.jobs.linux.steps=@($steps[0..($saveIndex-1)])}
            'late hash' {$steps[$saveIndex]['with']['key']=$steps[$restoreIndex]['with']['key']}
            'matched key' {$steps[$saveIndex]['with']['key']='${{ steps.'+$id+'.outputs.cache-matched-key }}'}
            'wrong path' {$steps[$saveIndex]['with']['path']='~/.nuget/unrelated'}
            'save before tests' {$swap=$steps[$restoreIndex+1];$steps[$restoreIndex+1]=$steps[$saveIndex];$steps[$saveIndex]=$swap}
            'save after failure' {$steps[$saveIndex]['if']="steps.$id.outputs.cache-hit != 'true'"}
            'save exact hits' {$steps[$saveIndex]['if']='success()'}
            'missing project input' {$steps[$restoreIndex]['with']['key']=([string]$steps[$restoreIndex]['with']['key']).Replace('**/*.csproj','**/*.missing')}
            'floating action' {$steps[$restoreIndex].uses='actions/cache/restore@v4';$steps[$saveIndex].uses='actions/cache/save@v4'}
            'unsafe condition' {$steps[$saveIndex]['if']="success() && hashFiles('**/*') != ''"}
            'empty condition' {$steps[$saveIndex]['if']=''}
        }
        $rejected=$false;try{$null=Assert-QuietNuGetCacheLifecycle $candidate}catch{$rejected=$true}
        if(!$rejected){throw ('NuGetCacheWorkflowMutantSurvived: '+$damage)}
    }
    Write-WorkspaceJson (Join-Path $RunDirectory 'nuget-cache-lifecycle.json') @{DecisionProperties=$properties;WorkflowMutantsRejected=$damages.Count;LateHashEvaluationRequired=$false;HostedContainerPostJobExecuted=$false}
}
