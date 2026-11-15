#requires -Version 7.6
#requires -PSEdition Core
<#
.SYNOPSIS
Runs a PowerShell block with the checkout's local QuietCli Core and selected companion modules.
.DESCRIPTION
Imports the exact local Core manifest into script scope without rebuilding. ForceReload
optionally forces module reimport; imports otherwise reuse loaded modules. Selected local
companion manifests are imported after Core. The block runs in the current process, can call quiet, and receives a local
orchestration context with fresh Data and State hashtables unless Runtime is supplied.
This context is separate from the native runtime passed to Output/Complete callbacks.
Pipeline output and terminating errors from Code are passed to the caller unchanged.
WhatIf skips both module import and block execution.
.PARAMETER Code
PowerShell block invoked once with Runtime as its first positional argument.
.PARAMETER Runtime
Optional non-null caller-owned context, passed by reference without serialization.
.PARAMETER Companion
Optional local business handlers loaded after Core. Supported values are Git and Vagrant.
.PARAMETER ForceReload
Passes Force to each selected local module import. Does not replace loaded assemblies.
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
    [ValidateNotNull()][object]$Runtime = [pscustomobject]@{ Data = @{}; State = @{} },
    [ValidateSet('Git','Vagrant')][string[]]$Companion = @(),
    [switch]$ForceReload
)

if (!$PSCmdlet.ShouldProcess($PSCommandPath, ('Import local QuietCli Core{0} and execute Code' -f $(if($Companion.Count){' with '+($Companion -join ', ')}else{''})))) { return }
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$moduleNames = [Collections.Generic.List[string]]::new()
$moduleNames.Add('FrenchExDev2.QuietCli.Core.PoSh')
foreach($name in @($Companion | Select-Object -Unique)){
    $moduleNames.Add('FrenchExDev2.QuietCli.'+$name+'.PoSh')
}
$introduced=[Collections.Generic.List[string]]::new()
$reloaded=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
if($ForceReload){
    $loadedModules=@{}
    foreach($moduleName in $moduleNames){
        $expectedPath=[IO.Path]::GetFullPath([IO.Path]::Combine($workspaceRoot,$moduleName,($moduleName+'.psm1')))
        $loadedModules[$moduleName]=@(Get-Module -Name $moduleName -All)
        foreach($loaded in $loadedModules[$moduleName]){
            if($loaded.Path -ne $expectedPath){throw "QuietLocalModuleConflict: start a fresh PowerShell session; loaded $($loaded.Path), expected $expectedPath"}
        }
    }
    # Remove dependents before Core; explicit removal also clears nested binary-module exports.
    for($index=$moduleNames.Count-1;$index -ge 0;$index--){
        foreach($loaded in $loadedModules[$moduleNames[$index]]){
            Remove-Module -ModuleInfo $loaded -Force -ErrorAction Stop
            [void]$reloaded.Add($moduleNames[$index])
        }
    }
}
try{
    foreach($moduleName in $moduleNames){
        $moduleDirectory = [IO.Path]::Combine($workspaceRoot,$moduleName)
        $expectedPath = [IO.Path]::GetFullPath(([IO.Path]::Combine($moduleDirectory,($moduleName + '.psm1'))))
        $existing=@(Get-Module -Name $moduleName -All)
        foreach ($loaded in $existing) {
            if ($loaded.Path -ne $expectedPath) {
                throw "QuietLocalModuleConflict: start a fresh PowerShell session; loaded $($loaded.Path), expected $expectedPath"
            }
        }
        # Companion RequiredModules resolve exported Core cmdlets from the process-global scope.
        # Core-only use preserves the original local-scope behavior.
        $scope=if($Companion.Count -and $moduleName -eq 'FrenchExDev2.QuietCli.Core.PoSh'){'Global'}else{'Local'}
        $imported=@(Import-Module ([IO.Path]::Combine($moduleDirectory,($moduleName + '.psd1'))) -Scope $scope -Force:$ForceReload -PassThru -DisableNameChecking -ErrorAction Stop)
        $localModule=@($imported|Where-Object Name -CEQ $moduleName)
        if ($localModule.Count -ne 1 -or $localModule[0].Path -ne $expectedPath) { throw ('QuietLocalModulePathMismatch: '+$moduleName) }
        if(!$existing.Count -and !$reloaded.Contains($moduleName)){$introduced.Add($moduleName)}
    }
    & $Code $Runtime
}finally{
    if($Companion.Count){
        for($index=$introduced.Count-1;$index -ge 0;$index--){
            Remove-Module -Name $introduced[$index] -Force -ErrorAction SilentlyContinue
        }
    }
}
