function Get-QuietCiFingerprint {
    <#
    .SYNOPSIS
    Hashes an image plan's own input files and its rendered Containerfile text into one deterministic
    identity, optionally folding in a parent's own fingerprint.
    .DESCRIPTION
    Shared by Core's own plan and every Core-consumer module's plan, so the fingerprint idiom (sorted
    "path hash" lines, SHA-256 over the joined text) is written once.
    .PARAMETER WorkspaceRoot
    QuietCli2 monorepo root.
    .PARAMETER InputPaths
    Workspace-relative paths hashed by content.
    .PARAMETER ContainerfileText
    The already-rendered Containerfile text, hashed so a declared-fragment-only change still invalidates
    the cache even when no file was touched.
    .PARAMETER ParentFingerprint
    A Core-consumer module's own Core fingerprint, folded in so a Core change also invalidates every
    module built on top of it. Omitted for Core's own plan, which has no parent.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string[]]$InputPaths,[Parameter(Mandatory)][string]$ContainerfileText,[string]$ParentFingerprint)
    [string[]]$lines=@($InputPaths|ForEach-Object {$_+' '+(Get-FileHash (Join-Path $WorkspaceRoot $_) -Algorithm SHA256).Hash})
    $lines+='CONTAINERFILE '+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($ContainerfileText))).ToLowerInvariant()
    if($ParentFingerprint){$lines+='CORE_FINGERPRINT '+$ParentFingerprint}
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).ToLowerInvariant()
}
function Get-QuietCiImagePlan {
    <#
    .SYNOPSIS
    Resolves one native Linux test image without running a tool or accessing a registry.
    .DESCRIPTION
    Core declares its own needs the same way a Core-consumer module declares its own: through a fixed-path
    script, FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1, returning its own Arguments,
    InputPaths and Containerfile fragment (Stages), plus Base/Architecture/Platform for the requested RID.
    This function only renders that fragment's Containerfile text (Get-QuietModuleContainerfile) and
    composes the fingerprint (Get-QuietCiFingerprint) -- it never hand-authors Containerfile text itself.
    .PARAMETER WorkspaceRoot
    Monorepo containing the reviewed image and upstream source locks.
    .PARAMETER RuntimeIdentifier
    Exact guest architecture and libc to test.
    #>
    param([string]$WorkspaceRoot,[ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier)
    $coreContractPath='FrenchExDev2.QuietCli.Core.PoSh/ci/Get-CiImageArguments.ps1'
    $coreScript=Join-Path $WorkspaceRoot $coreContractPath
    if(!(Test-Path -LiteralPath $coreScript)){throw "CiCoreContractMissing: $coreContractPath"}
    $declaration=& $coreScript -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $RuntimeIdentifier
    $containerfileText=Get-QuietModuleContainerfile -Platform $declaration.Containerfile.Platform -Objective $declaration.Containerfile.Objective -Stages $declaration.Containerfile.Stages
    $inputPaths=@($declaration.InputPaths)+@($coreContractPath)
    $fingerprint=Get-QuietCiFingerprint -WorkspaceRoot $WorkspaceRoot -InputPaths $inputPaths -ContainerfileText $containerfileText
    [pscustomobject]@{Rid=$RuntimeIdentifier;Architecture=$declaration.Architecture;Platform=$declaration.Platform;Base=$declaration.Base;ContainerfileText=$containerfileText;Arguments=$declaration.Arguments;Fingerprint=$fingerprint;RegistryPath="frenchexdev2/quietcli2-ci-$($declaration.Platform)-$($declaration.Architecture)";Source='https://github.com/FrenchExDev2/QuietCli.PoSh'}
}
function Get-QuietModuleContainerfile {
    <#
    .SYNOPSIS
    Renders a Containerfile from an ordered stage list, shared by Core's own declared image and every
    Core-consumer module's derived image.
    .DESCRIPTION
    Core still supplies only the apt/apk cache-mount convention; the caller declares as many stages as it
    needs, each FROM an explicit base (Core's own pinned platform digest), FROM an earlier stage's own
    Name, or (when neither is given) FROM ${CORE_IMAGE} -- a Core-consumer module's usual case, since it
    builds on top of Core's already-verified image rather than naming a base of its own. The ARG
    CORE_IMAGE declaration itself is only emitted when at least one stage actually resolves to it. This
    lets any stage install packages, run extra commands, copy build output, or set ENV/WORKDIR/ENTRYPOINT
    -- not only a single hardcoded final stage -- so Core's own image and a module's derived image are
    rendered by the exact same generator, never hand-authored as Containerfile text on disk.
    .PARAMETER Platform
    'debian' (apt) or 'alpine' (apk), as already resolved for the requested RID.
    .PARAMETER Objective
    One-line comment describing what this image adds or builds.
    .PARAMETER Stages
    Ordered stage declarations, each with: Name (required); From (an earlier declared stage's own Name,
    or an explicit base image reference; omitted means FROM ${CORE_IMAGE}); Args (ARG names, rendered
    before Packages/FetchScript so either may reference them); Packages (space-separated, installed in
    the target platform's own syntax, under a cache-mounted RUN -- any stage may declare its own, not only
    one fixed stage); FetchScript (file name of a script copied from the build context into /tmp and run
    under a separate ci-tools cache mount); Copy (zero or more {Stage;Spec} pairs, rendered as
    "COPY --from=<Stage> <Spec>"); Run (extra plain RUN commands, one per line); Env (an ordered map,
    rendered as one "ENV k=v k2=v2 ..." line); PathPrefix (directory prepended to PATH, for a stage that
    only needs to extend ${PATH} rather than declare a full Env map); WorkDir ("WORKDIR <dir>");
    Entrypoint (string array, rendered as JSON-array-form "ENTRYPOINT [...]").
    #>
    param([Parameter(Mandatory)][ValidateSet('debian','alpine')][string]$Platform,[Parameter(Mandatory)][string]$Objective,[Parameter(Mandatory)][object[]]$Stages)
    $manager=if($Platform -ceq 'debian'){'apt'}else{'apk'}
    $cacheMount=if($Platform -ceq 'debian'){'--mount=type=cache,target=/var/cache/apt,sharing=locked --mount=type=cache,target=/var/lib/apt,sharing=locked'}else{'--mount=type=cache,target=/var/cache/apk,sharing=locked'}
    $stageNames=@($Stages|ForEach-Object Name)
    $usesCoreImage=$false
    $lines=[Collections.Generic.List[string]]::new()
    [void]$lines.Add("# Objectif : $Objective")
    for($i=0;$i -lt $Stages.Count;$i++){
        # Stage declarations omit optional members. Normalize locally so callers running under
        # StrictMode receive the same rendering contract without changing their declarations.
        $stageValues=[ordered]@{}
        foreach($member in @('Name','From','Args','Packages','FetchScript','Copy','Run','Env','PathPrefix','WorkDir','Entrypoint')){
            $declaration=$Stages[$i]
            $stageValues[$member]=if($declaration -is [Collections.IDictionary]){$declaration[$member]}elseif($declaration.PSObject.Properties[$member]){$declaration.$member}else{$null}
        }
        $stage=[pscustomobject]$stageValues
        if($i -gt 0){[void]$lines.Add('')}
        $from=if($stage.From -and $stageNames -contains $stage.From){$stage.From}elseif($stage.From){$stage.From}else{$usesCoreImage=$true;'${CORE_IMAGE}'}
        [void]$lines.Add("FROM $from AS $($stage.Name)")
        foreach($argument in @($stage.Args)){if($argument){[void]$lines.Add("ARG $argument")}}
        if($stage.Packages){
            $install=if($Platform -ceq 'debian'){"rm -f /etc/apt/apt.conf.d/docker-clean && apt-get update && apt-get install -y --no-install-recommends $($stage.Packages)"}else{"ln -sf /var/cache/apk /etc/apk/cache && apk update && apk add $($stage.Packages)"}
            [void]$lines.Add("# The $manager cache mount is local to Podman's build storage; it speeds up a repeated local build but")
            [void]$lines.Add('# is never part of the resulting image layer and is never published or trusted as an input.')
            [void]$lines.Add("RUN $cacheMount \")
            [void]$lines.Add("    $install")
        }
        if($stage.FetchScript){
            [void]$lines.Add("COPY $($stage.FetchScript) /tmp/$($stage.FetchScript)")
            [void]$lines.Add("RUN --mount=type=cache,target=/var/cache/ci-tools,sharing=locked sh /tmp/$($stage.FetchScript)")
        }
        foreach($copy in @($stage.Copy)){if($copy){[void]$lines.Add("COPY --from=$($copy.Stage) $($copy.Spec)")}}
        foreach($run in @($stage.Run)){if($run){[void]$lines.Add("RUN $run")}}
        if($stage.Env){
            $pairs=@($stage.Env.Keys|ForEach-Object {$_+'='+$stage.Env[$_]})
            if($pairs.Count){[void]$lines.Add('ENV '+($pairs -join ' '))}
        }
        if($stage.PathPrefix){[void]$lines.Add('ENV PATH='+$stage.PathPrefix+':${PATH}')}
        if($stage.WorkDir){[void]$lines.Add("WORKDIR $($stage.WorkDir)")}
        if($stage.Entrypoint){[void]$lines.Add('ENTRYPOINT ['+(($stage.Entrypoint|ForEach-Object {'"'+$_+'"'}) -join ',')+']')}
    }
    if($usesCoreImage){$lines.Insert(1,'ARG CORE_IMAGE')}
    ($lines -join "`n")+"`n"
}
function Get-QuietCiModuleImagePlan {
    <#
    .SYNOPSIS
    Resolves one native Linux test image for a Core-consumer module, built on top of Core's own image.
    .DESCRIPTION
    Core is never read beyond its own resolved plan (used only for its Platform/Architecture/Fingerprint);
    this keeps the one-directional dependency intact: a module may depend on Core, Core never depends on it.
    Core also renders the module's actual Containerfile text from the module's own declared fragment (see
    Get-QuietModuleContainerfile), so the module never authors the ARG CORE_IMAGE/FROM ${CORE_IMAGE}
    two-stage boilerplate by hand, and that rendered text is itself hashed into the fingerprint below.
    .PARAMETER WorkspaceRoot
    Monorepo containing the reviewed image and upstream source locks.
    .PARAMETER RuntimeIdentifier
    Exact guest architecture and libc to test.
    .PARAMETER Module
    Lowercase-foldable module name (for example 'Git'), used in the registry path.
    .PARAMETER ContainerfileFragment
    The module's own declared Containerfile fragment (Platform/Objective/Stages), as returned by the
    module's own ci script. See Get-QuietModuleContainerfile for the Stages shape.
    .PARAMETER ModuleArguments
    Ordered build-arg map contributed by the module's own ci script.
    .PARAMETER ModuleInputPaths
    Workspace-relative paths (the module's own fetch script, locks) hashed into the fingerprint.
    .PARAMETER ParentPlan
    Preceding layer plan; its fingerprint invalidates every dependent overlay when changed.
    #>
    param([string]$WorkspaceRoot,[ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,[Parameter(Mandatory)][string]$Module,[Parameter(Mandatory)]$ContainerfileFragment,[Parameter(Mandatory)]$ModuleArguments,[Parameter(Mandatory)][string[]]$ModuleInputPaths,$ParentPlan)
    $core=if($ParentPlan){$ParentPlan}else{Get-QuietCiImagePlan $WorkspaceRoot $RuntimeIdentifier}
    $containerfileText=Get-QuietModuleContainerfile -Platform $ContainerfileFragment.Platform -Objective $ContainerfileFragment.Objective -Stages $ContainerfileFragment.Stages
    $fingerprint=Get-QuietCiFingerprint -WorkspaceRoot $WorkspaceRoot -InputPaths $ModuleInputPaths -ContainerfileText $containerfileText -ParentFingerprint $core.Fingerprint
    [pscustomobject]@{Rid=$RuntimeIdentifier;Architecture=$core.Architecture;Platform=$core.Platform;Core=$core;ContainerfileText=$containerfileText;Arguments=$ModuleArguments;Fingerprint=$fingerprint;RegistryPath="frenchexdev2/quietcli2-ci-$($core.Platform)-$($core.Architecture)-$($Module.ToLowerInvariant())";Source='https://github.com/FrenchExDev2/QuietCli.PoSh'}
}
function Get-QuietCiVerifiedImage {
    <# .SYNOPSIS
    Verifies local image identity, architecture and labels before using an image or parent layer.
    .PARAMETER Plan
    Expected immutable input identity and native architecture.
    .PARAMETER Reference
    Already prepared local image; never pulled here.
    .PARAMETER ContainerRuntime
    Selected native adapter.
    #>
    param($Plan,[string]$Reference,[string]$ContainerRuntime)
    $observed=@{Json=[Text.StringBuilder]::new()}
    $inspection=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('image','inspect',$Reference) -TimeoutSeconds 30 -State $observed -OnOutput {
        param($event,$state)
        if($event.Stream -eq 'stdout'){
            if($state.Json.Length+$event.Text.Length -gt 65536){throw 'CiImageMetadataTooLarge'}
            [void]$state.Json.Append($event.Text)
        }
    }
    if($inspection.Outcome -ne 'Success'){throw 'CiImageInspectionFailed'}
    $items=@($observed.Json.ToString()|ConvertFrom-Json)
    if($items.Count -ne 1){throw 'CiImageIdentityMismatch'}
    $info=$items[0]
    $expected=if($Plan.Architecture -eq 'x64'){'amd64'}else{'arm64'}
    $labels=if($info.PSObject.Properties['Labels']){$info.Labels}else{$info.Config.Labels}
    if($info.Id -cnotmatch '\A(?:sha256:)?[a-f0-9]{64}\z' -or $info.Architecture -cne $expected -or $info.Os -cne 'linux' -or $labels.'org.frenchexdev.quietcli2.inputs' -cne $Plan.Fingerprint -or $labels.'org.opencontainers.image.source' -cne $Plan.Source){throw 'CiImageIdentityMismatch'}
    $info
}
function Get-QuietCiLocalImageArchitecture {
    <#
    .SYNOPSIS
    Reads the architecture podman's local containers-storage actually holds for an image reference.
    .DESCRIPTION
    Used right after a 'podman pull --platform ...': podman keys a stored image by reference (name@digest)
    alone, never by the platform that was requested, so a reference already pulled for one architecture is
    reused as-is for a later pull of the same reference under a different --platform. Comparing this against
    the expected architecture detects that collision before it causes an opaque 'exec format error' deep in
    a build step.
    .PARAMETER Reference
    Image reference as stored locally (name@digest or name:tag).
    .PARAMETER ContainerRuntime
    Local Podman or GitHub Docker adapter; recipe and identity validation are shared.
    #>
    param([Parameter(Mandatory)][string]$Reference,[AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime)
    $ContainerRuntime=Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime
    $observed=@{Json=[Text.StringBuilder]::new()}
    $inspection=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('image','inspect',$Reference) -TimeoutSeconds 30 -State $observed -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Json.Append($e.Text)}}
    if($inspection.Outcome -ne 'Success'){throw 'CiImageInspectionFailed'}
    @($observed.Json.ToString()|ConvertFrom-Json)[0].Architecture
}
function Get-QuietCiRegistryDigest {
    <#
    .SYNOPSIS
    Resolves a cache tag to an immutable GHCR digest; never emits credentials or response bodies.
    .PARAMETER Plan
    Validated image plan.
    .PARAMETER Token
    Optional ephemeral workflow credential, held only in memory.
    .PARAMETER Actor
    Workflow actor used for registry authentication.
    .PARAMETER IncludeConfiguration
    Returns a digest and verified image configuration for GitHub job-container selection.
    #>
    param($Plan,[AllowEmptyString()][string]$Token,[string]$Actor,[switch]$IncludeConfiguration)
    $client=[Net.Http.HttpClient]::new();$client.Timeout=[TimeSpan]::FromSeconds(45)
    try{
        if($Token){$basic=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Actor+':'+$Token));$client.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Basic',$basic)}
        $response=$client.GetAsync('https://ghcr.io/token?service=ghcr.io&scope=repository:'+$Plan.RegistryPath+':pull').GetAwaiter().GetResult()
        try{
            if([int]$response.StatusCode -in @(401,403,404)){return $null}
            if(!$response.IsSuccessStatusCode){throw ('CiRegistryTokenHttpStatus: '+[int]$response.StatusCode)}
            $access=($response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json).token
        }finally{$response.Dispose()}
        $client.DefaultRequestHeaders.Authorization=[Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer',$access)
        $client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json')
        $response=$client.GetAsync('https://ghcr.io/v2/'+$Plan.RegistryPath+'/manifests/'+$Plan.Fingerprint,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try{
            if([int]$response.StatusCode -in @(401,403,404)){return $null}
            if(!$response.IsSuccessStatusCode){throw ('CiRegistryManifestHttpStatus: '+[int]$response.StatusCode)}
            $digest=($response.Headers.GetValues('Docker-Content-Digest') -join '')
            if($digest -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'CiRegistryDigestInvalid'}
            if($IncludeConfiguration){
                $manifest=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
                $configDigest=$manifest.config.digest
                if($configDigest -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'CiRegistryConfigurationDigestInvalid'}
                $configuration=$client.GetAsync('https://ghcr.io/v2/'+$Plan.RegistryPath+'/blobs/'+$configDigest).GetAwaiter().GetResult()
                try{
                    if(!$configuration.IsSuccessStatusCode){throw 'CiRegistryConfigurationUnavailable'}
                    $bytes=$configuration.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                    if($bytes.Length -gt 1048576 -or ('sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()) -cne $configDigest){throw 'CiRegistryConfigurationIdentityInvalid'}
                    $config=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
                    $arch=if($Plan.Architecture -eq 'x64'){'amd64'}else{'arm64'}
                    if($config.architecture -cne $arch -or $config.os -cne 'linux' -or $config.config.Labels.'org.frenchexdev.quietcli2.inputs' -cne $Plan.Fingerprint -or $config.config.Labels.'org.opencontainers.image.source' -cne $Plan.Source){throw 'CiRegistryImageIdentityMismatch'}
                    return [pscustomobject]@{Digest=$digest;Reference=('ghcr.io/'+$Plan.RegistryPath+'@'+$digest);Architecture=$config.architecture;OS=$config.os;Fingerprint=$Plan.Fingerprint}
                }finally{$configuration.Dispose()}
            }
            return $digest
        }finally{$response.Dispose()}
    }finally{$client.Dispose()}
}
function ConvertTo-QuietCiRegistryDiagnostic {
    <#
    .SYNOPSIS
    Redacts registry credentials before retaining a bounded, single-line login diagnostic.
    .PARAMETER Text
    One transient native output record.
    .PARAMETER Token
    Current ephemeral credential; never returned or written as metadata.
    .PARAMETER Actor
    Registry user used to mask a possible encoded Basic credential.
    #>
    param([AllowEmptyString()][string]$Text,[AllowEmptyString()][string]$Token,[string]$Actor)
    if($Token){
        foreach($secret in @($Token,[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Token)),[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Actor+':'+$Token)))){
            $Text=$Text.Replace($secret,'[REDACTED]')
        }
    }
    $Text=[regex]::Replace($Text,'(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)','[REDACTED]')
    $Text=[regex]::Replace($Text,'\x1B\[[0-?]*[ -/]*[@-~]','') -replace '[\x00-\x1F\x7F]',' '
    if($Text.Length -gt 2048){$Text=$Text.Substring(0,2048)}
    return $Text
}
function Invoke-QuietCiImageBuild {
    <#
    .SYNOPSIS
    Builds, verifies and optionally publishes one native Podman image from an already-resolved plan.
    .DESCRIPTION
    Shared by Core's own image build and every Core-consumer module's derived image build, so the Podman
    orchestration (native-architecture check, pull-by-digest-or-build, identity verification, push-by-digest,
    receipt) is written once. A plan carrying a 'Base' property (only Core's own plan, from
    Get-QuietCiImagePlan) is pulled and architecture-checked before the build; a module plan (from
    Get-QuietCiModuleImagePlan) has none, because its Containerfile's FROM target is instead an
    already-local, already-verified image the caller prepared (for example a tag of Core's own resolved
    image). Core's own plan carries a 'Dockerfile' workspace-relative path to its checked-in Containerfile;
    a module plan instead carries 'ContainerfileText', already rendered by Get-QuietModuleContainerfile,
    written out to the receipt directory right before the build so it can be passed to 'podman build -f'.
    .PARAMETER Plan
    Resolved image plan (Get-QuietCiImagePlan or Get-QuietCiModuleImagePlan).
    .PARAMETER ContextDirectory
    Absolute Podman build context directory holding the Dockerfile and its fetch script.
    .PARAMETER WorkspaceRoot
    QuietCli2 monorepo root.
    .PARAMETER ArtifactPrefix
    Receipt directory name prefix under artifacts/ci-images (for example 'linux-x64' or 'git-linux-x64').
    .PARAMETER RegistryCache
    Read the GHCR cache with the optional ephemeral QUIETCLI_REGISTRY_TOKEN credential.
    .PARAMETER PublishCache
    Publish a missing cache entry. Restricted to the upstream develop push/manual workflow, never pull requests.
    .PARAMETER ContainerRuntime
    Podman for workstation runs; Docker for GitHub image preparation and PR fallback.
    .PARAMETER CacheOnly
    Pulls and verifies an existing final image, returning no value on a registry miss without building.
    #>
    param($Plan,[Parameter(Mandatory)][string]$ContextDirectory,[Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$ArtifactPrefix,[switch]$RegistryCache,[switch]$PublishCache,[switch]$CacheOnly,[AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime)
    $ContainerRuntime=Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -WorkspaceRoot $WorkspaceRoot
    # The build must land in a native Linux environment matching the plan's architecture, but that environment is
    # Podman's own backend (its machine VM on Windows/macOS, or the host kernel on Linux), never the pwsh process's
    # own OS: Podman already executes every build inside a real Linux kernel regardless of where its CLI is invoked.
    $podmanHostState=@{Json=[Text.StringBuilder]::new()}
    $podmanHostInfo=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('info','--format','json') -TimeoutSeconds 20 -State $podmanHostState -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Json.Append($e.Text)}}
    if($podmanHostInfo.Outcome -ne 'Success'){throw 'PodmanHostInfoUnavailable'}
    $hostInfo=$podmanHostState.Json.ToString()|ConvertFrom-Json
    $podmanHost=if($ContainerRuntime -eq 'podman'){$hostInfo.Host}else{[pscustomobject]@{Os=$hostInfo.OSType;Arch=$(switch($hostInfo.Architecture){x86_64{'amd64'} aarch64{'arm64'} default{$hostInfo.Architecture}})}}
    $podmanExpectedArch=if($Plan.Architecture -eq 'x64'){'amd64'}else{'arm64'}
    $podmanNativeArch=($podmanHost.Arch -ceq $podmanExpectedArch)
    if($podmanHost.Os -cne 'linux'){throw 'NativeLinuxImageBuildRequired'}
    # A non-native target architecture only runs through Podman's own qemu emulation, never on the CI publication
    # path: that one stays pinned to each architecture's native runner, enforced below regardless of this check.
    if(!$podmanNativeArch -and $PublishCache){throw 'NativeLinuxImageBuildRequired'}
    if($PublishCache -and (!$RegistryCache -or $env:GITHUB_REPOSITORY -cne 'FrenchExDev2/QuietCli.PoSh' -or $env:GITHUB_REF -cne 'refs/heads/develop' -or $env:GITHUB_EVENT_NAME -cnotin @('push','workflow_dispatch'))){throw 'CiImagePublicationNotAuthorizedForThisEvent'}
    $directory=Join-Path $WorkspaceRoot ('artifacts/ci-images/'+$ArtifactPrefix+'-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    # One file per build, independent of console interleaving under -MaxConcurrency, so a failed
    # build is still traceable to its own full podman output after the fact.
    $logPath=Join-Path $directory 'podman.log'
    $token=$env:QUIETCLI_REGISTRY_TOKEN
    # Keep credentials out of all child environments, build arguments, reports and image layers.
    Remove-Item Env:QUIETCLI_REGISTRY_TOKEN -ErrorAction SilentlyContinue
    $authDirectory=$null;$auth=@();$digest=$null;$cacheHit=$false;$dockerfilePath=$null
    $previousDockerConfig=$env:DOCKER_CONFIG
    $registry='ghcr.io/'+$Plan.RegistryPath;$tag=$registry+':'+$Plan.Fingerprint
    try{
        if($RegistryCache){$digest=Get-QuietCiRegistryDigest $Plan $token $env:GITHUB_ACTOR}
        if($CacheOnly -and !$digest){return}
        if($token -and ($digest -or $PublishCache)){
            $authDirectory=Join-Path ([IO.Path]::GetTempPath()) ('quietcli2-registry-'+[guid]::NewGuid().ToString('N'))
            if($IsWindows){[void][IO.Directory]::CreateDirectory($authDirectory)}else{[void][IO.Directory]::CreateDirectory($authDirectory,[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)}
            if($ContainerRuntime -eq 'podman'){$auth=@('--authfile',(Join-Path $authDirectory auth.json))}else{$env:DOCKER_CONFIG=$authDirectory}
            $loginState=@{Token=$token;Actor=$env:GITHUB_ACTOR;Lines=[Collections.Generic.Queue[object]]::new()}
            $login=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList (@('login')+$auth+@('--username',$env:GITHUB_ACTOR,'--password-stdin','ghcr.io')) -InputText $token -TimeoutSeconds 45 -State $loginState -OnOutput {
                param($e,$s)
                $text=ConvertTo-QuietCiRegistryDiagnostic -Text $e.Text -Token $s.Token -Actor $s.Actor
                if($s.Lines.Count -ge 12){$null=$s.Lines.Dequeue()}
                $s.Lines.Enqueue(@{Stream=$e.Stream;Text=$text})
            }
            $loginState.Token=$null
            $loginReceipt=@{Registry='ghcr.io';RuntimeIdentifier=$Plan.Rid;Outcome=$login.Outcome;ExitCode=$login.ExitCode;ElapsedMs=$login.ElapsedMs;InputEncoding='UTF-8 without BOM';InputPreambleHex='';Diagnostics=@($loginState.Lines)}
            Write-WorkspaceJson (Join-Path $directory 'registry-login.json') $loginReceipt
            if($login.Outcome -ne 'Success'){
                Write-Host ('CI registry login diagnostic: '+($loginReceipt|ConvertTo-Json -Depth 5 -Compress))
                throw 'CiRegistryLoginFailed'
            }
        }
        if($digest){
            $null=Invoke-WorkspaceNative $ContainerRuntime (@('pull')+$auth+@($registry+'@'+$digest)) $WorkspaceRoot -TimeoutSeconds 600 -LogPath $logPath
            $image=$registry+'@'+$digest;$cacheHit=$true
        }else{
            if($ContainerRuntime -eq 'docker'){$env:DOCKER_CONFIG=$previousDockerConfig}
            $platform=@();if(!$podmanNativeArch){$platform=@('--platform',('linux/'+$podmanExpectedArch))}
            if($Plan.PSObject.Properties.Match('Base').Count -and $Plan.Base){
                # podman's local containers-storage keys a pulled image by reference (name@digest) alone, never by
                # the requested --platform: a base image already pulled natively under this exact digest by another
                # (possibly concurrent) target is reused as-is even when a different architecture is now requested,
                # which built an image for the wrong architecture under 'exec format error' rather than any clear
                # diagnostic. Pulling by digest is otherwise correct and is kept; this only guards against that
                # specific local-storage collision by re-pulling once, forcing the stale entry out first.
                $null=Invoke-WorkspaceNative $ContainerRuntime (@('pull')+$platform+@($Plan.Base)) $WorkspaceRoot -TimeoutSeconds 300 -LogPath $logPath
                $baseArch=Get-QuietCiLocalImageArchitecture $Plan.Base -ContainerRuntime $ContainerRuntime
                if($baseArch -cne $podmanExpectedArch){
                    $null=Invoke-WorkspaceNative $ContainerRuntime @('rmi','--force',$Plan.Base) $WorkspaceRoot -TimeoutSeconds 60 -LogPath $logPath
                    $null=Invoke-WorkspaceNative $ContainerRuntime (@('pull')+$platform+@($Plan.Base)) $WorkspaceRoot -TimeoutSeconds 300 -LogPath $logPath
                    $baseArch=Get-QuietCiLocalImageArchitecture $Plan.Base -ContainerRuntime $ContainerRuntime
                    if($baseArch -cne $podmanExpectedArch){throw "CiImageBaseArchitectureCacheCollision: expected $podmanExpectedArch, got $baseArch for $($Plan.Base) - see $logPath"}
                }
            }
            $dockerfilePath=if($Plan.PSObject.Properties.Match('ContainerfileText').Count -and $Plan.ContainerfileText){
                $generated=Join-Path $directory 'Containerfile'
                [void][IO.File]::WriteAllTextAsync($generated,$Plan.ContainerfileText,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $generated
            }else{
                Join-Path $WorkspaceRoot $Plan.Dockerfile
            }
            $buildOptions=if($ContainerRuntime -eq 'podman'){@('--pull=never','--jobs','1')}else{@('--pull=false')}
            $arguments=@('build')+$buildOptions+$platform+@('--label',('org.opencontainers.image.source='+$Plan.Source),'--label',('org.frenchexdev.quietcli2.inputs='+$Plan.Fingerprint),'-f',$dockerfilePath,'-t',$tag)
            foreach($entry in $Plan.Arguments.GetEnumerator()){$arguments+=@('--build-arg',($entry.Key+'='+$entry.Value))}
            $arguments+=$ContextDirectory
            $null=Invoke-WorkspaceNative $ContainerRuntime $arguments $WorkspaceRoot -TimeoutSeconds 1800 -LogPath $logPath
            $image=$tag
        }
        $info=Get-QuietCiVerifiedImage -Plan $Plan -Reference $image -ContainerRuntime $ContainerRuntime
        if($PublishCache -and !$cacheHit){
            if(!$token){throw 'CiRegistryCredentialMissing'}
            $digestFile=Join-Path $directory registry.digest
            if($ContainerRuntime -eq 'podman'){
                $null=Invoke-WorkspaceNative podman (@('push')+$auth+@('--digestfile',$digestFile,$tag,'docker://'+$tag)) $WorkspaceRoot -TimeoutSeconds 600 -LogPath $logPath
                $digest=(Get-Content $digestFile -Encoding utf8 -Raw).Trim()
            }else{
                $env:DOCKER_CONFIG=$authDirectory
                $null=Invoke-WorkspaceNative docker @('push',$tag) $WorkspaceRoot -TimeoutSeconds 600 -LogPath $logPath
                $digest=Get-QuietCiRegistryDigest $Plan $token $env:GITHUB_ACTOR
            }
            if($digest -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'CiImagePushReceiptInvalid'}
        }
        if(!$dockerfilePath){$dockerfilePath=if($Plan.PSObject.Properties.Match('Dockerfile').Count){$Plan.Dockerfile}else{$null}}
        $receipt=[pscustomobject]@{Image=$info.Id;RuntimeIdentifier=$Plan.Rid;Fingerprint=$Plan.Fingerprint;Base=$Plan.Base;Registry=$tag;RegistryDigest=$digest;CacheHit=$cacheHit;Published=([bool]$PublishCache -and !$cacheHit);RunnerArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();Dockerfile=$dockerfilePath;LogPath=$logPath}
        Write-WorkspaceJson (Join-Path $directory image.json) $receipt
        Write-Host ('CI image selection: '+($receipt|Select-Object Image,RuntimeIdentifier,Fingerprint,RegistryDigest,CacheHit,Published|ConvertTo-Json -Compress))
        return $receipt
    }finally{
        $env:DOCKER_CONFIG=$previousDockerConfig
        $token=$null
        if($authDirectory){foreach($name in @('auth.json','config.json')){$authFile=Join-Path $authDirectory $name;if([IO.File]::Exists($authFile)){[IO.File]::Delete($authFile)}};[IO.Directory]::Delete($authDirectory)}
    }
}
