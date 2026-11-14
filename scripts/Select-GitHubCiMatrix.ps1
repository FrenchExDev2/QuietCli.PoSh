#requires -Version 7.6
<#
.SYNOPSIS
Resolves verified digests and emits disjoint GitHub container and non-publishing Docker matrices.
.PARAMETER WorkspaceRoot
Selected checkout, including shared recipe and consumer image declarations.
.PARAMETER Suite
Suite whose image requirements are declared in build/companions.yml.
.PARAMETER OutputPath
GitHub output file, normally GITHUB_OUTPUT.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$Suite='All',[string]$OutputPath=$env:GITHUB_OUTPUT)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop;Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop;Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/GitHubCi.psm1')) -DisableNameChecking -ErrorAction Stop
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Resolve registry image identities and write GitHub matrix outputs')){return}
$images=@(foreach($rid in @('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){
    $plan=& ([IO.Path]::Combine($PSScriptRoot,'New-CiSuiteImage.ps1')) -WorkspaceRoot $WorkspaceRoot -RuntimeIdentifier $rid -Suite $Suite -PlanOnly
    $identity=Get-QuietCiRegistryDigest $plan $env:QUIETCLI_REGISTRY_TOKEN $env:GITHUB_ACTOR -IncludeConfiguration
    [pscustomobject]@{Rid=$rid;Platform=$plan.Platform;Runner=$(if($rid.EndsWith('arm64')){'ubuntu-24.04-arm'}else{'ubuntu-latest'});Reference=$(if($identity){$identity.Reference}else{$null})}
})
$matrix=Get-GitHubCiExecutionMatrix $images
Write-WorkspaceJson ([IO.Path]::Combine($WorkspaceRoot,'artifacts/github-matrix/selection.json')) $matrix
if(!$OutputPath){throw 'GitHubOutputPathRequired'}
$values="container_matrix=$($matrix.Container|ConvertTo-Json -Depth 5 -Compress)`ndocker_matrix=$($matrix.Fallback|ConvertTo-Json -Depth 5 -Compress)`nhas_container=$($matrix.HasContainer.ToString().ToLowerInvariant())`nhas_docker_container_runtime=$($matrix.HasFallback.ToString().ToLowerInvariant())`n"
[void][IO.File]::AppendAllTextAsync($OutputPath,$values,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
Write-Host ('GitHub Linux selection: '+($matrix|ConvertTo-Json -Depth 5 -Compress))
