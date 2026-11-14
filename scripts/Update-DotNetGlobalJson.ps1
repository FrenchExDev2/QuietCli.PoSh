#Requires -Version 7.6
<#
.SYNOPSIS
Verifies an SDK, backs up global.json and updates its SDK selection settings.
.DESCRIPTION
Accepts exact paths only and preserves unrelated JSON values. WhatIf performs no
HTTP/native calls or writes. See README-dotnet-and-global-dot-json.md for the full contract.
.PARAMETER Path
Exact global.json files; defaults to this checkout's root global.json.
.PARAMETER Version
Complete SDK version; omit to resolve the latest eligible published SDK.
.PARAMETER Channel
Expected release channel, default 11.0.
.PARAMETER Preleases
Permit preview/RC SDKs and set allowPrerelease to true.
.PARAMETER RollForward
Optional replacement; preserves the existing policy when omitted.
.PARAMETER SdkDirectory
Optional portable SDK search directory, written as a relative sdk.paths entry.
.PARAMETER DotNetPath
Exact host used to verify the installed SDK, default dotnet from PATH.
.PARAMETER SkipInstalledCheck
Explicitly permit pin preparation without local installation verification.
.PARAMETER Create
Permit creation of an explicitly named missing global.json.
.PARAMETER AllowDowngrade
Permit lowering an existing SDK pin.
.PARAMETER QuietCliRoot
Selected checkout providing independent process infrastructure.
.EXAMPLE
./scripts/Update-DotNetGlobalJson.ps1 -Version 11.0.100 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
param([string[]]$Path,[string]$Version,[string]$Channel='11.0',
    [Alias('Prerelease','Prereleases')][switch]$Preleases,[string]$RollForward,
    [string]$SdkDirectory,[string]$DotNetPath='dotnet',[switch]$SkipInstalledCheck,
    [switch]$Create,[switch]$AllowDowngrade,[string]$QuietCliRoot)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/DotNetProvisioning.psm1')) -ErrorAction Stop -DisableNameChecking
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Verify the selected SDK and update exact global.json targets')){return}
$invocation=@{}+$PSBoundParameters
$invocation.Confirm=$false
Update-DotNetGlobalJson @invocation
