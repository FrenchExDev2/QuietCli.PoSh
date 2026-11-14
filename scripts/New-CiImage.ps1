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
Publish a missing cache entry. Restricted to the upstream develop push/manual workflow, never pull requests.
.PARAMETER PlanOnly
Resolve inputs offline without executing a binary or reading credentials.
.PARAMETER ContainerRuntime
Explicit selection overrides the checkout dotenv key; absent configuration uses Podman-first application discovery on Windows and Linux.
#>
[CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$RegistryCache,[switch]$PublishCache,[switch]$PlanOnly,[AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime)
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop;Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop
$plan=Get-QuietCiImagePlan $WorkspaceRoot $RuntimeIdentifier
if($PlanOnly){return $plan}
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: New-CiImage')){return}

$ContainerRuntime=Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -WorkspaceRoot $WorkspaceRoot
Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory ([IO.Path]::Combine($WorkspaceRoot,'.github/containers')) -WorkspaceRoot $WorkspaceRoot -ArtifactPrefix $RuntimeIdentifier -RegistryCache:$RegistryCache -PublishCache:$PublishCache -ContainerRuntime $ContainerRuntime
