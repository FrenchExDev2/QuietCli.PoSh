#requires -Version 7.6
<#
.SYNOPSIS
Verifies a complete package set without executing it; TestImport explicitly enables an import smoke check afterwards.
.PARAMETER PackageDirectory
Archives and manifests from a trusted source. Hashes alone do not authenticate their author.
.PARAMETER ExtractionDirectory
New destination owned by this verification.
.PARAMETER TestImport
Explicitly executes the verified Core and Git modules after every archive is verified.
.PARAMETER MaxFiles
Maximum file count across the distribution.
.PARAMETER MaxFileBytes
Maximum uncompressed size of one file.
.PARAMETER MaxTotalBytes
Maximum uncompressed distribution size.
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$ExtractionDirectory,
    [switch]$TestImport,
    [ValidateRange(1,100000)][int]$MaxFiles=10000,
    [ValidateRange(1,1073741824)][long]$MaxFileBytes=134217728,
    [ValidateRange(1,4294967296)][long]$MaxTotalBytes=536870912
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Test-WorkspacePackage.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptTestWorkspacePackage @PSBoundParameters
