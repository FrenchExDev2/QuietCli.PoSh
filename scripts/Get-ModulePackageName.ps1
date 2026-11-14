#requires -Version 7.6
<#
.SYNOPSIS
Reads the package name from a .psm1 filename and checks its optional sibling manifest without importing code.
.PARAMETER Path
Existing script module; its basename is the PowerShell package identity.
.PARAMETER AsObject
Returns name, complete version, paths and declared dependencies instead of the name alone.
.PARAMETER RequireManifest
Requires a literal sibling manifest with a matching RootModule and optional PackageName declaration.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Path,[switch]$AsObject,[switch]$RequireManifest)
if(!$PSCmdlet.ShouldProcess($Path,'Read module package identity without executing module code')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ModulePackage.psm1')) -DisableNameChecking
$identity=Get-QuietModulePackageIdentity -Path $Path -RequireManifest:$RequireManifest
if($AsObject){$identity}else{$identity.Name}
