#requires -Version 7.6
<#
.SYNOPSIS
Resolves verified digests and emits disjoint GitHub container and non-publishing Docker matrices.
.PARAMETER WorkspaceRoot
Selected checkout, including shared recipe and consumer image declarations.
.PARAMETER Suite
Core uses its toolchain image; Git/All use the declared Git consumer image.
.PARAMETER OutputPath
GitHub output file, normally GITHUB_OUTPUT.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Core','Git','All')][string]$Suite='All',[string]$OutputPath=$env:GITHUB_OUTPUT)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1');. (Join-Path $PSScriptRoot 'CiImages.ps1');. (Join-Path $PSScriptRoot 'GitHubCi.ps1')
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Resolve registry image identities and write GitHub matrix outputs')){return}
$images=@(foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){
    $plan=if($Suite -eq 'Core'){& (Join-Path $PSScriptRoot 'New-CiImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $rid -PlanOnly}else{& (Join-Path $PSScriptRoot 'New-CiModuleImage.ps1') -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $rid -Module Git -PlanOnly}
    $identity=Get-QuietCiRegistryDigest $plan $env:QUIETCLI_REGISTRY_TOKEN $env:GITHUB_ACTOR -IncludeConfiguration
    [pscustomobject]@{Rid=$rid;Platform=$plan.Platform;Runner=$(if($rid.EndsWith('arm64')){'ubuntu-24.04-arm'}else{'ubuntu-latest'});Reference=$(if($identity){$identity.Reference}else{$null})}
})
$matrix=Get-GitHubCiExecutionMatrix $images
Write-WorkspaceJson (Join-Path $WorkspaceRoot 'artifacts/github-matrix/selection.json') $matrix
if(!$OutputPath){throw 'GitHubOutputPathRequired'}
$values="container_matrix=$($matrix.Container|ConvertTo-Json -Depth 5 -Compress)`nfallback_matrix=$($matrix.Fallback|ConvertTo-Json -Depth 5 -Compress)`nhas_container=$($matrix.HasContainer.ToString().ToLowerInvariant())`nhas_fallback=$($matrix.HasFallback.ToString().ToLowerInvariant())`n"
[void][IO.File]::AppendAllTextAsync($OutputPath,$values,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
Write-Host ('GitHub Linux selection: '+($matrix|ConvertTo-Json -Depth 5 -Compress))
