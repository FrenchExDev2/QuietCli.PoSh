# Objectif : Réutiliser le cache GHCR ou construire une image native et la publier uniquement depuis main.
#requires -Version 7.6
<#
.SYNOPSIS
Builds native multi-stage test images; optional GHCR cache uses a content fingerprint, then pulls by digest.
.PARAMETER RuntimeIdentifier
Native Linux RID selected by the GitHub runner matrix.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER RegistryCache
Read the GHCR cache with the optional ephemeral QUIETCLI_REGISTRY_TOKEN credential.
.PARAMETER PublishCache
Publish a missing cache entry. Restricted to the upstream main push/manual workflow, never pull requests.
.PARAMETER PlanOnly
Resolve inputs offline without executing a binary or reading credentials.
#>
[CmdletBinding()]param([Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$RegistryCache,[switch]$PublishCache,[switch]$PlanOnly)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1);. (Join-Path $PSScriptRoot CiImages.ps1)
$plan=Get-QuietCiImagePlan $WorkspaceRoot $RuntimeIdentifier
if($PlanOnly){return $plan}
if(!$IsLinux -or [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant() -cne $plan.Architecture){throw 'NativeLinuxImageBuildRequired'}
if($PublishCache -and (!$RegistryCache -or $env:GITHUB_REPOSITORY -cne 'FrenchExDev2/FrenchExDev2.QuietCli.PoSh' -or $env:GITHUB_REF -cne 'refs/heads/main' -or $env:GITHUB_EVENT_NAME -cnotin @('push','workflow_dispatch'))){throw 'CiImagePublicationNotAuthorizedForThisEvent'}
$directory=Join-Path $WorkspaceRoot ('artifacts/ci-images/'+$RuntimeIdentifier+'-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$token=$env:QUIETCLI_REGISTRY_TOKEN
# Keep credentials out of all child environments, build arguments, reports and image layers.
Remove-Item Env:QUIETCLI_REGISTRY_TOKEN -ErrorAction SilentlyContinue
$authDirectory=$null;$auth=@();$digest=$null;$cacheHit=$false
$registry='ghcr.io/'+$plan.RegistryPath;$tag=$registry+':'+$plan.Fingerprint
try{
    if($RegistryCache){$digest=Get-QuietCiRegistryDigest $plan $token $env:GITHUB_ACTOR}
    if($token -and ($digest -or $PublishCache)){
        $authDirectory=Join-Path ([IO.Path]::GetTempPath()) ('quietcli2-registry-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($authDirectory,[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
        $auth=@('--authfile',(Join-Path $authDirectory auth.json))
        $login=Invoke-CiProcess -FilePath podman -ArgumentList (@('login')+$auth+@('--username',$env:GITHUB_ACTOR,'--password-stdin','ghcr.io')) -InputText $token -TimeoutSeconds 45 -OnOutput {param($e,$s)}
        if($login.Outcome -ne 'Success'){throw 'CiRegistryLoginFailed'}
    }
    if($digest){
        $null=Invoke-WorkspaceNative podman (@('pull')+$auth+@($registry+'@'+$digest)) $WorkspaceRoot -TimeoutSeconds 600
        $image=$registry+'@'+$digest;$cacheHit=$true
    }else{
        $null=Invoke-WorkspaceNative podman @('pull',$plan.Base) $WorkspaceRoot -TimeoutSeconds 300
        $arguments=@('build','--pull=never','--jobs','1','--label',('org.opencontainers.image.source='+$plan.Source),'--label',('org.frenchexdev.quietcli2.inputs='+$plan.Fingerprint),'-f',(Join-Path $WorkspaceRoot $plan.Dockerfile),'-t',$tag)
        foreach($entry in $plan.Arguments.GetEnumerator()){$arguments+=@('--build-arg',($entry.Key+'='+$entry.Value))}
        $arguments+=Join-Path $WorkspaceRoot '.github/containers'
        $null=Invoke-WorkspaceNative podman $arguments $WorkspaceRoot -TimeoutSeconds 1800
        $image=$tag
    }
    $observed=@{Json=[Text.StringBuilder]::new()}
    $inspection=Invoke-CiProcess -FilePath podman -ArgumentList @('image','inspect',$image) -TimeoutSeconds 30 -State $observed -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Json.Append($e.Text)}}
    if($inspection.Outcome -ne 'Success'){throw 'CiImageInspectionFailed'}
    $info=@($observed.Json.ToString()|ConvertFrom-Json)[0]
    $expected=if($plan.Architecture -eq 'x64'){'amd64'}else{'arm64'}
    if($info.Architecture -cne $expected -or $info.Os -cne 'linux' -or $info.Labels.'org.frenchexdev.quietcli2.inputs' -cne $plan.Fingerprint -or $info.Labels.'org.opencontainers.image.source' -cne $plan.Source){throw 'CiImageIdentityMismatch'}
    if($PublishCache -and !$cacheHit){
        if(!$token){throw 'CiRegistryCredentialMissing'}
        $digestFile=Join-Path $directory registry.digest
        $null=Invoke-WorkspaceNative podman (@('push')+$auth+@('--digestfile',$digestFile,$tag,'docker://'+$tag)) $WorkspaceRoot -TimeoutSeconds 600
        $digest=(Get-Content $digestFile -Encoding utf8 -Raw).Trim()
        if($digest -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'CiImagePushReceiptInvalid'}
    }
    $receipt=[pscustomobject]@{Image=$info.Id;RuntimeIdentifier=$RuntimeIdentifier;Fingerprint=$plan.Fingerprint;Base=$plan.Base;Registry=$tag;RegistryDigest=$digest;CacheHit=$cacheHit;Published=([bool]$PublishCache -and !$cacheHit);RunnerArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();Dockerfile=$plan.Dockerfile}
    Write-WorkspaceJson (Join-Path $directory image.json) $receipt
    return $receipt
}finally{
    if($authDirectory){$authFile=Join-Path $authDirectory auth.json;if([IO.File]::Exists($authFile)){[IO.File]::Delete($authFile)};[IO.Directory]::Delete($authDirectory)}
    $token=$null
}
