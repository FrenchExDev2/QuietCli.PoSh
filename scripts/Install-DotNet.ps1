#Requires -Version 7.6
<#
.SYNOPSIS
Installs the SDK with its runtimes, optionally pulls images and updates SDK pins.
.DESCRIPTION
Installs a SHA-512-verified portable SDK in its own version directory. See
README-dotnet-and-global-dot-json.md for parameters, scope and complete examples.
.PARAMETER Channel
Release channel, default 11.0.
.PARAMETER Version
Exact published SDK version, or latest eligible when omitted.
.PARAMETER Preleases
Include preview and RC releases.
.PARAMETER InstallRoot
Parent for version directories, default this checkout's .dotnet.
.PARAMETER UpdateGlobalJson
Back up and update the exact GlobalJsonPath files after successful installation.
.PARAMETER GlobalJsonPath
Exact files; defaults to this checkout's root global.json.
.PARAMETER PullImages
Pull all four official dotnet image types using shared container configuration.
.PARAMETER ContainerRuntime
Optional docker/podman override; otherwise checkout dotenv and discovery apply.
.PARAMETER Platform
Container platforms to pull; default linux/amd64.
.PARAMETER ImageVariant
Optional tag suffix, for example alpine.
.PARAMETER ActivateSession
Set PATH and DOTNET_ROOT for this PowerShell process only.
.PARAMETER AllowDowngrade
Permit lowering an existing SDK pin.
.PARAMETER DownloadTimeoutSeconds
Maximum archive download duration; default 900 seconds.
.PARAMETER QuietCliRoot
Selected checkout providing independent process and runtime-resolution helpers.
.EXAMPLE
./scripts/Install-DotNet.ps1 -UpdateGlobalJson -WhatIf
.EXAMPLE
./scripts/Install-DotNet.ps1 -UpdateGlobalJson -PullImages -ContainerRuntime podman -Confirm
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string]$Channel='11.0',[string]$Version,[Alias('Prerelease','Prereleases')][switch]$Preleases,
    [string]$InstallRoot,[switch]$UpdateGlobalJson,[string[]]$GlobalJsonPath,
    [switch]$PullImages,[ValidateSet('docker','podman')][string]$ContainerRuntime,
    [string[]]$Platform,[string]$ImageVariant,[switch]$ActivateSession,[switch]$AllowDowngrade,
    [int]$DownloadTimeoutSeconds=900,[string]$QuietCliRoot)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/DotNetProvisioning.psm1')) -ErrorAction Stop -DisableNameChecking
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Install the selected SDK and explicitly requested optional effects')){return}
$invocation=@{}+$PSBoundParameters
$invocation.Confirm=$false
Install-DotNetEnvironment @invocation
