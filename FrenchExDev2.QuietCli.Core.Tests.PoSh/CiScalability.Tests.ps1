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
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/CiImpact.psm1')
    . (Join-Path $WorkspaceRoot 'scripts/CiImages.ps1')
    $vectors=@(
        @{Path='FrenchExDev2.QuietCli.Git.PoSh/src/Commands.ps1';Suite='Git';Products=$true;Tooling=$false},
        @{Path='FrenchExDev2.QuietCli.Git.Tests.PoSh/Queries.Tests.ps1';Suite='Git';Products=$true;Tooling=$false},
        @{Path='FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1';Suite='Vagrant';Products=$true;Tooling=$false},
        @{Path='FrenchExDev2.QuietCli.Core.PoSh/engine/Program.cs';Suite='All';Products=$true;Tooling=$true},
        @{Path='FrenchExDev2.QuietCli.Core.Tests.PoSh/Script.Tests.ps1';Suite='All';Products=$true;Tooling=$true},
        @{Path='scripts/Build-Workspace.ps1';Suite='All';Products=$true;Tooling=$true},
        @{Path='new-unknown-input';Suite='All';Products=$true;Tooling=$true},
        @{Path='docs/README.md';Suite='All';Products=$false;Tooling=$false},
        @{Path='FrenchExDev2.QuietCli.Tooling.Tests.PoSh/README.md';Suite='All';Products=$false;Tooling=$true}
    )
    foreach($vector in $vectors){
        $plan=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths @($vector.Path)
        Assert-QuietEqual $plan.Suite $vector.Suite $vector.Path
        Assert-QuietEqual $plan.RunProducts $vector.Products $vector.Path
        Assert-QuietEqual $plan.RunTooling $vector.Tooling $vector.Path
    }
    $combined=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths @($vectors[0].Path,$vectors[2].Path)
    Assert-QuietEqual $combined.Suite All
    Assert-QuietEqual $combined.SelectedSuites.Count 3
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
    $vagrant=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot Vagrant)
    Assert-QuietEqual ($vagrant -ccontains 'FrenchExDev2.QuietCli.Git.PoSh') $false
    $coverage=Join-Path $RunDirectory 'ci-catalogue-coverage'
    foreach($project in Get-QuietWorkspaceProjects $WorkspaceRoot){
        $destination=Join-Path $coverage $project.Name;[void][IO.Directory]::CreateDirectory($destination)
        Copy-Item -LiteralPath $project.ManifestPath -Destination (Join-Path $destination ($project.Name+'.psd1'))
    }
    foreach($path in @('build/companions.yml','FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json','FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll')){
        $destination=Join-Path $coverage $path;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath (Join-Path $WorkspaceRoot $path) -Destination $destination
    }
    $product='FrenchExDev2.QuietCli.Nimbus.PoSh';$tests='FrenchExDev2.QuietCli.Nimbus.Tests.PoSh'
    New-QuietWorkspaceFixtureProject $coverage $product @('FrenchExDev2.QuietCli.Core.PoSh') -Metadata ("@{TestsModule='"+$tests+"'}")
    New-QuietWorkspaceFixtureProject $coverage $tests @($product,'FrenchExDev2.QuietCli.Core.Tests.PoSh') -Command Invoke-QuietNimbusCustomTests -Metadata "@{TestCatalogue=@{Runner='Invoke-QuietNimbusCustomTests';Sources=@()}}"
    $rejected=$false;try{$null=Get-QuietWorkspaceSuiteSelection $coverage All}catch{$rejected=$_.Exception.Message -ceq 'WorkspaceCompanionQualificationUndeclared: Nimbus'}
    Assert-QuietEqual $rejected $true 'A newly generated product cannot be silently omitted from All'
    $catalogue=Join-Path $coverage 'build/companions.yml'
    $yaml=[IO.File]::ReadAllText($catalogue,[Text.Encoding]::UTF8)
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
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -Destination $manifestDirectory
    $install=@{SdkVersion='99.0.100';Rid=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier}
    Write-WorkspaceJson (Join-Path $sdkDirectory 'frenchexdev-install.json') $install
    [void][IO.Directory]::CreateDirectory((Join-Path $sdkDirectory 'shared/Microsoft.NETCore.App/11.0.9-preview'))
    Assert-QuietEqual (Get-QuietWorkspaceDotNetHost $sdkFixture) $null
    [void][IO.Directory]::CreateDirectory((Join-Path $sdkDirectory 'shared/Microsoft.NETCore.App/11.0.7'))
    Assert-QuietEqual (Get-QuietWorkspaceDotNetHost $sdkFixture).SdkVersion '99.0.100'
    $install.Rid='wrong-architecture';Write-WorkspaceJson (Join-Path $sdkDirectory 'frenchexdev-install.json') $install
    Assert-QuietEqual (Get-QuietWorkspaceDotNetHost $sdkFixture) $null
    $previewSandbox=Join-Path $RunDirectory 'mutation-preview-must-not-exist'
    $null=& (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.MutationWorker.ps1') -WorkspaceRoot $WorkspaceRoot -Sandbox $previewSandbox -WhatIf
    Assert-QuietEqual (Test-Path -LiteralPath $previewSandbox) $false
    $previousCache=$env:QUIETCLI_BUILDKIT_CACHE_DIR;$previousActions=$env:GITHUB_ACTIONS
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
