#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $scriptsRoot = Get-QuietTestScriptsRoot
    $harness = New-QuietTestFile ([IO.Path]::Combine($TestDrive, 'Invoke-Preview.ps1')) @'
param([string]$EntryPoint)
$ErrorActionPreference = 'Stop'
function global:New-ItemProperty { throw 'UnexpectedRegistryWrite' }
function global:Get-ItemPropertyValue { throw 'UnexpectedRegistryRead' }
function global:Add-MpPreference { throw 'UnexpectedDefenderWrite' }
function global:Get-MpPreference { throw 'UnexpectedDefenderRead' }
& $EntryPoint -WhatIf
'@
}

Describe 'Windows settings entry-point previews' {
    It 'describes the registry change without touching the registry' {
        $entryPoint = [IO.Path]::Combine($scriptsRoot, 'Enable-WindowsLongPaths.ps1')

        $result = Invoke-QuietTestScript -ScriptPath $harness -ArgumentList @($entryPoint) -TimeoutSeconds 20

        $result.ExitCode | Should -Be 0 -Because $result.Error
        $result.Output | Should -Match 'LongPathsEnabled'
    }

    It 'describes the Defender change without touching preferences' {
        $entryPoint = [IO.Path]::Combine($scriptsRoot, 'Fix-WindowsDefender.ps1')

        $result = Invoke-QuietTestScript -ScriptPath $harness -ArgumentList @($entryPoint) -TimeoutSeconds 20

        $result.ExitCode | Should -Be 0 -Because $result.Error
        $result.Output | Should -Match 'Microsoft Defender Antivirus'
    }
}
