function Test-QuietDockerRegistryDaemon {
    <#
    .SYNOPSIS
    Exercises image publication across isolated Docker credentials using the actual setup action inputs.
    .PARAMETER WorkspaceRoot
    Checkout providing the Docker setup action and image builder.
    .PARAMETER RunDirectory
    Owned fixture directory; no daemon or registry is contacted.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $null=[Reflection.Assembly]::LoadFrom((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'))
    $yaml=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $action=$yaml.Deserialize([IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/actions/cache-ci-layers/action.yml'),[Text.Encoding]::UTF8))
    $setup=@($action['runs']['steps']|Where-Object {$_['uses'] -like 'docker/setup-docker-action@*'})
    if($setup.Count -ne 1){throw 'DockerSetupActionRequired'}
    $setHost=[string]$setup[0]['with']['set-host'] -ieq 'true'
    foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){foreach($cached in @($false,$true)){
        & {
            param($WorkspaceRoot,$RunDirectory,$rid,$cached,$setHost)
            . (Join-Path $WorkspaceRoot 'scripts/CiImages.ps1')
            $plan=Get-QuietCiImagePlan $WorkspaceRoot $rid
            $fixture=Join-Path $RunDirectory ('docker-publication-'+$rid+'-'+$cached)
            $names=@('DOCKER_CONFIG','DOCKER_HOST','DOCKER_CONTEXT','QUIETCLI_REGISTRY_TOKEN','QUIETCLI_BUILDKIT_CACHE_DIR','GITHUB_ACTIONS','GITHUB_REPOSITORY','GITHUB_REF','GITHUB_EVENT_NAME','GITHUB_ACTOR')
            $previous=@{};foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name)}
            $originalConfig=Join-Path $fixture 'original-docker-config'
            $expectedHost='unix:///fixture/setup-docker-action.sock'
            $observed=@{BuildHost=$null;Pushed=$false;AuthDirectory=$null;DigestReads=0}
            function Get-QuietFixtureDockerHost {
                <# .SYNOPSIS
                Models Docker's environment override and config-owned current-context resolution.
                #>
                if($env:DOCKER_HOST){return $env:DOCKER_HOST}
                if($env:DOCKER_CONFIG -ceq $originalConfig){return $expectedHost}
                'unix:///var/run/docker.sock'
            }
            function Get-QuietCiRegistryDigest {
                <# .SYNOPSIS
                Returns a cache miss until the fixture has actually published its built image.
                #>
                $observed.DigestReads++
                if($observed.Pushed){'sha256:'+('2'*64)}
            }
            function Invoke-CiProcess {
                <# .SYNOPSIS
                Supplies daemon identity, image metadata and credential login without native effects.
                #>
                param($FilePath,$ArgumentList,$TimeoutSeconds,$State,$OnOutput,$InputText)
                $architecture=if($rid.EndsWith('arm64')){'arm64'}else{'amd64'}
                switch($ArgumentList[0]){
                    info {$metadata=@{OSType='linux';Architecture=$architecture}}
                    login {
                        $observed.AuthDirectory=$env:DOCKER_CONFIG
                        if($InputText -cne 'synthetic-credential' -or $env:QUIETCLI_REGISTRY_TOKEN){throw 'DockerCredentialBoundaryChanged'}
                        [IO.File]::WriteAllText((Join-Path $env:DOCKER_CONFIG 'config.json'),'{}',[Text.UTF8Encoding]::new($false))
                        return [pscustomobject]@{Outcome='Success';ExitCode=0;ElapsedMs=1}
                    }
                    context {$null=& $OnOutput ([pscustomobject]@{Stream='stdout';Text='setup-docker-action'}) $State;return [pscustomobject]@{Outcome='Success'}}
                    image {$metadata=@{Id=('sha256:'+('1'*64));Architecture=$architecture;Os='linux';Config=@{Labels=@{'org.frenchexdev.quietcli2.inputs'=$plan.Fingerprint;'org.opencontainers.image.source'=$plan.Source}}}}
                    default {throw 'UnexpectedDockerPublicationProbe'}
                }
                $null=& $OnOutput ([pscustomobject]@{Stream='stdout';Text=($metadata|ConvertTo-Json -Depth 5 -Compress)}) $State
                [pscustomobject]@{Outcome='Success';ExitCode=0;ElapsedMs=1}
            }
            function Invoke-WorkspaceNative {
                <# .SYNOPSIS
                Requires publication to find the exact built tag on the same daemon with private credentials.
                #>
                param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds,$LogPath)
                if($Arguments[0] -in @('build','buildx')){
                    $observed.BuildHost=Get-QuietFixtureDockerHost
                    $observed.Tag=$Arguments[[array]::IndexOf($Arguments,'-t')+1]
                    if($cached){
                        $option=$Arguments[[array]::IndexOf($Arguments,'--cache-to')+1]
                        $destination=($option -split ','|Where-Object { $_.StartsWith('dest=') }).Substring(5)
                        [void][IO.Directory]::CreateDirectory($destination)
                        [IO.File]::WriteAllText((Join-Path $destination 'index.json'),'{}',[Text.UTF8Encoding]::new($false))
                    }
                }elseif($Arguments[0] -ceq 'push'){
                    if((Get-QuietFixtureDockerHost) -cne $observed.BuildHost){throw 'DockerPublicationChangedDaemon'}
                    if($Arguments[1] -cne $observed.Tag -or $env:DOCKER_CONFIG -cne $observed.AuthDirectory){throw 'DockerPublicationLostTagOrCredential'}
                    $observed.Pushed=$true
                }elseif($Arguments[0] -cne 'pull'){throw 'UnexpectedDockerPublicationOperation'}
            }
            try{
                $env:DOCKER_CONFIG=$originalConfig;$env:DOCKER_CONTEXT=$null
                $env:DOCKER_HOST=if($setHost){$expectedHost}else{$null}
                $env:QUIETCLI_REGISTRY_TOKEN='synthetic-credential';$env:GITHUB_ACTIONS='true'
                $env:GITHUB_REPOSITORY='FrenchExDev2/QuietCli.PoSh';$env:GITHUB_REF='refs/heads/develop';$env:GITHUB_EVENT_NAME='push';$env:GITHUB_ACTOR='fixture'
                $env:QUIETCLI_BUILDKIT_CACHE_DIR=if($cached){Join-Path $fixture '.cache/ci-buildkit'}else{$null}
                $receipt=Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory (Join-Path $WorkspaceRoot '.github/containers') -WorkspaceRoot $fixture -ArtifactPrefix $rid -ContainerRuntime docker -RegistryCache -PublishCache
                if(!$observed.Pushed -or !$receipt.Published -or $observed.BuildHost -cne $expectedHost -or $observed.DigestReads -ne 2){throw 'DockerPublicationIncomplete'}
                if($env:DOCKER_CONFIG -cne $originalConfig -or (Test-Path -LiteralPath $observed.AuthDirectory)){throw 'DockerPublicationConfigurationNotRestored'}
            }finally{foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name])}}
        } $WorkspaceRoot $RunDirectory $rid $cached $setHost
    }}
    Write-WorkspaceJson (Join-Path $RunDirectory 'docker-publication-regression.json') @{RuntimeIdentifiers=4;CachedAndUncachedPublicationCases=8;IsolatedCredentials=$true;NativeDockerExecuted=$false;RegistryContacted=$false}
}

function Test-QuietGitHubImageAdapters {
    <#
    .SYNOPSIS
    Verifies native container adapters and derived-image credential lifetime without registry access.
    .PARAMETER WorkspaceRoot
    Checkout containing the image orchestration source.
    .PARAMETER RunDirectory
    Private fixture root for generated recipes and receipts.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Test-QuietDockerRegistryDaemon -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    foreach($runtime in @('podman','docker')){foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){foreach($cached in @($false,$true)){
        & {
            param($WorkspaceRoot,$RunDirectory,$runtime,$rid,$cached)
            . (Join-Path $WorkspaceRoot 'scripts/CiImages.ps1')
            $plan=Get-QuietCiImagePlan $WorkspaceRoot $rid
            $calls=[Collections.Generic.List[object]]::new()
            function Invoke-CiProcess {
                <# .SYNOPSIS
                Supplies independently predicted daemon/image metadata without starting a binary.
                .PARAMETER FilePath
                Selected container adapter.
                .PARAMETER ArgumentList
                Native operation being observed.
                .PARAMETER TimeoutSeconds
                Declared operation deadline.
                .PARAMETER State
                Caller-owned callback state.
                .PARAMETER OnOutput
                Real metadata callback under test.
                #>
                param($FilePath,$ArgumentList,$TimeoutSeconds,$State,$OnOutput)
                $calls.Add(@{File=$FilePath;Arguments=$ArgumentList})
                if(($ArgumentList -join ',') -ceq 'context,show'){
                    $null=& $OnOutput ([pscustomobject]@{Stream='stdout';Text='setup-docker-action'}) $State
                    return [pscustomobject]@{Outcome='Success';ExitCode=0;ElapsedMs=1}
                }
                $architecture=if($rid.EndsWith('arm64')){'arm64'}else{'amd64'}
                if($ArgumentList[0] -eq 'info'){
                    $metadata=if($runtime -eq 'podman'){@{Host=@{Os='linux';Arch=$architecture}}}else{@{OSType='linux';Architecture=$(if($architecture -eq 'amd64'){'x86_64'}else{'aarch64'})}}
                }else{
                    $labels=@{'org.frenchexdev.quietcli2.inputs'=$plan.Fingerprint;'org.opencontainers.image.source'=$plan.Source}
                    $metadata=@{Id=('sha256:'+('1'*64));Architecture=$architecture;Os='linux'}
                    if($runtime -eq 'podman'){$metadata.Labels=$labels}else{$metadata.Config=@{Labels=$labels}}
                }
                $null=& $OnOutput ([pscustomobject]@{Stream='stdout';Text=($metadata|ConvertTo-Json -Depth 5 -Compress)}) $State
                [pscustomobject]@{Outcome='Success';ExitCode=0;ElapsedMs=1}
            }
            function Invoke-WorkspaceNative {
                <# .SYNOPSIS
                Records tool selection and argument vectors without building or pulling an image.
                .PARAMETER FilePath
                Selected adapter.
                .PARAMETER Arguments
                Exact argument vector.
                .PARAMETER WorkingDirectory
                Explicit workspace.
                .PARAMETER TimeoutSeconds
                Declared deadline.
                .PARAMETER LogPath
                Owned diagnostic destination.
                #>
                param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds,$LogPath)
                $calls.Add(@{File=$FilePath;Arguments=$Arguments})
                if($Arguments[0] -ceq 'buildx'){
                    $cacheOption=$Arguments[[array]::IndexOf($Arguments,'--cache-to')+1]
                    $destination=($cacheOption -split ',')|Where-Object { $_.StartsWith('dest=') }
                    $destination=$destination.Substring(5)
                    [void][IO.Directory]::CreateDirectory($destination)
                    [IO.File]::WriteAllText((Join-Path $destination 'index.json'),'{}',[Text.UTF8Encoding]::new($false))
                }
            }
            $previous=$env:QUIETCLI_REGISTRY_TOKEN;$previousCache=$env:QUIETCLI_BUILDKIT_CACHE_DIR;$previousActions=$env:GITHUB_ACTIONS
            $env:QUIETCLI_REGISTRY_TOKEN=$null;$env:GITHUB_ACTIONS='true'
            $env:QUIETCLI_BUILDKIT_CACHE_DIR=if($cached){Join-Path $RunDirectory 'image-adapters/.cache/ci-buildkit'}else{$null}
            try{$receipt=Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory (Join-Path $WorkspaceRoot '.github/containers') -WorkspaceRoot (Join-Path $RunDirectory 'image-adapters') -ArtifactPrefix ($runtime+'-'+$rid) -ContainerRuntime $runtime}
            finally{$env:QUIETCLI_REGISTRY_TOKEN=$previous;$env:QUIETCLI_BUILDKIT_CACHE_DIR=$previousCache;$env:GITHUB_ACTIONS=$previousActions}
            $build=@($calls|Where-Object {$_.Arguments[0] -in @('build','buildx')})
            if($build.Count -ne 1 -or @($calls|Where-Object File -NE $runtime).Count -or $receipt.Image -cne ('sha256:'+('1'*64))){throw 'ContainerAdapterSelectionChanged'}
            if($runtime -eq 'docker' -and ('--jobs' -in $build[0].Arguments -or '--pull=false' -notin $build[0].Arguments)){throw 'DockerBuildReceivedPodmanOptions'}
            if($runtime -eq 'podman' -and ('--jobs' -notin $build[0].Arguments -or '--pull=never' -notin $build[0].Arguments)){throw 'WorkstationPodmanBuildOptionsChanged'}
            if($runtime -ceq 'docker' -and $cached -and ($build[0].Arguments[0..4] -join ',') -cne 'buildx,build,--builder,setup-docker-action,--load'){throw 'DockerBuildUsedForeignContext'}
        } $WorkspaceRoot $RunDirectory $runtime $rid $cached
    }}}
    $fixture=Join-Path $RunDirectory 'derived-image-credential';[void][IO.Directory]::CreateDirectory($fixture)
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'scripts/New-CiModuleImage.ps1') -Destination $fixture
    $common='function Invoke-WorkspaceNative { param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds); if($FilePath -ne "docker" -or $Arguments[0] -ne "tag"){throw "UnexpectedFixtureNativeOperation"} }'
    $images='function Get-QuietCiImagePlan { param($WorkspaceRoot,$RuntimeIdentifier); @{Platform="debian";Architecture="x64";Fingerprint=("a"*64)} }; function Get-QuietCiModuleImagePlan { param($WorkspaceRoot,$RuntimeIdentifier,$Module,$ContainerfileFragment,$ModuleArguments,$ModuleInputPaths); @{Arguments=@{};ParentReference=("localhost/quietcli2-ci-core-debian-x64:"+("a"*64))} }; function Invoke-QuietCiImageBuild { param($Plan,$ContextDirectory,$WorkspaceRoot,$ArtifactPrefix,[switch]$RegistryCache,[switch]$PublishCache,[switch]$CacheOnly,$ContainerRuntime); if($CacheOnly){return}; [pscustomobject]@{CredentialPreserved=($env:QUIETCLI_REGISTRY_TOKEN -ceq "synthetic-ephemeral-credential");Runtime=$ContainerRuntime} }'
    $core='$env:QUIETCLI_REGISTRY_TOKEN=$null; [pscustomobject]@{Image=("sha256:"+("1"*64))}'
    foreach($entry in @{ 'Common.ps1'=$common;'CiImages.ps1'=$images;'New-CiImage.ps1'=$core }.GetEnumerator()){[void][IO.File]::WriteAllTextAsync((Join-Path $fixture $entry.Key),$entry.Value,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()}
    $previous=$env:QUIETCLI_REGISTRY_TOKEN
    try{
        $env:QUIETCLI_REGISTRY_TOKEN='synthetic-ephemeral-credential'
        $result=& (Join-Path $fixture 'New-CiModuleImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier linux-x64 -Module Git -ContainerRuntime docker -RegistryCache
        if(!$result.CredentialPreserved -or $result.Runtime -cne 'docker'){throw 'DerivedImageCredentialLostBetweenCoreAndConsumer'}
    }finally{$env:QUIETCLI_REGISTRY_TOKEN=$previous}
}
