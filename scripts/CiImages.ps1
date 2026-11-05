# Objectif : Définir les entrées vérifiées et l’identité du cache des images de tests Linux.
function Get-QuietCiImagePlan {
    <#
    .SYNOPSIS
    Resolves one native Linux test image without running a tool or accessing a registry.
    .PARAMETER WorkspaceRoot
    Monorepo containing the reviewed image and upstream source locks.
    .PARAMETER RuntimeIdentifier
    Exact guest architecture and libc to test.
    #>
    param([string]$WorkspaceRoot,[ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier)
    $lock=Get-Content (Join-Path $WorkspaceRoot 'build/ci-images.lock.json') -Encoding utf8 -Raw|ConvertFrom-Json
    $sdk=(Get-Content (Join-Path $WorkspaceRoot global.json) -Encoding utf8 -Raw|ConvertFrom-Json).sdk.version
    if($lock.SchemaVersion -ne 1 -or $lock.SDK -cne $sdk){throw 'CiImageSdkLockMismatch'}
    $entries=@($lock.Platforms|Where-Object Rid -CEQ $RuntimeIdentifier)
    if($entries.Count -ne 1){throw 'CiImageTargetNotUnique'}
    $target=$entries[0]
    $architecture=if($RuntimeIdentifier.EndsWith('arm64')){'arm64'}else{'x64'}
    $platform=if($RuntimeIdentifier.StartsWith('linux-musl-')){'alpine'}else{'debian'}
    if($target.Architecture -cne $architecture -or $target.Platform -cne $platform){throw 'CiImageTargetMismatch'}
    if($target.Base -cnotmatch '^docker\.io/library/(alpine|debian):[a-z0-9.-]+@sha256:[a-f0-9]{64}$' -or $target.SDK_SHA512 -cnotmatch '^[a-f0-9]{128}$'){throw 'CiImageDigestInvalid'}
    $recipe=Get-Content (Join-Path $WorkspaceRoot ".github/containers/Dockerfile.ci.$platform") -Encoding utf8 -Raw
    if(!$recipe.Contains('FROM '+$target.Base+' AS tools') -or !$recipe.Contains('FROM '+$target.Base+' AS ci')){throw 'CiImageBaseLockMismatch'}
    $gitLock=Get-Content (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/UpstreamSources.json') -Encoding utf8 -Raw|ConvertFrom-Json
    $git=@($gitLock.Sources|Where-Object Version -CEQ $lock.GitVersion)
    if($git.Count -ne 1 -or $git[0].SHA256 -notmatch '^[a-fA-F0-9]{64}$' -or $git[0].URL -cne ('https://codeload.github.com/git/git/tar.gz/refs/tags/v'+$lock.GitVersion)){throw 'CiImageGitSourceInvalid'}
    $arguments=[ordered]@{
        SDK_URL="https://builds.dotnet.microsoft.com/dotnet/Sdk/$sdk/dotnet-sdk-$sdk-$RuntimeIdentifier.tar.gz"
        SDK_SHA512=$target.SDK_SHA512
        GIT_URL=$git[0].URL
        GIT_SHA256=$git[0].SHA256
    }
    if($platform -eq 'debian'){
        if($target.PowerShell -cnotmatch '^7\.[6-9]\.\d+$' -or $target.PowerShell_SHA256 -cnotmatch '^[a-f0-9]{64}$'){throw 'CiImagePowerShellLockInvalid'}
        $arguments.POWERSHELL_URL="https://github.com/PowerShell/PowerShell/releases/download/v$($target.PowerShell)/powershell-$($target.PowerShell)-linux-$architecture.tar.gz"
        $arguments.POWERSHELL_SHA256=$target.PowerShell_SHA256
    }else{
        if($lock.AlpinePowerShellPackage -cnotmatch '^7\.[6-9]\.\d+-r\d+$'){throw 'CiImagePowerShellLockInvalid'}
        $arguments.POWERSHELL_PACKAGE=$lock.AlpinePowerShellPackage
    }
    $paths=@('build/ci-images.lock.json','global.json','scripts/CiImages.ps1','scripts/New-CiImage.ps1','FrenchExDev2.QuietCli.Git.PoSh/metadata/locks/UpstreamSources.json')
    $paths+=@(Get-ChildItem (Join-Path $WorkspaceRoot '.github/containers') -File -Force|ForEach-Object {'.github/containers/'+$_.Name})
    [string[]]$lines=@($paths|ForEach-Object {$_+' '+(Get-FileHash (Join-Path $WorkspaceRoot $_) -Algorithm SHA256).Hash})
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    $fingerprint=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).ToLowerInvariant()
    [pscustomobject]@{Rid=$RuntimeIdentifier;Architecture=$architecture;Platform=$platform;Base=$target.Base;Dockerfile=".github/containers/Dockerfile.ci.$platform";Arguments=$arguments;Fingerprint=$fingerprint;RegistryPath="frenchexdev2/quietcli2-ci-$platform-$architecture";Source='https://github.com/FrenchExDev2/FrenchExDev2.QuietCli.PoSh'}
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
    #>
    param($Plan,[AllowEmptyString()][string]$Token,[string]$Actor)
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
            return $digest
        }finally{$response.Dispose()}
    }finally{$client.Dispose()}
}
