#requires -Version 7.6
<#
.SYNOPSIS
Exports or installs the repository's VS Code/Insiders extension inventory.
.DESCRIPTION
Default mode installs missing listed extensions. Update ensures their latest versions without
updating unrelated extensions. Export saves the selected editor's installed identifiers, versions
and prerelease preferences. WhatIf starts no editor process and writes no file.
.PARAMETER Insiders
Selects VS Code Insiders; Stable is the default.
.PARAMETER Export
Captures the selected channel into the inventory file instead of installing extensions.
.PARAMETER Update
Installs or updates every listed extension through --install-extension ID --force.
.PARAMETER Path
Inventory path, defaulting to build/vscode-extensions.json in this repository.
.PARAMETER EditorPath
Explicit Code.exe, Code - Insiders.exe or Linux code/code-insiders CLI.
.PARAMETER AdditionalExtension
Additional required IDs, used by workstation setup.
.EXAMPLE
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Export
.EXAMPLE
./scripts/Sync-DevelopmentEditorExtensions.ps1 -Insiders -Update -WhatIf
#>
[CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Sync')]
param(
    [switch]$Insiders,
    [Parameter(Mandatory,ParameterSetName='Export')][switch]$Export,
    [Parameter(ParameterSetName='Sync')][switch]$Update,
    [string]$Path=(Join-Path (Split-Path $PSScriptRoot -Parent) 'build/vscode-extensions.json'),
    [string]$EditorPath,
    [Parameter(ParameterSetName='Sync')][string[]]$AdditionalExtension=@()
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/EditorExtensions.psm1')
$cli=if($WhatIfPreference){[pscustomobject]@{Channel=$(if($Insiders){'Insiders'}else{'Stable'})}}else{Resolve-DevelopmentEditorCli -Insiders:$Insiders -EditorPath $EditorPath}
$caller=$PSCmdlet
$apply={param($target,$action)$caller.ShouldProcess($target,$action)}.GetNewClosure()
if($Export){Export-EditorExtensionManifest $cli $Path $apply;return}
$entries=@(Read-EditorExtensionManifest $Path)
$report=Sync-EditorExtensionManifest $cli $entries -AdditionalExtension $AdditionalExtension -Update:$Update -ShouldApply $apply -Preview:$WhatIfPreference
$report
if($report.Failed){throw ('EditorExtensionSynchronizationFailed: '+(($report.Results|Where-Object State -EQ Failed|ForEach-Object {$_.Id+': '+$_.Error}) -join '; '))}
