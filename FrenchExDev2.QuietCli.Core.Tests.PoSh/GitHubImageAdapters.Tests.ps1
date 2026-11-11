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
    foreach($runtime in @('podman','docker')){foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){
        & {
            param($WorkspaceRoot,$RunDirectory,$runtime,$rid)
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
            }
            $previous=$env:QUIETCLI_REGISTRY_TOKEN;$env:QUIETCLI_REGISTRY_TOKEN=$null
            try{$receipt=Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory (Join-Path $WorkspaceRoot '.github/containers') -WorkspaceRoot (Join-Path $RunDirectory 'image-adapters') -ArtifactPrefix ($runtime+'-'+$rid) -ContainerRuntime $runtime}
            finally{$env:QUIETCLI_REGISTRY_TOKEN=$previous}
            $build=@($calls|Where-Object {$_.Arguments[0] -eq 'build'})
            if($build.Count -ne 1 -or @($calls|Where-Object File -NE $runtime).Count -or $receipt.Image -cne ('sha256:'+('1'*64))){throw 'ContainerAdapterSelectionChanged'}
            if($runtime -eq 'docker' -and ('--jobs' -in $build[0].Arguments -or '--pull=false' -notin $build[0].Arguments)){throw 'DockerBuildReceivedPodmanOptions'}
            if($runtime -eq 'podman' -and ('--jobs' -notin $build[0].Arguments -or '--pull=never' -notin $build[0].Arguments)){throw 'WorkstationPodmanBuildOptionsChanged'}
        } $WorkspaceRoot $RunDirectory $runtime $rid
    }}
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
