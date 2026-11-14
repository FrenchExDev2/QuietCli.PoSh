#requires -Version 7.6
<#
.SYNOPSIS
Collects Linux host identity and explicitly loads verified SQLite assets inside an owned diagnostic container.
.PARAMETER OutputPath
Owned JSON report path inside the container.
.PARAMETER AssetsRoot
Read-only diagnostic input convention: RID directories and assets.json beside them.
.PARAMETER ExpectedRuntimeIdentifier
Portable target whose SQLite ABI is checked independently from the reported RID.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$AssetsRoot,
    [Parameter(Mandatory)][ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Probe-ContainerRuntime.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptProbeContainerRuntime @PSBoundParameters
