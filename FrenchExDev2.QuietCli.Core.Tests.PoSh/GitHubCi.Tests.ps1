function Test-QuietContainerInputs {
    <#
    .SYNOPSIS
    Verifies offline staging of docs and restored packages, preview effects and hostile package paths.
    .PARAMETER WorkspaceRoot
    Source checkout providing the real staging function and inert module manifests.
    .PARAMETER RunDirectory
    Owned staging/property fixtures, never a real container or registry.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot scripts/ContainerInputs.ps1)
    $fixture=Join-Path $RunDirectory container-input-fixture
    foreach($name in @('FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh')){
        $directory=Join-Path $fixture $name;[void][IO.Directory]::CreateDirectory($directory)
        Copy-Item -LiteralPath (Join-Path $WorkspaceRoot ($name+'/'+$name+'.psd1')) -Destination $directory
    }
    foreach($relative in @('scripts/staged.ps1','build/lock.json','docs/agents/AGENTS.md','docs/scripts/Sync-ScriptsReadme.md','.github/actions/cache-resources/action.yml','CREDITS.md','README.md','Quietly.slnx','Directory.Build.props','.env','secret.json')){
        $path=Join-Path $fixture $relative;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[void][IO.File]::WriteAllTextAsync($path,'fixture-é漢',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    $cache=Join-Path $RunDirectory restored-packages
    [void][IO.Directory]::CreateDirectory((Join-Path $cache 'system.fixture/1.0.0'))
    [void][IO.File]::WriteAllTextAsync((Join-Path $cache system.fixture/1.0.0/content.txt),'restored-package',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $assetsPath=Join-Path $fixture FrenchExDev2.QuietCli.Core.PoSh/engine/obj/project.assets.json
    $assets=@{libraries=@{fixture=@{type='package';path='system.fixture/1.0.0'}};packageFolders=@{$cache=@{}}}
    Write-WorkspaceJson $assetsPath $assets
    $stage=Join-Path $RunDirectory container-input-stage
    $null=Copy-QuietContainerInputs -WorkspaceRoot $fixture -Destination $stage -WhatIf
    if(Test-Path -LiteralPath $stage){throw 'ContainerStagePreviewWroteFiles'}
    Copy-QuietContainerInputs -WorkspaceRoot $fixture -Destination $stage -Confirm:$false
    foreach($relative in @('docs/agents/AGENTS.md','docs/scripts/Sync-ScriptsReadme.md','.github/actions/cache-resources/action.yml','CREDITS.md','Quietly.slnx','Directory.Build.props','artifacts/nuget-cache/system.fixture/1.0.0/content.txt')){
        if(!(Test-Path -LiteralPath (Join-Path $stage $relative))){throw ('ContainerInputMissing: '+$relative)}
    }
    if((Test-Path (Join-Path $stage .env)) -or (Test-Path (Join-Path $stage secret.json)) -or (Test-Path (Join-Path $stage FrenchExDev2.QuietCli.Core.PoSh/engine/obj))){throw 'ContainerStageCopiedUndeclaredInputs'}
    [void][IO.File]::WriteAllTextAsync((Join-Path $fixture .env),"SECRET=never-forward-this`nQUIET_CONTAINER_RUNTIME=podman`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    foreach($selection in @('','docker')){
        $runtimeStage=Join-Path $RunDirectory ('runtime-stage-'+$(if($selection){$selection}else{'configured'}))
        Copy-QuietContainerInputs -WorkspaceRoot $fixture -Destination $runtimeStage -ContainerRuntime $selection -Confirm:$false
        $expected=if($selection){$selection}else{'podman'}
        $stagedText=[IO.File]::ReadAllText((Join-Path $runtimeStage .env),[Text.UTF8Encoding]::new($false,$true))
        if($stagedText -cne ('QUIET_CONTAINER_RUNTIME="'+$expected+'"'+"`n")){throw 'ContainerStageForwardedPrivateEnvironmentOrIgnoredOverride'}
    }
    $bad=@('../outside','x/../outside','/root/private','C:\private','x/1.0/extra',"x/1.0`n")
    foreach($relative in $bad){
        $assets.libraries.fixture.path=$relative;Write-WorkspaceJson $assetsPath $assets
        $rejected=$false;try{Copy-QuietContainerInputs -WorkspaceRoot $fixture -Destination (Join-Path $RunDirectory ('bad-stage-'+[guid]::NewGuid().ToString('N'))) -Confirm:$false}catch{$rejected=$_.Exception.Message -eq 'ContainerNuGetPackagePathInvalid'}
        if(!$rejected){throw 'ContainerNuGetPathEscapeAccepted'}
    }
    Write-WorkspaceJson (Join-Path $RunDirectory container-inputs.json) @{Preview='No writes';RestoredPackages=1;MalformedPaths=$bad.Count;SecretsCopied=$false;ContainerStarted=$false}
}
function Test-QuietCompanionHelperScope {
    <#
    .SYNOPSIS
    Imports the companion in a clean process without caller helpers and verifies its private dependencies.
    .PARAMETER WorkspaceRoot
    Selected checkout containing the source module and orchestration libraries.
    .PARAMETER RunDirectory
    Owned report directory for the isolated module probe.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    $script={
            param($root,$run)
            $ErrorActionPreference='Stop'
            $utf8=[Text.UTF8Encoding]::new($false)
            [Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
            $helpers=@('Invoke-CiProcess','Write-WorkspaceJson','ConvertTo-QuietByteCount','Get-QuietWorkspaceProjects')
            foreach($name in $helpers){if(Test-Path ('Function:'+ $name)){throw ('CallerHelperAlreadyPresent: '+$name)}}
            Import-Module (Join-Path $root 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
            $importWarnings=@()
            $module=Import-Module (Join-Path $root 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -PassThru -DisableNameChecking -WarningVariable importWarnings
            if($importWarnings.Count){throw 'CompanionImportEmittedWarnings'}
            $result=& $module {
                param($root,$run,$helpers)
                foreach($name in $helpers){
                    $command=Get-Command $name -ListImported -ErrorAction Stop
                    $expected=Join-Path $root ('scripts/'+$(if($name -eq 'Invoke-CiProcess'){'Ci.Process.ps1'}elseif($name -eq 'Get-QuietWorkspaceProjects'){'WorkspaceProjects.ps1'}else{'Common.ps1'}))
                    if([IO.Path]::GetFullPath($command.ScriptBlock.File) -cne [IO.Path]::GetFullPath($expected)){throw ('UnexpectedCompanionHelperSource: '+$name)}
                }
                if((ConvertTo-QuietByteCount '1 KiB') -ne 1024){throw 'CompanionByteCountHelperChanged'}
                $report=Join-Path $run 'isolated-companion/receipt.json'
                Write-WorkspaceJson $report @{Message='é漢';Helpers=$helpers}
                if((Get-Content $report -Raw -Encoding utf8|ConvertFrom-Json).Message -cne 'é漢'){throw 'CompanionJsonHelperChanged'}
                [pscustomobject]@{Helpers=$helpers.Count;Private=$true;ProfileRequired=$false}
            } $root $run $helpers
            foreach($name in $helpers){if(Test-Path ('Function:'+ $name)){throw ('CompanionHelperLeakedToCaller: '+$name)}}
            'QUIETCLI_HELPER_PROBE='+($result|ConvertTo-Json -Compress)
    }.ToString()
    $path=Join-Path $RunDirectory 'companion-helper-probe.ps1'
    [void][IO.File]::WriteAllTextAsync($path,$script,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $state=@{Receipt=$null;Diagnostics=[Collections.Generic.List[string]]::new()}
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    # Deliberate profile isolation detects caller/session dependencies hidden by workstation startup.
    $execution=Invoke-CiProcess -FilePath $runner -ArgumentList @('-NoProfile','-File',$path,$WorkspaceRoot,$RunDirectory) -TimeoutSeconds 45 -State $state -OnOutput {
        param($event,$state)
        $prefix='QUIETCLI_HELPER_PROBE='
        if($event.Text.StartsWith($prefix)){$state.Receipt=$event.Text.Substring($prefix.Length)|ConvertFrom-Json}
        elseif($state.Diagnostics.Count -lt 8){$state.Diagnostics.Add($event.Text)}
    }
    if($execution.Outcome -ne 'Success'){throw ('CompanionHelperScopeProbeFailed: '+($state.Diagnostics -join '; '))}
    if(!$state.Receipt -or $state.Receipt.Helpers -ne 4 -or !$state.Receipt.Private){throw 'CompanionHelperScopeReceiptChanged'}
}
function Test-QuietGitHubCiJsonReceipts {
    <#
    .SYNOPSIS
    Reproduces clean-checkout matrix output and checks atomic JSON publication on owned files.
    .PARAMETER WorkspaceRoot
    Source checkout providing the real writer, selector and matrix policy.
    .PARAMETER RunDirectory
    Owned fixture directory; no registry access or real container execution is performed.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    $fixture=Join-Path $RunDirectory 'github-json-receipts'
    $receipt=Join-Path $fixture 'clean/artifacts/github-matrix/selection.json'
    if(Test-Path -LiteralPath (Split-Path $receipt -Parent)){throw 'GitHubJsonRegressionRequiresAbsentParent'}
    Write-WorkspaceJson $receipt @{Message="é漢`nsecond line";Index=0}
    $saved=Get-Content -LiteralPath $receipt -Raw -Encoding utf8|ConvertFrom-Json
    if($saved.Message -cne "é漢`nsecond line" -or $saved.Index -ne 0){throw 'GitHubJsonCleanCheckoutReceiptChanged'}
    $seed=20261110;$random=[Random]::new($seed)
    foreach($index in 1..32){
        $path=Join-Path $fixture (('paths/{0}/nested-é漢/state.json' -f $random.Next()))
        foreach($revision in 1..2){
            $output=@(Write-WorkspaceJson $path @{Index=$index;Revision=$revision;Message='é漢'})
            $bytes=[IO.File]::ReadAllBytes($path)
            $value=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)|ConvertFrom-Json
            if($output.Count -or $value.Index -ne $index -or $value.Revision -ne $revision -or $value.Message -cne 'é漢' -or $bytes[0] -ne 123 -or $bytes -contains 13){throw 'WorkspaceJsonRoundTripPropertyFailed'}
        }
    }
    Push-Location $fixture
    try{Write-WorkspaceJson 'relative.json' @{Relative=$true}}finally{Pop-Location}
    if(!(Test-Path -LiteralPath (Join-Path $fixture relative.json))){throw 'WorkspaceJsonRelativePathChanged'}
    $blocked=Join-Path $fixture blocked
    [void][IO.File]::WriteAllTextAsync($blocked,'preserve',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $rejected=$false
    try{Write-WorkspaceJson (Join-Path $blocked 'nested/state.json') @{Invalid=$true}}catch{$rejected=$true}
    if(!$rejected -or [IO.File]::ReadAllText($blocked) -cne 'preserve'){throw 'WorkspaceJsonBlockedParentAccepted'}
    $writerSource=(Get-Command Write-WorkspaceJson).ScriptBlock.ToString()
    $anchor='[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))'
    if(!$writerSource.Contains($anchor)){throw 'WorkspaceJsonParentCreationMutationAnchorMissing'}
    $mutant=[scriptblock]::Create($writerSource.Replace($anchor,''))
    $killed=$false
    try{& $mutant (Join-Path $fixture 'mutant/absent/selection.json') @{Mutant=$true}}catch{$killed=$_.Exception.GetBaseException() -is [IO.DirectoryNotFoundException]}
    if(!$killed){throw 'WorkspaceJsonMissingParentMutantSurvived'}
    $scripts=Join-Path $fixture 'selector/scripts'
    [void][IO.Directory]::CreateDirectory($scripts)
    foreach($name in @('Select-GitHubCiMatrix.ps1','Common.ps1','EnvFile.ps1','Ci.Process.ps1','SourceIdentity.ps1','RuntimeTargets.ps1','ReportPaths.ps1','WorkspaceProjects.ps1','GitHubCi.ps1')){
        Copy-Item -LiteralPath (Join-Path $WorkspaceRoot "scripts/$name") -Destination $scripts
    }
    $adapter='function Get-QuietCiRegistryDigest { param($Plan,$Token,$Actor,[switch]$IncludeConfiguration); return $null }'
    [void][IO.File]::WriteAllTextAsync((Join-Path $scripts CiImages.ps1),$adapter,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $plan='param($WorkspaceRoot,$RuntimeIdentifier,$Module,[switch]$PlanOnly); [pscustomobject]@{Platform=$(if($RuntimeIdentifier.Contains("-musl-")){"alpine"}else{"debian"})}'
    foreach($name in @('New-CiImage.ps1','New-CiModuleImage.ps1')){[void][IO.File]::WriteAllTextAsync((Join-Path $scripts $name),$plan,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
    foreach($suite in @('Core','Git','All')){
        $checkout=Join-Path $fixture ('selector/'+$suite)
        $outputPath=Join-Path $fixture ($suite+'-output.txt')
        [void][IO.File]::WriteAllTextAsync($outputPath,"existing=value`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $before=(Get-FileHash -LiteralPath $outputPath).Hash
        $null=& (Join-Path $scripts Select-GitHubCiMatrix.ps1) -WorkspaceRoot $checkout -Suite $suite -OutputPath $outputPath -WhatIf
        if((Test-Path -LiteralPath $checkout) -or (Get-FileHash -LiteralPath $outputPath).Hash -cne $before){throw 'GitHubMatrixPreviewCreatedOutput'}
        $null=& (Join-Path $scripts Select-GitHubCiMatrix.ps1) -WorkspaceRoot $checkout -Suite $suite -OutputPath $outputPath -Confirm:$false
        $selection=Get-Content -LiteralPath (Join-Path $checkout 'artifacts/github-matrix/selection.json') -Raw -Encoding utf8|ConvertFrom-Json
        $outputs=Get-Content -LiteralPath $outputPath -Encoding utf8
        if($selection.HasContainer -or !$selection.HasFallback -or @($selection.Fallback.include).Count -ne 4 -or $outputs[0] -cne 'existing=value' -or $outputs -cnotcontains 'has_docker_container_runtime=true' -or $outputs -cnotcontains 'has_container=false'){throw 'GitHubMatrixCleanCheckoutOutputsChanged'}
    }
    if(@(Get-ChildItem -LiteralPath $fixture -Filter '*.tmp' -File -Recurse).Count){throw 'WorkspaceJsonTemporaryFilesLeaked'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'github-json-receipts.json') @{Seed=$seed;RoundTrips=64;SelectorSuites=@('Core','Git','All');PreviewCases=3;BlockedParentRejected=$true;MutantsKilled=1;RealRegistry=$false;RealHostedRunner=$false}
}
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
    foreach($name in @('Invoke-GitHubCi.ps1','Common.ps1','EnvFile.ps1','Ci.Process.ps1','SourceIdentity.ps1','RuntimeTargets.ps1','ReportPaths.ps1','WorkspaceProjects.ps1')){Copy-Item -LiteralPath (Join-Path $WorkspaceRoot "scripts/$name") -Destination $scripts}
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
    foreach($name in $jobs.Keys){
        $steps=@($jobs[$name]['steps'])
        for($index=0;$index -lt $steps.Count;$index++){
            if([string]$steps[$index]['uses'] -notlike 'actions/checkout@*'){continue}
            if($index+1 -ge $steps.Count -or [string]$steps[$index+1]['run'] -notmatch '\./scripts/Initialize-CiEnvironment\.ps1 -Target GitHub -ContainerRuntime docker' -or $steps[$index+1]['shell'] -cne 'pwsh'){throw ('GitHubEnvironmentInitializationMissing: '+$name)}
        }
    }
    foreach($entry in @(@{Job='linux';Flag='has_container'},@{Job='linux-test-driver';Flag='has_docker_container_runtime'})){
        $condition=[string]$jobs[$entry.Job]['if']
        if(!$condition.Contains('!cancelled()') -or !$condition.Contains("needs.linux-selection.result == 'success'") -or !$condition.Contains(("needs.linux-selection.outputs."+$entry.Flag+" == 'true'"))){throw ('GitHubCiSelectedJobInheritedSkip: '+$entry.Job)}
    }
    foreach($name in $jobs.Keys){foreach($dependency in @($jobs[$name]['needs'])){if($dependency -and !$jobs.ContainsKey($dependency)){throw 'GitHubWorkflowDanglingDependency'}}}
    if(!$jobs['linux']['container'] -or $jobs['windows']['container'] -or $jobs['linux-test-driver']['container']){throw 'GitHubWorkflowExecutionEnvironmentChanged'}
    $direct=@($jobs['linux']['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
    if(!$direct.Contains('Invoke-GitHubCi.ps1') -or $direct -match 'Invoke-ContainerCi|New-CiImage|podman'){throw 'GitHubContainerNestedRuntimeDetected'}
    $fallback=@($jobs['linux-test-driver']['steps']|ForEach-Object {[string]$_['run']}) -join "`n"
    if(!$fallback.Contains('-ContainerRuntime docker') -or $fallback.Contains('-PublishCache')){throw 'GitHubFallbackPublicationOrRuntimeChanged'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'github-ci-campaign.json') @{Seed=$seed;PartitionProperties=$properties;MalformedCases=$badInputs.Count;GateCases=$gateCases;MutantsKilled=2;DirectWorkerSameProcess=$true;Workflow=$workflowPath;RealHostedRunner=$false}
}
