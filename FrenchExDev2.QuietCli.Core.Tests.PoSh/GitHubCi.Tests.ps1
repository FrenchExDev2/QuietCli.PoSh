function Test-QuietGitHubCi {
    <#
    .SYNOPSIS
    Checks matrix partition properties, malformed identities, fail-closed gates and direct GitHub entry.
    .PARAMETER WorkspaceRoot
    Source checkout providing the shared execution policy.
    .PARAMETER RunDirectory
    Owned fixture and property campaign directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    . (Join-Path $WorkspaceRoot 'scripts/GitHubCi.ps1')
    . (Join-Path $PSScriptRoot 'GitHubImageAdapters.Tests.ps1')
    Test-QuietGitHubImageAdapters -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    $seed=20261110;$random=[Random]::new($seed);$properties=0;$gateCases=0
    $rids=@('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')
    for($mask=0;$mask -lt 16;$mask++){
        $rows=@(for($index=0;$index -lt 4;$index++){
            $rid=$rids[$index];$platform=if($rid.Contains('-musl-')){'alpine'}else{'debian'}
            [pscustomobject]@{Rid=$rid;Platform=$platform;Runner=$(if($rid.EndsWith('arm64')){'ubuntu-24.04-arm'}else{'ubuntu-latest'});Reference=$(if($mask -band (1 -shl $index)){'ghcr.io/frenchexdev2/quietcli2-ci-fixture@sha256:'+('a'*64)}else{$null})}
        })
        foreach($iteration in 1..16){
            $permuted=@($rows|Sort-Object {$random.Next()})
            $matrix=Get-GitHubCiExecutionMatrix $permuted
            $native=@($matrix.Container.include);$fallback=@($matrix.Fallback.include)
            $all=@($native)+@($fallback)
            if($all.Count -ne 4 -or @($all|Group-Object rid|Where-Object Count -NE 1).Count -or @($all|Where-Object rid -NotIn $rids).Count){throw 'GitHubCiTargetPartitionChanged'}
            foreach($row in $rows){
                $expectedNative=[bool]$row.Reference -and $row.Rid -cne 'linux-musl-arm64'
                if(@($native|Where-Object rid -CEQ $row.Rid).Count -ne [int]$expectedNative){throw 'GitHubCiContainerPolicyChanged'}
            }
            if($matrix.HasContainer -ne [bool]$native.Count -or $matrix.HasFallback -ne [bool]$fallback.Count){throw 'GitHubCiSelectionFlagsChanged'}
            $properties++
        }
    }
    $base=@($rows|ForEach-Object {$_.PSObject.Copy()})
    $badInputs=@(@{Kind='missing';Rows=@($base[0..2])},@{Kind='duplicate';Rows=@($base[0],$base[0],$base[2],$base[3])})
    foreach($value in @('latest','ghcr.io/frenchexdev2/quietcli2-ci-fixture:tag','ghcr.io/other/image@sha256:'+('a'*64),"bad`nimage")){
        $copy=@($base|ForEach-Object {$_.PSObject.Copy()});$copy[0].Reference=$value;$badInputs+=@{Kind='identity';Rows=$copy}
    }
    $copy=@($base|ForEach-Object {$_.PSObject.Copy()});$copy[1].Runner='ubuntu-latest';$badInputs+=@{Kind='runner';Rows=$copy}
    foreach($bad in $badInputs){$rejected=$false;try{$null=Get-GitHubCiExecutionMatrix $bad.Rows}catch{$rejected=$true};if(!$rejected){throw 'GitHubCiMalformedMatrixAccepted'}}
    foreach($hasNative in @($false,$true)){
        foreach($selection in @('success','failure','cancelled','skipped')){foreach($native in @('success','failure','cancelled','skipped')){foreach($fallback in @('success','failure','cancelled','skipped')){
            $expected=$selection -ceq 'success' -and $fallback -ceq 'success' -and $native -ceq $(if($hasNative){'success'}else{'skipped'})
            $accepted=$true;try{Assert-GitHubCiLinuxResults $selection $native $fallback $hasNative $true}catch{$accepted=$false}
            if($accepted -ne $expected){throw 'GitHubCiAggregateGateChanged'};$gateCases++
        }}}
    }
    $source=(Get-Command Get-GitHubCiExecutionMatrix).ScriptBlock.ToString()
    $mutant=[scriptblock]::Create($source.Replace("`$rid -cne 'linux-musl-arm64'",'$true'))
    $observed=& $mutant -Images $base
    if(@($observed.Container.include|Where-Object rid -EQ linux-musl-arm64).Count -ne 1){throw 'GitHubCiInvalidAlpineMutant'}
    $gateSource=(Get-Command Assert-GitHubCiLinuxResults).ScriptBlock.ToString()
    $gateMutant=[scriptblock]::Create($gateSource.Replace("`$SelectionResult -cne 'success'",'$false'))
    $detected=$false;try{& $gateMutant failure success success $true $true}catch{$detected=$true}
    if($detected){throw 'GitHubCiInvalidGateMutant'}
    $fixture=Join-Path $RunDirectory 'github-entry-fixture';$scripts=Join-Path $fixture 'scripts'
    [void][IO.Directory]::CreateDirectory($scripts)
    foreach($project in Get-ChildItem -LiteralPath $WorkspaceRoot -Directory -Filter 'FrenchExDev2.QuietCli.*.PoSh'){
        $manifest=Join-Path $project.FullName ($project.Name+'.psd1')
        if(Test-Path -LiteralPath $manifest){
            $target=Join-Path $fixture $project.Name;[void][IO.Directory]::CreateDirectory($target)
            Copy-Item -LiteralPath $manifest -Destination $target
        }
    }
    foreach($name in @('Invoke-GitHubCi.ps1','Common.ps1','Ci.Process.ps1','SourceIdentity.ps1','RuntimeTargets.ps1','ReportPaths.ps1','WorkspaceProjects.ps1')){Copy-Item -LiteralPath (Join-Path $WorkspaceRoot "scripts/$name") -Destination $scripts}
    $worker='param($WorkspaceRoot,$RunDirectory,$Suite,$ExpectedRuntimeIdentifier,[switch]$SkipTty); . (Join-Path $PSScriptRoot Common.ps1); Write-WorkspaceJson (Join-Path $RunDirectory summary.json) @{State=@{State="Success";Passed=3;Failed=0};WorkerPid=$PID;Suite=$Suite;SkipTty=[bool]$SkipTty}'
    [void][IO.File]::WriteAllTextAsync((Join-Path $scripts 'Invoke-TestWorker.ps1'),$worker,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $previous=$env:GITHUB_ACTIONS
    try{
        $env:GITHUB_ACTIONS='false';$rejected=$false
        try{$null=& (Join-Path $scripts 'Invoke-GitHubCi.ps1') -WorkspaceRoot $fixture -Suite Import -SkipBuild}catch{$rejected=$true}
        if(!$rejected -or (Test-Path (Join-Path $fixture artifacts))){throw 'GitHubEntryRanOutsideGitHubContext'}
        $env:GITHUB_ACTIONS='true';$run=Join-Path $fixture 'artifacts/tests/direct'
        $result=& (Join-Path $scripts 'Invoke-GitHubCi.ps1') -WorkspaceRoot $fixture -Suite Import -SkipBuild -SkipTty -RunDirectory $run
        $receipt=Get-Content -LiteralPath (Join-Path $run summary.json) -Raw -Encoding utf8|ConvertFrom-Json
        if($result.State -cne 'Success' -or $receipt.WorkerPid -ne $PID -or !$receipt.SkipTty){throw 'GitHubEntryDidNotExecuteDirectWorker'}
    }finally{$env:GITHUB_ACTIONS=$previous}
    $workflowPath=if($env:QUIETCLI_CI_CANDIDATE){$env:QUIETCLI_CI_CANDIDATE}else{Join-Path $WorkspaceRoot '.github/workflows/ci.yml'}
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $parser=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build();$reader=[IO.StringReader]::new([IO.File]::ReadAllText($workflowPath,[Text.Encoding]::UTF8))
    try{$workflow=$parser.Deserialize($reader,[object])}finally{$reader.Dispose()}
    $jobs=$workflow['jobs']
    foreach($name in $jobs.Keys){foreach($dependency in @($jobs[$name]['needs'])){if($dependency -and !$jobs.ContainsKey($dependency)){throw 'GitHubWorkflowDanglingDependency'}}}
    if(!$jobs['linux']['container'] -or $jobs['windows']['container'] -or $jobs['linux-fallback']['container']){throw 'GitHubWorkflowExecutionEnvironmentChanged'}
    $direct=@($jobs['linux']['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
    if(!$direct.Contains('Invoke-GitHubCi.ps1') -or $direct -match 'Invoke-ContainerCi|New-CiImage|podman'){throw 'GitHubContainerNestedRuntimeDetected'}
    $fallback=@($jobs['linux-fallback']['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
    if(!$fallback.Contains('-ContainerRuntime docker') -or $fallback.Contains('-PublishCache')){throw 'GitHubFallbackPublicationOrRuntimeChanged'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'github-ci-campaign.json') @{Seed=$seed;PartitionProperties=$properties;MalformedCases=$badInputs.Count;GateCases=$gateCases;MutantsKilled=2;DirectWorkerSameProcess=$true;Workflow=$workflowPath;RealHostedRunner=$false}
}
