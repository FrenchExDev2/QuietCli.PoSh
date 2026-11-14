function Test-QuietAutomationContracts {
    <#
    .SYNOPSIS
    Independently checks runtime discovery, workflow documentation and the new-script preview policy.
    .PARAMETER WorkspaceRoot
    Real repository containing the production check scripts.
    .PARAMETER RunDirectory
    Owned fixtures, seeds and campaign evidence.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/Common.psm1) -DisableNameChecking -ErrorAction Stop
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/ScriptShouldProcess.psm1) -DisableNameChecking -ErrorAction Stop
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/WorkflowDocumentation.psm1) -DisableNameChecking -ErrorAction Stop
    $resolverSource=(Get-Command Resolve-QuietVirtEngine).ScriptBlock.ToString()
    $engineAvailability=@{}
    function Get-Command {
        <#
        .SYNOPSIS
        Simulates application discovery for the scoped container-runtime availability matrix.
        .PARAMETER Name
        Application name whose fixture availability is queried.
        .PARAMETER CommandType
        Requested command kind, retained to match the production resolver call.
        .PARAMETER ErrorAction
        Requested missing-command policy, retained without invoking real discovery.
        #>
        param($Name,$CommandType,$ErrorAction)
        if($engineAvailability.ContainsKey($Name) -and $engineAvailability[$Name]){[pscustomobject]@{Name=$Name;CommandType='Application'}}
    }
    $runtimeCases=0
    $runtimeFixture=Join-Path $RunDirectory 'runtime-discovery'
    $platformResolver=[scriptblock]::Create($resolverSource)
    if($resolverSource.Contains('$IsWindows') -or $resolverSource.Contains('$IsLinux')){throw 'ContainerRuntimePreferenceMustBePlatformIndependent'}
    foreach($docker in @($false,$true)){foreach($podman in @($false,$true)){
        $engineAvailability=@{docker=$docker;podman=$podman}
        foreach($explicit in @('','docker','podman')){foreach($requireAvailable in @($false,$true)){
            $expected=if($explicit){$explicit}elseif($podman){'podman'}elseif($docker){'docker'}else{$null}
            $mustReject=(!$expected) -or ($explicit -and $requireAvailable -and !$engineAvailability[$explicit])
            $actual=$null;$rejected=$false
            try{$actual=& $platformResolver -ContainerRuntime $explicit -Available:$requireAvailable -WorkspaceRoot $runtimeFixture}catch{$rejected=$true}
            if($rejected -ne [bool]$mustReject -or (!$rejected -and $actual -cne $expected)){throw 'ContainerRuntimeDiscoveryPropertyFailed'}
            $runtimeCases++
        }}
    }}
    $engineAvailability=@{docker=$true;podman=$true}
    $preferred='podman'
    if((& $platformResolver -Available -WorkspaceRoot $runtimeFixture) -cne $preferred){throw 'ActualHostContainerPreferenceChanged'}
    if(!$resolverSource.Contains("@('podman','docker')")){throw 'ContainerRuntimePreferenceMutationAnchorMissing'}
    $mutant=[scriptblock]::Create($resolverSource.Replace("@('podman','docker')","@('docker','podman')"))
    if((& $mutant -Available -WorkspaceRoot $runtimeFixture) -ceq $preferred){throw 'ContainerRuntimePreferenceMutantSurvived'}
    foreach($configured in @('podman','docker')){
        $null=Set-QuietEnvValue -Path (Join-Path $runtimeFixture '.env') -Key QUIET_CONTAINER_RUNTIME -Value $configured -Confirm:$false
            if((& $platformResolver -Available -WorkspaceRoot $runtimeFixture) -cne $configured){throw 'ContainerRuntimeIgnoredEnvConfiguration'}
            $override=if($configured -eq 'podman'){'docker'}else{'podman'}
            if((& $platformResolver -Available -WorkspaceRoot $runtimeFixture -ContainerRuntime $override) -cne $override){throw 'ContainerRuntimeIgnoredExplicitOverride'}
    }
    foreach($invalid in @('invalid','','Docker')){
        $null=Set-QuietEnvValue -Path (Join-Path $runtimeFixture '.env') -Key QUIET_CONTAINER_RUNTIME -Value $invalid -Confirm:$false
        $rejected=$false;try{$null=& $platformResolver -WorkspaceRoot $runtimeFixture}catch{$rejected=$_.Exception.Message -like 'QuietVirtEngineConfigurationInvalid:*'}
        if(!$rejected){throw 'ContainerRuntimeInvalidConfigurationFellBackSilently'}
        if((& $platformResolver -WorkspaceRoot $runtimeFixture -ContainerRuntime docker -Available) -cne 'docker'){throw 'ExplicitRuntimeDidNotOverrideInvalidEnv'}
    }
    $null=Set-QuietEnvValue -Path (Join-Path $runtimeFixture '.env') -Key QUIET_CONTAINER_RUNTIME -Value podman -Confirm:$false
    $engineAvailability=@{docker=$true;podman=$false}
    $rejected=$false;try{$null=& $platformResolver -WorkspaceRoot $runtimeFixture -Available}catch{$rejected=$_.Exception.Message -eq 'QuietVirtEngineUnavailable: podman'}
    if(!$rejected -or (& $platformResolver -WorkspaceRoot $runtimeFixture) -cne 'podman'){throw 'ConfiguredUnavailableRuntimeFellBackSilently'}
    [void][IO.File]::WriteAllTextAsync((Join-Path $runtimeFixture '.env'),"QUIET_CONTAINER_RUNTIME=podman`nQUIET_CONTAINER_RUNTIME=docker`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $rejected=$false;try{$null=Resolve-QuietVirtEngine -WorkspaceRoot $runtimeFixture}catch{$rejected=$_.Exception.Message -like 'EnvKeyDuplicate:*'}
    if(!$rejected){throw 'DuplicateRuntimeConfigurationAccepted'}
    Remove-Item Function:Get-Command
    $fixture=Join-Path $RunDirectory automation-contracts
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture build))
    $policy=@{SchemaVersion=1;LegacyPaths=@();ReadOnlyExceptions=@()}
    Write-WorkspaceJson (Join-Path $fixture build/script-shouldprocess.json) $policy
    $target=Join-Path $fixture target.ps1
    $artifact=Join-Path $fixture forbidden.txt
    $random=[Random]::new(20261110)
    foreach($index in 0..127){
        $value=$random.Next()
        $text='[CmdletBinding(SupportsShouldProcess)] param([string]$Path); if(!$PSCmdlet.ShouldProcess($Path,''Write owned fixture'')){return}; [IO.File]::WriteAllText($Path,'''+$value+''')'
        [void][IO.File]::WriteAllTextAsync($target,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        if((Get-QuietScriptShouldProcess $target) -cne 'ShouldProcess'){throw 'ScriptShouldProcessPropertyFailed'}
        if($index -lt 8){
            $null=& $target -Path $artifact -WhatIf
            if(Test-Path $artifact){throw 'WhatIfWroteFixture'}
        }
    }
    $null=& $target -Path $artifact -Confirm:$false
    if(!(Test-Path $artifact)){throw 'ConfirmedFixtureDidNotWrite'}
    $bad=@('[CmdletBinding(SupportsShouldProcess)] param(); Set-Content x y','[CmdletBinding(SupportsShouldProcess=$false)] param(); if($PSCmdlet.ShouldProcess(''x'',''y'')){}','param([switch]$WhatIf); Set-Content x y','[CmdletBinding()] param(); Set-Content x y')
    foreach($text in $bad){
        [void][IO.File]::WriteAllTextAsync($target,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $rejected=$false;try{$null=Test-QuietScriptShouldProcessPolicy $fixture}catch{$rejected=$true}
        if(!$rejected){throw 'ScriptShouldProcessMalformedContractAccepted'}
    }
    $source=(Get-Command Get-QuietScriptShouldProcess).ScriptBlock.ToString()
    $mutant=[scriptblock]::Create($source.Replace('$supported -and $guard','$supported'))
    [void][IO.File]::WriteAllTextAsync($target,$bad[0],[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    if((& $mutant $target) -cne 'ShouldProcess'){throw 'ScriptSafetyMutantInvalid'}
    $policy.ReadOnlyExceptions=@(@{Path='target.ps1';SHA256=('0'*64);Reason='Read-only fixture exception with intentionally wrong source identity.'})
    Write-WorkspaceJson (Join-Path $fixture build/script-shouldprocess.json) $policy
    $rejected=$false;try{$null=Test-QuietScriptShouldProcessPolicy $fixture}catch{$rejected=$_.Exception.Message -like 'ScriptShouldProcessExceptionStale*'}
    if(!$rejected){throw 'ScriptSafetyStaleExceptionAccepted'}
    $policy.ReadOnlyExceptions=@()
    Write-WorkspaceJson (Join-Path $fixture build/script-shouldprocess.json) $policy
    [void][IO.File]::WriteAllTextAsync($target,'function Get-ReadOnlyFixture { 1 }',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $authoredLib=Join-Path $fixture scripts/lib;[void][IO.Directory]::CreateDirectory($authoredLib)
    $unsafeLibrary=Join-Path $authoredLib Unsafe.psm1
    [void][IO.File]::WriteAllTextAsync($unsafeLibrary,'Set-Content forbidden unsafe',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $rejected=$false;try{$null=Test-QuietScriptShouldProcessPolicy $fixture}catch{$rejected=$_.Exception.Message -like 'ScriptShouldProcessRequired: scripts/lib/Unsafe.psm1*'}
    if(!$rejected){throw 'AuthoredScriptLibEscapedPreviewPolicy'}
    $workflows=Join-Path $fixture .github/workflows
    $docs=Join-Path $fixture docs/ci/github
    [void][IO.Directory]::CreateDirectory($workflows);[void][IO.Directory]::CreateDirectory($docs)
    $yaml="name: Fixture`non:`n  workflow_dispatch:`njobs:`n  build:`n    runs-on: ubuntu-latest`n  verify:`n    needs: build`n    runs-on: ubuntu-latest`n    steps:`n      - run: Import-Module ./scripts/lib/Runner.psm1`n"
    $workflow=Join-Path $workflows fixture.yml
    [void][IO.File]::WriteAllTextAsync($workflow,$yaml,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $hash=(Get-FileHash $workflow).Hash
    $document=Join-Path $docs script-fixture.md
    $text=@(('# Fixture'),'',('<!-- workflow-source-sha256: '+$hash+' -->'),'','## Purpose','','Owned validation fixture.','','## Triggers','','Manual only.','','<!-- workflow-generated:begin -->','<!-- workflow-generated:end -->','','## Scripts and effects','','No business execution.','','## Validation and limits','','Fixture only.','') -join "`n"
    [void][IO.File]::WriteAllTextAsync($document,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $sync=Join-Path $WorkspaceRoot scripts/Sync-GitHubWorkflowsReadme.ps1
    $null=& $sync -WorkspaceRoot $fixture -Apply -WhatIf
    if(Test-Path (Join-Path $docs README.md)){throw 'WorkflowDocsWhatIfWroteIndex'}
    $null=& $sync -WorkspaceRoot $fixture -Apply -Confirm:$false
    $original=Get-Content $document -Raw -Encoding utf8
    if(!$original.Contains('job_build --> job_verify')){throw 'WorkflowDiagramDoesNotMatchNeeds'}
    if(!$original.Contains('./scripts/lib/Runner.psm1')){throw 'WorkflowModuleEntrypointTruncated'}
    $null=& (Join-Path $WorkspaceRoot scripts/Invoke-WorkspaceChecks.ps1) -WorkspaceRoot $fixture -Check GitHubWorkflowDocs
    foreach($variant in @('graph','receipt','section','index','source')){
        $indexPath=Join-Path $docs README.md;$indexText=Get-Content $indexPath -Raw -Encoding utf8
        $changed=switch($variant){
            graph {$original.Replace('job_build --> job_verify','job_verify --> job_build')}
            receipt {$original.Replace($hash,('F'*64))}
            section {$original.Replace('## Triggers','## Missing')}
            index {$original}
            source {$original}
        }
        [void][IO.File]::WriteAllTextAsync($document,$changed,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        if($variant -eq 'index'){[void][IO.File]::WriteAllTextAsync($indexPath,'stale',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
        if($variant -eq 'source'){[void][IO.File]::WriteAllTextAsync($workflow,($yaml+"# Changed workflow`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
        $rejected=$false;try{$null=& $sync -WorkspaceRoot $fixture}catch{$rejected=$true}
        if(!$rejected){throw ('WorkflowDocumentationDriftAccepted: '+$variant)}
        [void][IO.File]::WriteAllTextAsync($indexPath,$indexText,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        [void][IO.File]::WriteAllTextAsync($workflow,$yaml,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    [void][IO.File]::WriteAllTextAsync($document,$original,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $skipped=@(& (Join-Path $WorkspaceRoot scripts/Invoke-WorkspaceChecks.ps1) -WorkspaceRoot $fixture -Check ScriptShouldProcess -SkipCheck ScriptShouldProcess)
    if($skipped.Count -ne 1 -or $skipped[0].State -cne 'Skipped'){throw 'WorkspacePipelineSkipReportedAsSuccess'}
    $rejected=$false;try{$null=& (Join-Path $WorkspaceRoot scripts/Invoke-WorkspaceChecks.ps1) -WorkspaceRoot $fixture -Check unknown}catch{$rejected=$true}
    if(!$rejected){throw 'WorkspacePipelineUnknownCheckAccepted'}
    $isolatedScripts=Join-Path $fixture tooling/scripts
    [void][IO.Directory]::CreateDirectory($isolatedScripts)
    $isolatedLibrary=[IO.Path]::Combine($isolatedScripts,'lib')
    [void][IO.Directory]::CreateDirectory($isolatedLibrary)
    foreach($helper in @('WorkflowDocumentation','Resources')){Copy-Item -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib',($helper+'.psm1'))) -Destination $isolatedLibrary}
    $isolatedResources=Join-Path $fixture tooling/FrenchExDev2.QuietCli.Core.PoSh/resources
    [void][IO.Directory]::CreateDirectory((Join-Path $isolatedResources yaml))
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json) -Destination $isolatedResources
    foreach($variant in @('missing','tampered')){
        if($variant -eq 'tampered'){[IO.File]::WriteAllBytes((Join-Path $isolatedResources yaml/YamlDotNet.dll),[byte[]]@(1,2,3))}
        $rejected=$false
        try{$null=& {param($helper,$root) Import-Module $helper -DisableNameChecking -ErrorAction Stop; Get-QuietWorkflowDocumentation $root -WhatIf} ([IO.Path]::Combine($isolatedLibrary,'WorkflowDocumentation.psm1')) $fixture}catch{$rejected=$_.Exception.Message -like 'WorkflowYamlResource*'}
        if(!$rejected){throw 'WorkflowParserResourceFailureAccepted'}
        if(Test-Path (Join-Path $fixture tooling/.cache)){throw 'WorkflowParserPreviewPreparedResources'}
    }
    $yamlCorpus=@('jobs: [broken','jobs: plain','name: no-jobs','jobs: {build: {needs: missing, runs-on: ubuntu-latest}}','jobs: {a-b: {runs-on: ubuntu-latest}, a_b: {runs-on: ubuntu-latest}}')
    foreach($round in 0..7){foreach($badYaml in $yamlCorpus){
        [void][IO.File]::WriteAllTextAsync($workflow,("# Seed 20261110 round "+$round+"`n"+$badYaml+"`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $rejected=$false;try{$null=Get-QuietWorkflowDocumentation $fixture}catch{$rejected=$true}
        if(!$rejected){throw 'WorkflowMalformedCorpusAccepted'}
    }}
    [void][IO.File]::WriteAllTextAsync($workflow,$yaml,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $previewRoot=Join-Path $RunDirectory 'preview-must-not-exist'
    $null=& (Join-Path $WorkspaceRoot scripts/Export-CiFailureDiagnostics.ps1) -WorkspaceRoot $fixture -OutputDirectory $previewRoot -WhatIf
    $null=& (Join-Path $WorkspaceRoot scripts/Select-GitHubCiMatrix.ps1) -WorkspaceRoot $WorkspaceRoot -OutputPath $previewRoot -WhatIf
    $previous=$env:GITHUB_ACTIONS
    try{
        $env:GITHUB_ACTIONS='true'
        $null=& (Join-Path $WorkspaceRoot scripts/Invoke-GitHubCi.ps1) -WorkspaceRoot $WorkspaceRoot -Suite Import -RunDirectory $previewRoot -WhatIf
        $null=& (Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-GitHubCiSmoke.ps1) -WorkspaceRoot $WorkspaceRoot -Image fixture -RunDirectory $previewRoot -WhatIf
    }finally{$env:GITHUB_ACTIONS=$previous}
    if(Test-Path $previewRoot){throw 'AutomationEntryPointWhatIfProducedEffects'}
    $resourceFixture=Join-Path $fixture resource-preview
    [void][IO.Directory]::CreateDirectory((Join-Path $resourceFixture FrenchExDev2.QuietCli.Core.PoSh/resources))
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json) -Destination (Join-Path $resourceFixture FrenchExDev2.QuietCli.Core.PoSh/resources)
    $null=& (Join-Path $WorkspaceRoot scripts/Restore-CoreResources.ps1) -WorkspaceRoot $resourceFixture -IncludePackage YamlDotNet -WhatIf
    if(Test-Path (Join-Path $resourceFixture .cache)){throw 'ResourceRestoreWhatIfWroteCache'}
    $rejected=$false;try{$null=& (Join-Path $WorkspaceRoot scripts/Restore-CoreResources.ps1) -WorkspaceRoot $resourceFixture -IncludePackage unknown}catch{$rejected=$_.Exception.Message -like 'ResourcePackageUnknown*'}
    if(!$rejected -or (Test-Path (Join-Path $resourceFixture .cache))){throw 'ResourceRestoreInvalidSelectionProducedEffects'}
    $payload=[byte[]]@(11,23,47)
    $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payload))
    $fakeLock=@{Packages=@(@{Id='yamldotnet';Version='1.0.0';Source='https://example.invalid/not-called'},@{Id='unselected';Version='1.0.0';Source=$null});Files=@(@{Package='yamldotnet';Path='resources/yaml/YamlDotNet.dll';SHA256=$digest;Bytes=3},@{Package='unselected';Path='resources/forbidden.dll';SHA256=('0'*64);Bytes=1})}
    Write-WorkspaceJson (Join-Path $resourceFixture FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json) $fakeLock
    $cache=Join-Path $resourceFixture .cache/nuget-resources;[void][IO.Directory]::CreateDirectory($cache)
    $zip=[IO.Compression.ZipFile]::Open((Join-Path $cache yamldotnet.1.0.0.nupkg),[IO.Compression.ZipArchiveMode]::Create)
    try{$entry=$zip.CreateEntry('lib/YamlDotNet.dll');$stream=$entry.Open();try{[void]$stream.WriteAsync($payload).GetAwaiter().GetResult()}finally{$stream.Dispose()}}finally{$zip.Dispose()}
    $restored=& (Join-Path $WorkspaceRoot scripts/Restore-CoreResources.ps1) -WorkspaceRoot $resourceFixture -IncludePackage YAMLDOTNET -Confirm:$false
    if($restored.Restored -ne 1 -or $restored.Total -ne 1 -or (Get-FileHash (Join-Path $resourceFixture FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll)).Hash -cne $digest -or (Test-Path (Join-Path $resourceFixture FrenchExDev2.QuietCli.Core.PoSh/resources/forbidden.dll))){throw 'SelectiveResourceRestoreContractFailed'}
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/Resources.psm1) -DisableNameChecking -ErrorAction Stop
    $ensured=Ensure-QuietResource -WorkspaceRoot $resourceFixture -RelativePath resources/yaml/YamlDotNet.dll
    if($ensured.State -cne 'Ready' -or $ensured.Restored){throw 'VerifiedResourceNotReused'}
    [IO.File]::WriteAllBytes($ensured.Path,[byte[]]@(0))
    $planned=Ensure-QuietResource -WorkspaceRoot $resourceFixture -RelativePath resources/yaml/YamlDotNet.dll -WhatIf
    if($planned.State -cne 'Planned' -or (Get-FileHash $ensured.Path).Hash -ceq $digest){throw 'EnsureResourcePreviewWroteBytes'}
    $ensured=Ensure-QuietResource -WorkspaceRoot $resourceFixture -RelativePath resources/yaml/YamlDotNet.dll -Confirm:$false
    if(!$ensured.Restored -or (Get-FileHash $ensured.Path).Hash -cne $digest){throw 'EnsureResourceFailedOfflineRepair'}
    Write-WorkspaceJson (Join-Path $RunDirectory automation-contracts-campaign.json) @{Seed=20261110;RuntimeProperties=$runtimeCases;ShouldProcessProperties=128;WhatIfExecutions=14;MalformedContracts=$bad.Count;AuthoredLibBoundaryChecked=$true;DocumentationDriftCases=5;ParserResourceFailures=2;YamlFuzzCases=40;OfflineSelectiveRestore=$true;MutantsKilled=2}
}
function Test-QuietAutomationCommitChecks {
    <#
    .SYNOPSIS
    Proves new workflow/preview gates inspect the staged bytes and preserve HEAD/index during WhatIf.
    .PARAMETER WorkspaceRoot
    Real scripts and shared disposable repository factory.
    .PARAMETER RunDirectory
    Owned fixture directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/Common.psm1) -DisableNameChecking -ErrorAction Stop
    $scripts=Join-Path $WorkspaceRoot scripts
    $root=Join-Path $RunDirectory automation-commit
    [void][IO.Directory]::CreateDirectory($root)
    foreach($kind in @('GitHubWorkflowDocs','ScriptShouldProcess')){
        $fixture=New-QuietCommitWorkspaceFixture -Root $root -RealScriptsPath $scripts
        $fixPath=$null;$good=$null
        if($kind -eq 'GitHubWorkflowDocs'){
            $directory=Join-Path $fixture .github/workflows;[void][IO.Directory]::CreateDirectory($directory)
            $fixPath=Join-Path $directory owned.yml
            $good="on:`n  workflow_dispatch:`njobs:`n  owned:`n    runs-on: ubuntu-latest`n"
            [void][IO.File]::WriteAllTextAsync($fixPath,$good,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $hash=(Get-FileHash $fixPath).Hash
            $doc=Join-Path $fixture docs/ci/github/script-owned.md
            $text=@('# Owned','',('<!-- workflow-source-sha256: '+$hash+' -->'),'','## Purpose','','Owned test.','','## Triggers','','Manual.','','<!-- workflow-generated:begin -->','<!-- workflow-generated:end -->','','## Scripts and effects','','None.','','## Validation and limits','','Fixture.','') -join "`n"
            [void][IO.File]::WriteAllTextAsync($doc,$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $null=& (Join-Path $scripts Sync-GitHubWorkflowsReadme.ps1) -WorkspaceRoot $fixture -Apply
            [void][IO.File]::WriteAllTextAsync($fixPath,($good+"# Unreviewed staged change`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        }else{
            $fixPath=Join-Path $fixture scripts/Test-Unsafe.ps1
            $bad='[IO.File]::WriteAllText(''forbidden'',''bad'')'
            $good='[CmdletBinding(SupportsShouldProcess)]param(); if($PSCmdlet.ShouldProcess(''owned'',''write'')){[IO.File]::WriteAllText(''owned'',''safe'')}'
            [void][IO.File]::WriteAllTextAsync($fixPath,$bad,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            [void][IO.File]::WriteAllTextAsync((Join-Path $fixture docs/scripts/Test-Unsafe.md),"# Owned unsafe fixture`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $null=& (Join-Path $scripts Sync-ScriptsReadme.ps1) -ScriptsPath (Join-Path $fixture scripts) -DocsPath (Join-Path $fixture docs/scripts) -Apply
        }
        $null=& (Join-Path $scripts Sync-DocsCredits.ps1) -DocsPath (Join-Path $fixture docs) -RootPath $fixture -CreditsPath (Join-Path $fixture CREDITS.md) -Apply
        $null=& (Join-Path $scripts Update-WorkspaceLock.ps1) -WorkspaceRoot $fixture
        $null=Invoke-WorkspaceNative git @('-C',$fixture,'add','--all','--') $fixture
        [void][IO.File]::WriteAllTextAsync($fixPath,$good,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $index=(Get-FileHash (Join-Path $fixture .git/index)).Hash
        $head=Get-QuietCommitWorkspaceHeadRevision $fixture
        $rejected=$false
        try{$null=& (Join-Path $scripts Commit-Workspace.ps1) -WorkspaceRoot $fixture -Message 'Reject staged contract' -NoAll -WhatIf}catch{
            $rejected=$_.Exception.Message -like $(if($kind -eq 'GitHubWorkflowDocs'){'WorkflowDocumentationStale*'}else{'ScriptShouldProcessRequired*'})
        }
        if(!$rejected){throw ('StagedAutomationContractAccepted: '+$kind)}
        # Unsafe staged script bytes deliberately violate both independently reported contracts.
        $flags=@{NoGitHubWorkflowDocsCheck=($kind -eq 'GitHubWorkflowDocs');NoScriptShouldProcessCheck=($kind -eq 'ScriptShouldProcess');NoScriptContractsCheck=($kind -eq 'ScriptShouldProcess')}
        $result=@(& (Join-Path $scripts Commit-Workspace.ps1) -WorkspaceRoot $fixture -Message 'Explicitly skip staged contract preview' -NoAll -WhatIf @flags)
        if(@($result|Where-Object {$_.PSObject.Properties['Check'] -and $_.Check -ceq $kind -and $_.State -ceq 'Skipped'}).Count -ne 1){throw 'CommitAutomationSkipNotReported'}
        if((Get-FileHash (Join-Path $fixture .git/index)).Hash -cne $index -or (Get-QuietCommitWorkspaceHeadRevision $fixture) -cne $head){throw 'CommitAutomationWhatIfMutatedRepository'}
    }
    Write-WorkspaceJson (Join-Path $RunDirectory automation-commit-campaign.json) @{StagedContracts=2;UnstagedRepairsRejected=2;ExplicitSkipsReported=2;HeadAndIndexUnchanged=$true}
}
function Test-QuietReportStreaming {
    <#
    .SYNOPSIS
    Generates fragmented Unicode report streams and checks bounded read-only tails and malformed bytes.
    .PARAMETER WorkspaceRoot
    Source of the shared streaming helper.
    .PARAMETER RunDirectory
    Owned deterministic corpus and mutation evidence.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/Common.psm1) -DisableNameChecking -ErrorAction Stop
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/ReportStreaming.psm1) -DisableNameChecking -ErrorAction Stop
    $directory=Join-Path $RunDirectory report-streaming;[void][IO.Directory]::CreateDirectory($directory)
    $random=[Random]::new(20261111);$utf8=[Text.UTF8Encoding]::new($false,$true)
    $path=Join-Path $directory owned.log
    foreach($round in 0..63){
        $expected=@(1..($random.Next(2,25))|ForEach-Object { 'été漢字🙂-'+$round+'-'+$_ })
        $bytes=$utf8.GetBytes(($expected -join "`n")+"`n")
        [IO.File]::WriteAllBytes($path,[byte[]]@());$state=New-QuietReportStream $path
        $observed=[Collections.Generic.List[string]]::new();$position=0
        $writer=[IO.FileStream]::new($path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
        try{
            while($position -lt $bytes.Length){
                $count=[Math]::Min($bytes.Length-$position,$random.Next(1,8))
                [void]$writer.WriteAsync($bytes,$position,$count).GetAwaiter().GetResult();[void]$writer.FlushAsync().GetAwaiter().GetResult();$position+=$count
                foreach($line in (Read-QuietReportStream $state -MaxLines 100)){$observed.Add($line)}
            }
        }finally{$writer.Dispose()}
        if(($observed -join '|') -cne ($expected -join '|') -or $state.TotalBytes -ne $bytes.Length -or $state.TotalLines -ne $expected.Count){throw 'ReportUnicodeFragmentationPropertyFailed'}
        if((Read-QuietReportStream $state).Count){throw 'ReportStreamRepeatedOldOutput'}
    }
    [IO.File]::WriteAllTextAsync($path,((1..200 -join "`n")+"`n"),$utf8).GetAwaiter().GetResult();$state=New-QuietReportStream $path
    $tail=Read-QuietReportStream $state -MaxLines 4
    if($tail.Count -ne 4 -or $state.Lines.Count -ne 4 -or $tail[-1] -cne '200'){throw 'ReportTailNotBounded'}
    [IO.File]::WriteAllTextAsync($path,"reset`n",$utf8).GetAwaiter().GetResult()
    if((Read-QuietReportStream $state)[0] -cne 'reset'){throw 'ReportTruncationNotReset'}
    foreach($bad in @([byte[]]@(255),[byte[]]@(195,32),[byte[]]@(237,160,128))){
        [IO.File]::WriteAllBytes($path,$bad);$state=New-QuietReportStream $path;$rejected=$false
        try{$null=Read-QuietReportStream $state}catch{$rejected=$true}
        if(!$rejected){throw 'ReportMalformedUtf8Accepted'}
    }
    $source=(Get-Command Read-QuietReportStream).ScriptBlock.ToString()
    $mutant=[scriptblock]::Create($source.Replace('$State.Decoder.GetChars','([Text.UTF8Encoding]::new($false,$true).GetDecoder()).GetChars'))
    [IO.File]::WriteAllBytes($path,[byte[]]@(195));$state=New-QuietReportStream $path;$null=& $mutant $state
    $writer=[IO.FileStream]::new($path,[IO.FileMode]::Append);try{$writer.WriteByte(169)}finally{$writer.Dispose()}
    $killed=$false;try{$null=& $mutant $state}catch{$killed=$true}
    if(!$killed){throw 'NonIncrementalReportDecoderMutantSurvived'}
    Write-WorkspaceJson (Join-Path $RunDirectory report-streaming-campaign.json) @{Seed=20261111;GeneratedStreams=64;MalformedCorpus=3;BoundedTail=$true;TruncationReset=$true;MutantsKilled=1}
}
function Test-QuietResourceCommitChecks {
    <#
    .SYNOPSIS
    Proves resource and script-review gates inspect the prepared index and report explicit omissions.
    .PARAMETER WorkspaceRoot
    Source of the shared commit pipeline.
    .PARAMETER RunDirectory
    Owned disposable repositories and evidence.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/Common.psm1) -DisableNameChecking -ErrorAction Stop
    $scripts=Join-Path $WorkspaceRoot scripts
    $root=Join-Path $RunDirectory resource-commit;[void][IO.Directory]::CreateDirectory($root)
    foreach($kind in @('Resources','ScriptContracts')){
        $fixture=New-QuietCommitWorkspaceFixture -Root $root -RealScriptsPath $scripts
        $path=Join-Path $fixture $(if($kind -eq 'Resources'){'docs/resources/README.md'}else{'scripts/Get-Tracked.ps1'})
        $good=Get-Content $path -Raw -Encoding utf8
        $bad=if($kind -eq 'Resources'){$good+"`nStale owned fixture.`n"}else{"#Objective: Unwanted script header.`n"+$good}
        [void][IO.File]::WriteAllTextAsync($path,$bad,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $null=& (Join-Path $scripts Update-WorkspaceLock.ps1) -WorkspaceRoot $fixture
        $null=Invoke-WorkspaceNative git @('-C',$fixture,'add','--all','--') $fixture
        [void][IO.File]::WriteAllTextAsync($path,$good,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $index=(Get-FileHash (Join-Path $fixture .git/index)).Hash;$head=Get-QuietCommitWorkspaceHeadRevision $fixture
        $rejected=$false
        try{$null=& (Join-Path $scripts Commit-Workspace.ps1) -WorkspaceRoot $fixture -Message 'Reject stale staged documentation' -NoAll -WhatIf}catch{
            $rejected=$_.Exception.Message -like $(if($kind -eq 'Resources'){'ResourcesReadmeStale*'}else{'ScriptContractStale*'})
        }
        if(!$rejected){throw ('PreparedResourceContractAccepted: '+$kind)}
        $flags=@{NoResourcesCheck=($kind -eq 'Resources');NoScriptContractsCheck=($kind -eq 'ScriptContracts')}
        $result=@(& (Join-Path $scripts Commit-Workspace.ps1) -WorkspaceRoot $fixture -Message 'Explicit omission preview' -NoAll -WhatIf @flags)
        if(@($result|Where-Object {$_.PSObject.Properties['Check'] -and $_.Check -ceq $kind -and $_.State -ceq 'Skipped'}).Count -ne 1){throw 'ResourceCommitSkipNotReported'}
        if((Get-FileHash (Join-Path $fixture .git/index)).Hash -cne $index -or (Get-QuietCommitWorkspaceHeadRevision $fixture) -cne $head){throw 'ResourceCommitPreviewMutatedRepository'}
    }
    Write-WorkspaceJson (Join-Path $RunDirectory resource-commit-campaign.json) @{PreparedContracts=2;UnstagedRepairsRejected=2;ExplicitOmissions=2;HeadAndIndexUnchanged=$true}
}
function Test-QuietObjectiveOutput {
    <#
    .SYNOPSIS
    Separates inert objective comments from executable host output using owned copies of a real check.
    .PARAMETER WorkspaceRoot
    Source of the checked scripts.
    .PARAMETER RunDirectory
    Owned baseline and generated-comment evidence.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/Common.psm1) -DisableNameChecking -ErrorAction Stop
    $directory=Join-Path $RunDirectory objective-output;[void][IO.Directory]::CreateDirectory($directory)
    Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'scripts/Invoke-WorkspaceChecks.ps1')) $directory
    Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'scripts/Sync-Credits.ps1')) $directory
    Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib')) ([IO.Path]::Combine($directory,'lib')) -Recurse
    $path=Join-Path $directory Invoke-WorkspaceChecks.ps1
    $text=Get-Content $path -Raw -Encoding utf8
    $before=@(& $path -WorkspaceRoot $WorkspaceRoot -Check Credits 6>&1|ForEach-Object {if($_ -is [Management.Automation.InformationRecord]){[string]$_.MessageData}else{$_.Check+'='+$_.State}})
    $stripped=[regex]::Replace($text,'(?m)^#\s*Objective:[^\r\n]*(?:\r?\n|$)','')
    [void][IO.File]::WriteAllTextAsync($path,$stripped,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    $after=@(& $path -WorkspaceRoot $WorkspaceRoot -Check Credits 6>&1|ForEach-Object {if($_ -is [Management.Automation.InformationRecord]){[string]$_.MessageData}else{$_.Check+'='+$_.State}})
    if(($before -join "`n") -cne ($after -join "`n")){throw 'RemovingCommentsChangedRealScriptOutput'}
    $loaded=@(& {Import-Module (Join-Path $WorkspaceRoot scripts/lib/Resources.psm1) -DisableNameChecking -ErrorAction Stop;Import-Module (Join-Path $WorkspaceRoot scripts/lib/ReportStreaming.psm1) -DisableNameChecking -ErrorAction Stop} *>&1)
    if($loaded.Count){throw 'FunctionLibraryLoadProducedOutput'}
    $random=[Random]::new(20261112)
    foreach($index in 0..63){
        $source='#Objective: é漢🙂 '+$random.Next()+"`n'expected-business-value'"
        $actual=@(& ([scriptblock]::Create($source)) *>&1)
        if($actual.Count -ne 1 -or $actual[0] -cne 'expected-business-value'){throw 'ObjectiveCommentProducedOutput'}
    }
    $headers=0;$writes=0
    foreach($file in Get-ChildItem (Join-Path $WorkspaceRoot scripts) -Filter *.ps1 -File){
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        $headers+=@($tokens|Where-Object {$_.Kind -eq 'Comment' -and $_.Text -match '^#Objective:'}).Count
        $writes+=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Host' -and $node.Extent.Text -match '#Objective:'},$true)).Count
    }
    Write-WorkspaceJson (Join-Path $RunDirectory objective-output-campaign.json) @{Seed=20261112;CommentProperties=64;RootScriptHeaders=$headers;ExplicitObjectiveWrites=$writes;LibraryLoadOutput=$loaded.Count;Before=$before;After=$after;RemovingCommentsChangedOutput=$false}
}
