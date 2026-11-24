#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $module = Import-QuietTestLibrary -Name Fix-WindowsDefender
    & $module {
        function script:Add-MpPreference {
            [CmdletBinding()]
            param([string[]]$ExclusionPath, [string[]]$ExclusionProcess, [string]$ExclusionExtension)
            throw 'UnexpectedDefenderWrite'
        }

        function script:Get-MpPreference { throw 'UnexpectedDefenderRead' }
    }
}

AfterAll {
    & $module {
        Remove-Item -LiteralPath 'Function:script:Add-MpPreference', 'Function:script:Get-MpPreference'
    }
}

Describe 'Invoke-QuietScriptFixWindowsDefender' {
    BeforeEach {
        Mock -ModuleName Fix-WindowsDefender Test-Path { $false }
        Mock -ModuleName Fix-WindowsDefender Add-MpPreference {}
        Mock -ModuleName Fix-WindowsDefender Get-MpPreference {
            [pscustomobject]@{
                ExclusionPath = @('fixture-path')
                ExclusionProcess = @('fixture-process')
                ExclusionExtension = @('vhdx')
                OtherPreference = 'not selected'
            }
        }
        $previousUserProfile = $env:USERPROFILE
        $previousLocalAppData = $env:LOCALAPPDATA
        $previousAppData = $env:APPDATA
        $env:USERPROFILE = [IO.Path]::Combine($TestDrive, 'profile[1]')
        $env:LOCALAPPDATA = [IO.Path]::Combine($TestDrive, 'local')
        $env:APPDATA = [IO.Path]::Combine($TestDrive, 'roaming')
    }

    AfterEach {
        $env:USERPROFILE = $previousUserProfile
        $env:LOCALAPPDATA = $previousLocalAppData
        $env:APPDATA = $previousAppData
    }

    It 'adds only present literal paths plus the existing process and extension defaults' {
        $expectedPaths = @(
            'C:\code'
            [IO.Path]::Combine($env:USERPROFILE, 'source', 'repos')
            [IO.Path]::Combine($env:USERPROFILE, '.nuget', 'packages')
            [IO.Path]::Combine($env:USERPROFILE, '.vscode-insiders')
            [IO.Path]::Combine($env:LOCALAPPDATA, 'npm-cache')
            [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'Microsoft VS Code Insiders')
            [IO.Path]::Combine($env:APPDATA, 'Code - Insiders')
        )
        Mock -ModuleName Fix-WindowsDefender Test-Path { $true } -ParameterFilter { $LiteralPath -in $expectedPaths }

        $result = Invoke-QuietScriptFixWindowsDefender -Confirm:$false

        Should -Invoke -ModuleName Fix-WindowsDefender Test-Path -Exactly -Times 8
        Should -Invoke -ModuleName Fix-WindowsDefender Test-Path -Exactly -Times 1 -ParameterFilter {
            $LiteralPath -ceq 'C:\Program Files\dotnet'
        }
        Should -Invoke -ModuleName Fix-WindowsDefender Add-MpPreference -Exactly -Times 1 -ParameterFilter {
            ($ExclusionPath -join '|') -ceq ($expectedPaths -join '|') -and
                ($ExclusionProcess -join '|') -ceq 'dotnet.exe|MSBuild.exe|VBCSCompiler.exe|node.exe|code.exe|Code - Insiders.exe|git.exe|codex.exe|claude.exe' -and
                $ExclusionExtension -ceq 'vhdx' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke -ModuleName Fix-WindowsDefender Get-MpPreference -Exactly -Times 1
        $result.ExclusionPath | Should -Be 'fixture-path'
        $result.ExclusionProcess | Should -Be 'fixture-process'
        $result.ExclusionExtension | Should -Be 'vhdx'
        $result.PSObject.Properties.Name | Should -Not -Contain 'OtherPreference'
    }

    It 'omits the path argument when profile variables and candidate paths are absent' {
        $env:USERPROFILE = $null
        $env:LOCALAPPDATA = $null
        $env:APPDATA = $null

        $null = Invoke-QuietScriptFixWindowsDefender -Confirm:$false

        Should -Invoke -ModuleName Fix-WindowsDefender Test-Path -Exactly -Times 2
        Should -Invoke -ModuleName Fix-WindowsDefender Add-MpPreference -Exactly -Times 1 -ParameterFilter {
            $null -eq $ExclusionPath -and $ExclusionExtension -ceq 'vhdx' -and $ExclusionProcess.Count -eq 9
        }
    }

    It 'does not query paths or touch Defender in preview' {
        $transcript = [IO.Path]::Combine($TestDrive, 'defender-preview.txt')
        Start-Transcript -LiteralPath $transcript -UseMinimalHeader | Out-Null
        try {
            @(Invoke-QuietScriptFixWindowsDefender -WhatIf).Count | Should -Be 0
        } finally {
            Stop-Transcript | Out-Null
        }

        $preview = Get-Content -LiteralPath $transcript -Raw -Encoding utf8
        $preview | Should -Match 'Microsoft Defender Antivirus'
        $preview | Should -Match 'Add development path, process and VHDX exclusions'

        Should -Invoke -ModuleName Fix-WindowsDefender Test-Path -Exactly -Times 0
        Should -Invoke -ModuleName Fix-WindowsDefender Add-MpPreference -Exactly -Times 0
        Should -Invoke -ModuleName Fix-WindowsDefender Get-MpPreference -Exactly -Times 0
    }

    It 'surfaces a write failure without reading stale preferences' {
        Mock -ModuleName Fix-WindowsDefender Add-MpPreference { throw 'FixtureDefenderWriteFailed' }

        { Invoke-QuietScriptFixWindowsDefender -Confirm:$false } |
            Should -Throw -ExpectedMessage '*FixtureDefenderWriteFailed*'
        Should -Invoke -ModuleName Fix-WindowsDefender Get-MpPreference -Exactly -Times 0
    }
}
