#requires -Version 7.6
<#
.SYNOPSIS
Loads the verified image for a test suite from the current run's Linux image bundle.
.PARAMETER Suite
Suite whose image must be present.
.PARAMETER RuntimeIdentifier
Native Linux target.
.PARAMETER Directory
Downloaded bundle directory.
.PARAMETER Revision
Revision under test.
.PARAMETER RunId
GitHub Actions run supplying the image.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Suite,
    [Parameter(Mandatory)][ValidateSet('linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier,
    [Parameter(Mandatory)][string]$Directory,
    [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory)][ValidatePattern('\A[0-9]+\z')][string]$RunId
)
if(!$PSCmdlet.ShouldProcess($Directory,'Load the verified Linux CI image')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImages.psm1')) -DisableNameChecking -ErrorAction Stop
$plan=& ([IO.Path]::Combine($PSScriptRoot,'New-CiSuiteImage.ps1')) -Suite $Suite -RuntimeIdentifier $RuntimeIdentifier -PlanOnly
Import-QuietCiImageBundle -Directory ([IO.Path]::GetFullPath($Directory,$PWD.ProviderPath)) -Plan $plan -Revision $Revision -RunId $RunId
