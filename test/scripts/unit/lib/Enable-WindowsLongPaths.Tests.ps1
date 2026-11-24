#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null = Import-QuietTestLibrary -Name Enable-WindowsLongPaths
}

Describe 'Invoke-QuietScriptEnableWindowsLongPaths' {
    BeforeEach {
        Mock -ModuleName Enable-WindowsLongPaths New-ItemProperty { [pscustomobject]@{ LongPathsEnabled = 1 } }
        Mock -ModuleName Enable-WindowsLongPaths Get-ItemPropertyValue { 1 }
    }

    It 'sets the exact machine DWORD and reads back its value' {
        $result = @(Invoke-QuietScriptEnableWindowsLongPaths -Confirm:$false)

        $result.Count | Should -Be 2
        $result[0].LongPathsEnabled | Should -Be 1
        $result[1] | Should -Be 1
        Should -Invoke -ModuleName Enable-WindowsLongPaths New-ItemProperty -Exactly -Times 1 -ParameterFilter {
            $LiteralPath -ceq 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -and
                $Name -ceq 'LongPathsEnabled' -and $Value -eq 1 -and $PropertyType -eq 'DWord' -and
                $Force -and $Confirm -eq $false -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke -ModuleName Enable-WindowsLongPaths Get-ItemPropertyValue -Exactly -Times 1 -ParameterFilter {
            $LiteralPath -ceq 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -and
                $Name -ceq 'LongPathsEnabled' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'does not touch the registry in preview' {
        $transcript = [IO.Path]::Combine($TestDrive, 'long-paths-preview.txt')
        Start-Transcript -LiteralPath $transcript -UseMinimalHeader | Out-Null
        try {
            @(Invoke-QuietScriptEnableWindowsLongPaths -WhatIf).Count | Should -Be 0
        } finally {
            Stop-Transcript | Out-Null
        }

        $preview = Get-Content -LiteralPath $transcript -Raw -Encoding utf8
        $preview | Should -Match ([regex]::Escape('HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled'))
        $preview | Should -Match 'Set DWORD to 1'

        Should -Invoke -ModuleName Enable-WindowsLongPaths New-ItemProperty -Exactly -Times 0
        Should -Invoke -ModuleName Enable-WindowsLongPaths Get-ItemPropertyValue -Exactly -Times 0
    }

    It 'surfaces a write failure without reading a stale value' {
        Mock -ModuleName Enable-WindowsLongPaths New-ItemProperty { throw 'FixtureRegistryWriteFailed' }

        { Invoke-QuietScriptEnableWindowsLongPaths -Confirm:$false } |
            Should -Throw -ExpectedMessage '*FixtureRegistryWriteFailed*'
        Should -Invoke -ModuleName Enable-WindowsLongPaths Get-ItemPropertyValue -Exactly -Times 0
    }
}
