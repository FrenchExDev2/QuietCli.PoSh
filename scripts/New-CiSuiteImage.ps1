#requires -Version 7.6
<# .SYNOPSIS
Resolves or builds the image layers declared for a companion test suite.
.PARAMETER Suite
Declared companion or All.
.PARAMETER RuntimeIdentifier
Native Linux RID.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER PlanOnly
Returns the final image plan without executing a binary or accessing a registry.
.PARAMETER RegistryCache
Reuses checksum-verified registry images.
.PARAMETER PublishCache
Requests develop-only publication under the existing image guard.
.PARAMETER ResolveOnly
Verifies existing registry image configuration without downloading layers; builds only on a miss.
.PARAMETER ContainerRuntime
Explicit container adapter or the shared environment selection.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Suite='All',[Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$PlanOnly,[switch]$RegistryCache,[switch]$PublishCache,[switch]$ResolveOnly,[AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime)
$ErrorActionPreference='Stop'
if(!$PlanOnly -and !$PSCmdlet.ShouldProcess($WorkspaceRoot,('Prepare declared image layers for '+$Suite))){return}
Import-Module (Join-Path $PSScriptRoot 'lib/CiCompanions.psm1')
$configuration=Read-QuietCiCompanions $WorkspaceRoot
$selection=Resolve-QuietCiCompanions $configuration -Suite $Suite
if($PlanOnly){return Get-QuietCiSuiteImagePlan $WorkspaceRoot $selection $RuntimeIdentifier}
Invoke-QuietCiSuiteImage -WorkspaceRoot $WorkspaceRoot -Selection $selection -RuntimeIdentifier $RuntimeIdentifier -ContainerRuntime $ContainerRuntime -RegistryCache:$RegistryCache -PublishCache:$PublishCache -ResolveOnly:$ResolveOnly -Confirm:$false
