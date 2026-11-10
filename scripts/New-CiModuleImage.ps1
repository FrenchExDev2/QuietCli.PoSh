#requires -Version 7.6
<#
.SYNOPSIS
Builds a Core-consumer module's own derived Podman image, from the module's own Containerfile and locks.
.DESCRIPTION
Resolves (and, if needed, builds) Core's own image first, tags it locally under a reference keyed by
Core's own verified fingerprint so it can serve as a Containerfile FROM target, then builds the module's
image on top of it. Core is never read beyond its own resolved plan; the module supplies its own fetch
script under .github/containers/ and its own metadata/locks/, and declares them plus its Containerfile
fragment through ci/Get-CiImageArguments.ps1 -- a plain script, invoked directly (not dot-sourced) at
this exact same relative path for every Core-consumer module, no module-name-derived function to guess.
Core itself renders the actual Containerfile text from that fragment (Get-QuietModuleContainerfile) --
the module never authors one by hand.
.PARAMETER Module
Core-consumer module name (for example 'Git'), matching the FrenchExDev2.QuietCli.<Module>.PoSh directory.
.PARAMETER RuntimeIdentifier
Native Linux RID selected by the GitHub runner matrix.
.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.
.PARAMETER RegistryCache
Read the GHCR cache (for both Core and the module) with the optional ephemeral QUIETCLI_REGISTRY_TOKEN credential.
.PARAMETER PublishCache
Publish a missing module cache entry. Core's own cache is never published from here; that stays the
exclusive responsibility of the linux-images job calling New-CiImage.ps1 directly.
.PARAMETER PlanOnly
Resolve inputs offline without executing a binary or reading credentials.
.PARAMETER ContainerRuntime
Explicit selection overrides the checkout dotenv key; absent configuration uses Podman-first application discovery on Windows and Linux.
#>
[CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$Module,[Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$RegistryCache,[switch]$PublishCache,[switch]$PlanOnly,[AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime)
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot Common.ps1);. (Join-Path $PSScriptRoot CiImages.ps1)
$moduleRoot="FrenchExDev2.QuietCli.$Module.PoSh"
$moduleContractPath="$moduleRoot/ci/Get-CiImageArguments.ps1"
$moduleScript=Join-Path $WorkspaceRoot $moduleContractPath
if(!(Test-Path -LiteralPath $moduleScript)){throw "CiModuleContractMissing: $moduleContractPath"}
$core=Get-QuietCiImagePlan $WorkspaceRoot $RuntimeIdentifier
$moduleInputs=& $moduleScript -WorkspaceRoot $WorkspaceRoot -Platform $core.Platform
$moduleInputPaths=@($moduleInputs.InputPaths)+@($moduleContractPath)
$plan=Get-QuietCiModuleImagePlan $WorkspaceRoot $RuntimeIdentifier $Module $moduleInputs.Containerfile $moduleInputs.Arguments $moduleInputPaths
if($PlanOnly){return $plan}
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: New-CiModuleImage')){return}

$ContainerRuntime=Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -WorkspaceRoot $WorkspaceRoot
$registryCredential=$env:QUIETCLI_REGISTRY_TOKEN
try{$coreImage=& (Join-Path $PSScriptRoot 'New-CiImage.ps1') -RuntimeIdentifier $RuntimeIdentifier -WorkspaceRoot $WorkspaceRoot -RegistryCache:$RegistryCache -ContainerRuntime $ContainerRuntime}
finally{$env:QUIETCLI_REGISTRY_TOKEN=$registryCredential;$registryCredential=$null}
# A bare image ID cannot be a Dockerfile FROM target; this local tag, keyed by Core's own verified
# fingerprint, works whether that image just arrived by a GHCR pull-by-digest or a fresh local build.
$coreTag="localhost/quietcli2-ci-core-$($core.Platform)-$($core.Architecture):$($core.Fingerprint)"
$null=Invoke-WorkspaceNative $ContainerRuntime @('tag',$coreImage.Image,$coreTag) $WorkspaceRoot -TimeoutSeconds 30
$plan.Arguments.CORE_IMAGE=$coreTag
Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory (Join-Path $WorkspaceRoot $moduleRoot '.github/containers') -WorkspaceRoot $WorkspaceRoot -ArtifactPrefix ($Module.ToLowerInvariant()+'-'+$RuntimeIdentifier) -RegistryCache:$RegistryCache -PublishCache:$PublishCache -ContainerRuntime $ContainerRuntime
