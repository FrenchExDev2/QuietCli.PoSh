function Test-QuietCiScalability {
    <#
    .SYNOPSIS
    Checks affected-suite selection, same-tree receipt rejection, scoped builds and intermediate-cache boundaries.
    .PARAMETER WorkspaceRoot
    Selected checkout.
    .PARAMETER RunDirectory
    Owned fixture directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    . (Join-Path $PSScriptRoot 'CiCache.Tests.ps1')
    Test-QuietNuGetCacheLifecycle -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    . (Join-Path $PSScriptRoot 'GitHubRelease.Tests.ps1')
    Test-QuietGitHubReleaseLifecycle -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    . (Join-Path $PSScriptRoot 'MutationShards.Tests.ps1')
    Test-QuietMutationShardContracts -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiImpact.psm1')
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiImages.psm1') -DisableNameChecking -ErrorAction Stop
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/GitHubCi.psm1') -DisableNameChecking -ErrorAction Stop
    $cacheContextProperties=0
    foreach($imagesOnly in @($false,$true)){foreach($event in @('workflow_dispatch','push','pull_request','')){foreach($ref in @('refs/heads/develop','refs/heads/feature/cache','refs/pull/3/merge','')){foreach($repository in @('FrenchExDev2/QuietCli.PoSh','fork/QuietCli.PoSh','')){
        $accepted=$true
        try{Assert-GitHubCiImagePreparationContext -ImagesOnly $imagesOnly -Event $event -Ref $ref -Repository $repository}catch{$accepted=$false}
        $expected=!$imagesOnly -or ($event -ceq 'workflow_dispatch' -and $ref -ceq 'refs/heads/develop' -and $repository -ceq 'FrenchExDev2/QuietCli.PoSh')
        Assert-QuietEqual $accepted $expected 'Cache-only context must not authorize a PR or fork'
        $cacheContextProperties++
    }}}}
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $cacheWorkflow=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build().Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/ci.yml'),[Text.Encoding]::UTF8))
    if($cacheWorkflow['on']['workflow_dispatch']['inputs']['images_only']['default'] -cne 'false'){throw 'CacheOnlyMustBeOptIn'}
    foreach($job in @('qualification-gate','windows','tooling','linux-selection','linux-result','performance-results')){
        if([string]$cacheWorkflow['jobs'][$job]['if'] -notmatch '!inputs\.images_only'){throw ('CacheOnlyStartsQualification: '+$job)}
    }
    $vectors=@(
        @{Path='src/Git/src/FrenchExDev2.QuietCli.Git.PoSh/src/Commands.ps1';Suite='Git';Products=$true;Tooling=$false},
        @{Path='src/Git/test/FrenchExDev2.QuietCli.Git.Tests.PoSh/Queries.Tests.ps1';Suite='Git';Products=$true;Tooling=$false},
        @{Path='src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1';Suite='Vagrant';Products=$true;Tooling=$false},
        @{Path='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/Program.cs';Suite='Core';Products=$true;Tooling=$false},
        @{Path='src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Script.Tests.ps1';Suite='Core';Products=$true;Tooling=$false},
        @{Path='scripts/Build-Workspace.ps1';Suite='None';Products=$false;Tooling=$false;Scripts=$true},
        @{Path='new-unknown-input';Suite='Selected';Products=$true;Tooling=$true},
        @{Path='docs/README.md';Suite='None';Products=$false;Tooling=$false},
        @{Path='src/Tooling/test/FrenchExDev2.QuietCli.Tooling.Tests.PoSh/README.md';Suite='None';Products=$false;Tooling=$false}
    )
    foreach($vector in $vectors){
        $plan=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths @($vector.Path)
        Assert-QuietEqual $plan.Suite $vector.Suite $vector.Path
        Assert-QuietEqual $plan.RunProducts $vector.Products $vector.Path
        Assert-QuietEqual $plan.RunTooling $vector.Tooling $vector.Path
        Assert-QuietEqual (@($plan.ScriptPaths) -join ',') $(if($vector.ContainsKey('Scripts')){$vector.Path}else{''}) $vector.Path
    }
    $combined=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths @($vectors[0].Path,$vectors[2].Path)
    Assert-QuietEqual $combined.Suite Selected
    Assert-QuietEqual $combined.SelectedSuites.Count 2
    # Independent boundary oracle: repository scripts and their tests select only their script tests; look-alike
    # prefixes and mixed shared changes cannot inherit that scope.
    $toolingPaths=@('scripts/New-RunProfile.ps1','scripts/lib/RunProfiler.psm1','scripts/New-CorePerformanceReport.ps1','scripts/lib/CiImpact.psm1','scripts/RunProfiles/coldstart-100.profile.psd1','test/scripts/unit/lib/CiImpact.Tests.ps1')
    $sharedPaths=@('new-unknown-input','build/x.txt','tools/scripts/x.ps1')
    $impactProperties=0;$impactSeed=20261112;$impactRandom=[Random]::new($impactSeed)
    foreach($path in $toolingPaths){
        $plan=Get-QuietCiImpact $WorkspaceRoot @($path)
        Assert-QuietEqual $plan.RunProducts $false $path
        Assert-QuietEqual $plan.RunTooling $false $path
        Assert-QuietEqual (@($plan.ScriptPaths) -join ',') $path $path
        foreach($bad in @($path.ToUpperInvariant(),('x'+$path),('build/'+$path))){
            Assert-QuietEqual (Get-QuietCiImpact $WorkspaceRoot @($bad)).RunProducts $true $bad
        }
        foreach($shared in $sharedPaths){
            foreach($paths in @(@($path,$shared),@($shared,$path))){
                $plan=Get-QuietCiImpact $WorkspaceRoot $paths
                Assert-QuietEqual $plan.RunProducts $true
                Assert-QuietEqual $plan.ConservativeFull $true
                $impactProperties++
            }
        }
    }
    foreach($iteration in 1..64){
        $plan=Get-QuietCiImpact $WorkspaceRoot @('scripts/RunProfiles/profile-'+$impactRandom.Next(100000)+'.profile.psd1')
        Assert-QuietEqual $plan.RunProducts $false
        Assert-QuietEqual $plan.RunTooling $false
        Assert-QuietEqual @($plan.ScriptPaths).Count 1
        $impactProperties++
    }
    $impactModule=Get-Module CiImpact
    $impactSource=(Get-Command Get-QuietCiImpact).ScriptBlock.ToString()
    $impactAnchor="if(`$path.StartsWith('scripts/'"
    if(!$impactSource.Contains($impactAnchor)){throw 'CiImpactMutationAnchorMissing'}
    $impactSource=$impactSource.Replace("[IO.Path]::Combine(`$PSScriptRoot,'CiCompanions.psm1')","[IO.Path]::Combine(`$WorkspaceRoot,'scripts/lib/CiCompanions.psm1')")
    $impactMutant=[scriptblock]::Create($impactSource.Replace($impactAnchor,"if(`$false -and `$path.StartsWith('scripts/'"))
    $mutantPlan=& $impactModule {param($body,$root,$path) & $body -WorkspaceRoot $root -ChangedPaths @($path)} $impactMutant $WorkspaceRoot $toolingPaths[0]
    Assert-QuietEqual $mutantPlan.RunProducts $true 'Removing the reviewed boundary must be observable'
    Write-WorkspaceJson (Join-Path $RunDirectory 'ci-impact-properties.json') @{Seed=$impactSeed;Properties=$impactProperties;UnknownPaths=12;MutantsDetected=1}
    foreach($path in @('../escape','/absolute',("bad"+[char]0+'name'))){
        $rejected=$false;try{$null=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths @($path)}catch{$rejected=$_.Exception.Message -ceq 'CiImpactPathInvalid'}
        Assert-QuietEqual $rejected $true
    }
    $receipt=@{Ready=$true;Tree=('a'*40);RunId='42';RunAttempt='2';Windows='success';Linux='success';PerformanceRequired=$true;Performance='success';ToolingRequired=$true;Tooling='success';ToolingMutation='success';MutationRequired=$false;Mutation='skipped'}
    Assert-QuietEqual (Test-QuietDevelopReceipt $receipt ('a'*40) 42 2) $true
    Assert-QuietEqual (Test-QuietDevelopReceipt $receipt ('b'*40) 42 2) $false
    Assert-QuietEqual (Test-QuietDevelopReceipt $receipt ('a'*40) 43 2) $false
    Assert-QuietEqual (Test-QuietDevelopReceipt $receipt ('a'*40) 42 3) $false
    foreach($field in $receipt.Keys){
        $bad=@{};foreach($key in $receipt.Keys){$bad[$key]=$receipt[$key]}
        $bad.Remove($field)
        Assert-QuietEqual (Test-QuietDevelopReceipt $bad ('a'*40) 42 2) $false ('Missing receipt field: '+$field)
    }
    $core=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot Core)
    Assert-QuietEqual ($core -join ',') 'FrenchExDev2.QuietCli.Core.PoSh,FrenchExDev2.QuietCli.Core.Tests.PoSh'
    Assert-QuietEqual (@(Get-QuietWorkspaceBuildSelection -WorkspaceRoot $WorkspaceRoot -Module FrenchExDev2.QuietCli.Core.PoSh) -join ',') 'FrenchExDev2.QuietCli.Core.PoSh'
    Assert-QuietEqual (@(Get-QuietWorkspaceBuildSelection -WorkspaceRoot $WorkspaceRoot -Module FrenchExDev2.QuietCli.Git.PoSh) -join ',') 'FrenchExDev2.QuietCli.Core.PoSh,FrenchExDev2.QuietCli.Git.PoSh'
    $unknown=$false;try{$null=Get-QuietWorkspaceBuildSelection -WorkspaceRoot $WorkspaceRoot -Module FrenchExDev2.QuietCli.Absent.PoSh}catch{$unknown=$_.Exception.Message -clike 'WorkspaceBuildModuleMissing:*'}
    Assert-QuietEqual $unknown $true
    $vagrant=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot Vagrant)
    Assert-QuietEqual ($vagrant -ccontains 'FrenchExDev2.QuietCli.Git.PoSh') $false
    $coverage=Join-Path $RunDirectory 'ci-catalogue-coverage'
    foreach($project in Get-QuietWorkspaceProjects $WorkspaceRoot){
        $destination=Join-Path $coverage $project.Name;[void][IO.Directory]::CreateDirectory($destination)
        Copy-Item -LiteralPath $project.ManifestPath -Destination (Join-Path $destination ($project.Name+'.psd1'))
    }
    foreach($path in @('build/companions.yaml','src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json','src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll')){
        $destination=Join-Path $coverage ($path.Replace('src/Core/src/',''));[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath (Join-Path $WorkspaceRoot $path) -Destination $destination
    }
    $product='FrenchExDev2.QuietCli.Nimbus.PoSh';$tests='FrenchExDev2.QuietCli.Nimbus.Tests.PoSh'
    New-QuietWorkspaceFixtureProject $coverage $product @('FrenchExDev2.QuietCli.Core.PoSh') -Metadata ("@{TestsModule='"+$tests+"'}")
    New-QuietWorkspaceFixtureProject $coverage $tests @($product,'FrenchExDev2.QuietCli.Core.Tests.PoSh') -Command Invoke-QuietNimbusCustomTests -Metadata "@{TestCatalogue=@{Runner='Invoke-QuietNimbusCustomTests';Sources=@()}}"
    $rejected=$false;try{$null=Get-QuietWorkspaceSuiteSelection $coverage All}catch{$rejected=$_.Exception.Message -ceq 'WorkspaceCompanionQualificationUndeclared: Nimbus'}
    Assert-QuietEqual $rejected $true 'A newly generated product cannot be silently omitted from All'
    $catalogue=Join-Path $coverage 'build/companions.yaml'
    $yaml=[IO.File]::ReadAllText($catalogue,[Text.Encoding]::UTF8)
    # The fixture uses flat project directories, so it has no grouped layout paths.
    $yaml=$yaml -creplace '(?m)^    (?:src|test): .+\r?\n',''
    [IO.File]::WriteAllText($catalogue,$yaml,[Text.UTF8Encoding]::new($false))
    $yaml=$yaml.Replace('companions:',"companions:`n  Nimbus:`n    requires: [Core]`n    image: none")
    $yaml=$yaml.Replace('suites:',"suites:`n  Nimbus:`n    test_project: $tests`n    command: Invoke-QuietNimbusCustomTests`n    requires: [Nimbus]`n    core_evidence: false")
    [IO.File]::WriteAllText($catalogue,$yaml,[Text.UTF8Encoding]::new($false))
    Assert-QuietEqual @((Get-QuietWorkspaceSuiteSelection $coverage All)|Where-Object Name -CEQ Nimbus).Count 1
    Assert-QuietEqual (Get-QuietWorkspaceSuiteSelection $coverage Nimbus).Command Invoke-QuietNimbusCustomTests
    $cacheWorkspace=Join-Path $RunDirectory 'ci-buildkit'
    $sdkFixture=Join-Path $RunDirectory 'private-sdk-selection'
    $sdkDirectory=Join-Path $sdkFixture '.dotnet/99.0.100'
    [void][IO.Directory]::CreateDirectory($sdkDirectory)
    [IO.File]::WriteAllText((Join-Path $sdkFixture 'global.json'),'{"sdk":{"version":"99.0.100"}}',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $sdkDirectory $(if($IsWindows){'dotnet.exe'}else{'dotnet'})),'must never execute',[Text.UTF8Encoding]::new($false))
    $manifestDirectory=Join-Path $sdkFixture 'FrenchExDev2.QuietCli.Core.Tests.PoSh';[void][IO.Directory]::CreateDirectory($manifestDirectory)
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -Destination $manifestDirectory
    $install=@{SdkVersion='99.0.100';Rid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier}
    Write-WorkspaceJson (Join-Path $sdkDirectory 'frenchexdev-install.json') $install
    [void][IO.Directory]::CreateDirectory((Join-Path $sdkDirectory 'shared/Microsoft.NETCore.App/11.0.9-preview'))
    Assert-QuietEqual (Get-QuietWorkspaceDotNetHost $sdkFixture) $null
    [void][IO.Directory]::CreateDirectory((Join-Path $sdkDirectory 'shared/Microsoft.NETCore.App/11.0.7'))
    Assert-QuietEqual (Get-QuietWorkspaceDotNetHost $sdkFixture).SdkVersion '99.0.100'
    $install.Rid='wrong-architecture';Write-WorkspaceJson (Join-Path $sdkDirectory 'frenchexdev-install.json') $install
    Assert-QuietEqual (Get-QuietWorkspaceDotNetHost $sdkFixture) $null
    $previewSandbox=Join-Path $RunDirectory 'mutation-preview-must-not-exist'
    $null=& (Join-Path $WorkspaceRoot 'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.MutationWorker.ps1') -WorkspaceRoot $WorkspaceRoot -Sandbox $previewSandbox -WhatIf
    Assert-QuietEqual (Test-Path -LiteralPath $previewSandbox) $false
    $previousCache=$env:QUIETCLI_BUILDKIT_CACHE_DIR;$previousActions=$env:GITHUB_ACTIONS
    $seed=20261112;$random=[Random]::new($seed)
    foreach($context in @('default','setup-docker-action','desktop-linux')+@(1..24|ForEach-Object {'fixture-'+$random.Next()})){
        $command=@(Get-QuietCiBuildCommand -ContainerRuntime docker -Cached -DockerContext $context)
        Assert-QuietEqual ($command -join '|') ('buildx|build|--builder|'+$context+'|--load')
        Assert-QuietEqual (@(Get-QuietCiBuildCommand -ContainerRuntime docker -DockerContext $context) -join '|') 'build'
        Assert-QuietEqual (@(Get-QuietCiBuildCommand -ContainerRuntime podman -Cached -DockerContext $context) -join '|') 'build'
    }
    foreach($context in @('','../escape',"context`nother",'two contexts','--invalid')){
        $rejected=$false;try{$null=Get-QuietCiBuildCommand -ContainerRuntime docker -Cached -DockerContext $context}catch{$rejected=$_.Exception.Message -ceq 'CiDockerContextInvalid'}
        Assert-QuietEqual $rejected $true
    }
    $builderSource=(Get-Command Get-QuietCiBuildCommand).ScriptBlock.ToString()
    $mutant=[scriptblock]::Create($builderSource.Replace("'--builder',`$DockerContext","'--builder','default'"))
    if((& $mutant -ContainerRuntime docker -Cached -DockerContext setup-docker-action) -join '|' -ceq 'buildx|build|--builder|setup-docker-action|--load'){throw 'CiDefaultBuilderMutantSurvived'}
    try{
        $env:GITHUB_ACTIONS='true';$env:QUIETCLI_BUILDKIT_CACHE_DIR=Join-Path $cacheWorkspace '.cache/ci-buildkit'
        $plan=[pscustomobject]@{RegistryPath='fixture/linux-x64-core'}
        $cold=Get-QuietCiBuildCacheOptions $plan $cacheWorkspace docker
        Assert-QuietEqual ($cold.Arguments -contains '--cache-from') $false
        Assert-QuietEqual ($cold.Arguments[-1].EndsWith(',mode=max')) $true
        [void][IO.Directory]::CreateDirectory($cold.Source)
        [IO.File]::WriteAllText((Join-Path $cold.Source 'index.json'),'{}',[Text.UTF8Encoding]::new($false))
        $warm=Get-QuietCiBuildCacheOptions $plan $cacheWorkspace docker
        Assert-QuietEqual ($warm.Arguments -contains '--cache-from') $true
        Assert-QuietEqual $warm.Source $cold.Source
        $other=Get-QuietCiBuildCacheOptions ([pscustomobject]@{RegistryPath='fixture/linux-arm64-core'}) $cacheWorkspace docker
        Assert-QuietEqual ($other.Source -cne $warm.Source) $true
        Assert-QuietEqual (Get-QuietCiBuildCacheOptions $plan $cacheWorkspace podman) $null
        $env:QUIETCLI_BUILDKIT_CACHE_DIR=Join-Path $cacheWorkspace '../outside'
        $rejected=$false;try{$null=Get-QuietCiBuildCacheOptions $plan $cacheWorkspace docker}catch{$rejected=$_.Exception.Message -ceq 'CiBuildCacheMustBelongToWorkflowCheckout'}
        Assert-QuietEqual $rejected $true
    }finally{$env:QUIETCLI_BUILDKIT_CACHE_DIR=$previousCache;$env:GITHUB_ACTIONS=$previousActions}
}
