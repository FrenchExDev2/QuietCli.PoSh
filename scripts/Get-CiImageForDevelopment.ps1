#requires -Version 7.6
<#
.SYNOPSIS
Pulls an already-published, cache-verified CI test image by its locked digest, for use from any host OS.

.DESCRIPTION
New-CiImage.ps1 refuses to run anywhere except a matching native Linux runner, because its build path produces
the image this repository trusts as a qualification input. A developer's own machine (frequently Windows or
macOS) is never meant to build that image, but it can still legitimately *pull* one the CI pipeline already
published and digest-pinned, the same way `podman pull` by digest works from any host with a working Podman
engine. This script is that narrower, host-independent read path: it resolves the locked plan, resolves the
GHCR digest for the current source fingerprint, and pulls by digest only — it never builds, never pushes, and
never falls back to an unpinned tag. If nothing is cached yet for this fingerprint, it fails with an actionable
error instead of silently building (which would defeat the point of staying off the native-Linux build path).

.PARAMETER RuntimeIdentifier
Exact guest architecture and libc to test.

.PARAMETER WorkspaceRoot
QuietCli2 monorepo root.

.PARAMETER RegistryToken
Optional GHCR read token; anonymous pulls are attempted when omitted, which is sufficient for a public package.

.OUTPUTS
A receipt matching New-CiImage.ps1's shape (Image/RuntimeIdentifier/Fingerprint/Registry/RegistryDigest/CacheHit).

.EXAMPLE
$image = ./scripts/Get-CiImageForDevelopment.ps1 -RuntimeIdentifier linux-x64
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [Parameter(Mandatory)][ValidateSet('linux-x64', 'linux-arm64', 'linux-musl-x64', 'linux-musl-arm64')][string]$RuntimeIdentifier,
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [AllowEmptyString()][string]$RegistryToken = $env:QUIETCLI_REGISTRY_TOKEN
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Get-CiImageForDevelopment')){return}
$ErrorActionPreference = 'Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop

$plan = Get-QuietCiImagePlan $WorkspaceRoot $RuntimeIdentifier
$digest = Get-QuietCiRegistryDigest $plan $RegistryToken 'quietcli2-developer'
if (-not $digest) { throw "CiImageNotCachedForDevelopment: no published image matches this source fingerprint ($($plan.Fingerprint)) for $RuntimeIdentifier yet. Run .github/workflows/ci.yml's linux-images job (or New-CiImage.ps1 on a native Linux host) first, or wait for main to publish one." }
$registry = 'ghcr.io/' + $plan.RegistryPath
$reference = $registry + '@' + $digest
$null = Invoke-WorkspaceNative podman @('pull', $reference) $WorkspaceRoot -TimeoutSeconds 600

$observed = @{ Json = [Text.StringBuilder]::new() }
$inspection = Invoke-CiProcess -FilePath podman -ArgumentList @('image', 'inspect', $reference) -TimeoutSeconds 30 -State $observed -OnOutput { param($e, $s) if ($e.Stream -eq 'stdout') { [void]$s.Json.Append($e.Text) } }
if ($inspection.Outcome -ne 'Success') { throw 'CiImageInspectionFailed' }
$info = @($observed.Json.ToString() | ConvertFrom-Json)[0]
$expected = if ($plan.Architecture -eq 'x64') { 'amd64' } else { 'arm64' }
if ($info.Architecture -cne $expected -or $info.Os -cne 'linux' -or $info.Labels.'org.frenchexdev.quietcli2.inputs' -cne $plan.Fingerprint -or $info.Labels.'org.opencontainers.image.source' -cne $plan.Source) { throw 'CiImageIdentityMismatch' }

[pscustomobject]@{ Image = $info.Id; RuntimeIdentifier = $RuntimeIdentifier; Fingerprint = $plan.Fingerprint; Base = $plan.Base; Registry = $registry; RegistryDigest = $digest; CacheHit = $true; Published = $false; RunnerArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString(); Dockerfile = $null }
