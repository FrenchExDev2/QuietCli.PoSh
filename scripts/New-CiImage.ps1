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
Invoke-QuietCiImageBuild -Plan $plan -ContextDirectory (Join-Path $WorkspaceRoot '.github/containers') -WorkspaceRoot $WorkspaceRoot -ArtifactPrefix $RuntimeIdentifier -RegistryCache:$RegistryCache -PublishCache:$PublishCache
