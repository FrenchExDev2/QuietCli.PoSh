#requires -Version 7.6
#requires -PSEdition Core
<#
.SYNOPSIS
Runs a PowerShell block with the checkout's local QuietCli Core module.
.DESCRIPTION
Imports the exact local Core manifest into script scope without rebuilding or forcing
a reload. The block runs in the current process, can call quiet, and receives a local
orchestration context with fresh Data and State hashtables unless Runtime is supplied.
This context is separate from the native runtime passed to Output/Complete callbacks.
Pipeline output and terminating errors from Code are passed to the caller unchanged.
WhatIf skips both module import and block execution.
.PARAMETER Code
PowerShell block invoked once with Runtime as its first positional argument.
.PARAMETER Runtime
Optional non-null caller-owned context, passed by reference without serialization.
.EXAMPLE
./scripts/Invoke-Quiet.ps1 -Code {
    param($runtime)
    $runtime.Data.Result = quiet -AsObject -Complete { param($native) $native.Data } dotnet --version
    $runtime.Data.Result
}
Returns the native result object. Supply an Output callback to analyze native output.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateNotNull()][scriptblock]$Code,
    [ValidateNotNull()][object]$Runtime = [pscustomobject]@{ Data = @{}; State = @{} }
)

if (!$PSCmdlet.ShouldProcess($PSCommandPath, 'Import local QuietCli Core and execute Code')) { return }
$ErrorActionPreference = 'Stop'
$moduleName = 'FrenchExDev2.QuietCli.Core.PoSh'
$moduleDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) $moduleName
$expectedPath = [IO.Path]::GetFullPath((Join-Path $moduleDirectory ($moduleName + '.psm1')))
foreach ($loaded in Get-Module -Name $moduleName -All) {
    if ($loaded.Path -ne $expectedPath) {
        throw "QuietLocalModuleConflict: start a fresh PowerShell session; loaded $($loaded.Path), expected $expectedPath"
    }
}
# Reimporting without Force exposes the matching module's exports in this script scope.
$localModule = Import-Module (Join-Path $moduleDirectory ($moduleName + '.psd1')) -Scope Local -PassThru -ErrorAction Stop
if ($localModule.Path -ne $expectedPath) { throw 'QuietLocalModulePathMismatch' }
& $Code $Runtime
