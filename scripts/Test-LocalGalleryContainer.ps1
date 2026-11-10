#requires -Version 7.6
<#
.SYNOPSIS
Explicit exploratory localhost NuGet/PSResource container compatibility probe.
.PARAMETER Image
Selected BaGet server image; may be pulled, resolved and recorded.
.PARAMETER LinuxClientImage
Existing local Linux client image with PowerShell and PSResourceGet.
.PARAMETER RunDirectory
New external reports directory.
.PARAMETER DependencyStrategy
Explicit Automatic or PinnedClosure preview dependency strategy.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Image,[Parameter(Mandatory)][string]$LinuxClientImage,
    [ValidateSet('Automatic','PinnedClosure')][string]$DependencyStrategy='Automatic',[string]$RunDirectory)
Import-Module (Join-Path $PSScriptRoot 'lib/LocalGallery.Probe.psm1') -ErrorAction Stop
LocalGallery.Probe\Test-LocalGalleryContainer @PSBoundParameters
