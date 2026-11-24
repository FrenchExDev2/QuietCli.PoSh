#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -DisableNameChecking -ErrorAction Stop
    $versionLibrary = Import-QuietTestLibrary -Name ModuleVersion
    $seed = Get-QuietTestSeed
    $root = [IO.Path]::Combine($TestDrive,'workspace')
    $core = [IO.Path]::Combine($root,'FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.PoSh.psd1')
    $git = [IO.Path]::Combine($root,'FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Git.PoSh.psd1')
    $coreText = "@{ModuleVersion='1.2.3'; PrivateData=@{PSData=@{Prerelease='preview3'}}}"
    $gitText = "@{ModuleVersion='4.5.6'; RequiredModules=@('FrenchExDev2.QuietCli.Core.PoSh')}"
}

Describe 'Invoke-QuietScriptNewVersion' {
    BeforeEach {
        $null = New-QuietTestFile -Path $core -Text $coreText
        $null = New-QuietTestFile -Path $git -Text $gitText
    }

    It 'plans each current version independently without changing any bytes' {
        $before = (Get-FileHash -LiteralPath $core,$git).Hash
        $plan = @(Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Bump patch -WhatIf)
        $plan.PreviousVersion | Should -BeExactly @('1.2.3-preview3','4.5.6')
        $plan.Version | Should -BeExactly @('1.2.4','4.5.7')
        $plan.Changed | Should -Be @($true,$true)
        $plan.Updated | Should -Be @($false,$false)
        (Get-FileHash -LiteralPath $core,$git).Hash | Should -BeExactly $before
        @(Get-ChildItem -LiteralPath $root -Recurse -File).Count | Should -Be 2
    }

    It 'deduplicates aliases and full names and applies only the selected version' {
        $plan = @(Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Version 2.0.0-preview3 -Module core,FrenchExDev2.QuietCli.Core.PoSh)
        $plan.Count | Should -Be 1
        $plan[0].Module | Should -BeExactly 'FrenchExDev2.QuietCli.Core.PoSh'
        $plan[0].ManifestPath | Should -BeExactly $core
        $plan[0].Changed | Should -BeTrue
        $plan[0].Updated | Should -BeTrue
        $manifest = Import-PowerShellDataFile -LiteralPath $core
        $manifest.ModuleVersion | Should -BeExactly '2.0.0'
        $manifest.PrivateData.PSData.Prerelease | Should -BeExactly 'preview3'
        [IO.File]::ReadAllText($git,[Text.Encoding]::UTF8) | Should -BeExactly $gitText
    }

    It 'leaves an exact version byte-for-byte intact' {
        $plan = Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Version 1.2.3-preview3 -Module Core
        $plan.Changed | Should -BeFalse
        $plan.Updated | Should -BeFalse
        [IO.File]::ReadAllText($core,[Text.Encoding]::UTF8) | Should -BeExactly $coreText
    }

    It 'accepts patch zero and selects a case-insensitive full name by itself' {
        $null = New-QuietTestFile -Path $git -Text ($gitText.Replace('4.5.6','4.5.0'))
        $result = Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Bump PATCH -Module 'frenchexdev2.quietcli.git.posh'
        $result.Module | Should -BeExactly 'FrenchExDev2.QuietCli.Git.PoSh'
        $result.Version | Should -BeExactly '4.5.1'
        [IO.File]::ReadAllText($core,[Text.Encoding]::UTF8) | Should -BeExactly $coreText
        [Convert]::ToHexString([IO.File]::ReadAllBytes($git)) |
            Should -BeExactly ([Convert]::ToHexString([Text.Encoding]::UTF8.GetBytes($gitText.Replace('4.5.6','4.5.1'))))
    }

    It 'starts or increments the preview counter for <Label>' -ForEach @(
        @{ Label = ''; Next = 'preview1' }
        @{ Label = 'preview'; Next = 'preview1' }
        @{ Label = 'preview3'; Next = 'preview4' }
        @{ Label = 'PREVIEW9'; Next = 'preview10' }
        @{ Label = 'preview2147483646'; Next = 'preview2147483647' }
    ) {
        $null = New-QuietTestFile -Path $core -Text ($coreText.Replace('preview3',$Label))
        $result = Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Module Core -Bump preview
        $result.Version | Should -BeExactly "1.2.3-$Next"
        $result.Updated | Should -BeTrue
        $manifest = Import-PowerShellDataFile -LiteralPath $core
        $manifest.ModuleVersion | Should -BeExactly '1.2.3'
        $manifest.PrivateData.PSData.Prerelease | Should -BeExactly $Next
    }

    It 'increments preview counters independently and handles missing metadata' {
        $plan = @(Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Bump preview)
        $plan.Version | Should -BeExactly @('1.2.3-preview4','4.5.6-preview1')
        $data = Import-PowerShellDataFile -LiteralPath $git
        $data.ModuleVersion | Should -BeExactly '4.5.6'
        $data.PrivateData.PSData.Prerelease | Should -BeExactly 'preview1'
    }

    It 'rejects an invalid preview bump from <Label>' -ForEach @(
        @{ Label = 'rc1'; ErrorPrefix = 'ModuleVersionExpectedPreview' }
        @{ Label = 'preview-1'; ErrorPrefix = 'ModuleVersionExpectedPreview' }
        @{ Label = 'preview2147483647'; ErrorPrefix = 'ModuleVersionBumpOverflow' }
        @{ Label = 'preview2147483648'; ErrorPrefix = 'ModuleVersionBumpOverflow' }
    ) {
        $before = $coreText.Replace('preview3',$Label)
        $null = New-QuietTestFile -Path $core -Text $before
        { Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Module Core -Bump preview } |
            Should -Throw -ExpectedMessage "${ErrorPrefix}:*"
        [IO.File]::ReadAllText($core,[Text.Encoding]::UTF8) | Should -BeExactly $before
    }

    It 'reports an unknown module even when All was also passed' {
        { Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Version 2.0.0 -Module All,Unknown } |
            Should -Throw -ExpectedMessage 'ModuleVersionUnknownModule: Unknown'
        [IO.File]::ReadAllText($core,[Text.Encoding]::UTF8) | Should -BeExactly $coreText
    }

    It 'rejects a workspace containing only test modules' {
        $testRoot = [IO.Path]::Combine($TestDrive,'test-only')
        $null = New-QuietTestFile -Path ([IO.Path]::Combine($testRoot,'FrenchExDev2.QuietCli.Core.Tests.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1')) -Text $coreText
        { Invoke-QuietScriptNewVersion -WorkspaceRoot $testRoot -Version 2.0.0 } |
            Should -Throw -ExpectedMessage 'ModuleVersionNoBusinessModules'
    }

    It 'validates the full batch before editing the first manifest' -ForEach @(
        @{ Version = '4.5.2147483647'; ErrorPrefix = 'ModuleVersionBumpOverflow' }
        @{ Version = '4.5'; ErrorPrefix = 'ModuleVersionBumpRequiresThreeParts' }
        @{ Version = '4.5.6.0'; ErrorPrefix = 'ModuleVersionBumpRequiresThreeParts' }
        @{ Version = 'bad'; ErrorPrefix = 'ModuleVersionBumpRequiresThreeParts' }
    ) {
        $before = $gitText.Replace('4.5.6',$Version)
        $null = New-QuietTestFile -Path $git -Text $before
        { Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Bump patch } |
            Should -Throw -ExpectedMessage "${ErrorPrefix}:*"
        [IO.File]::ReadAllText($core,[Text.Encoding]::UTF8) | Should -BeExactly $coreText
        [IO.File]::ReadAllText($git,[Text.Encoding]::UTF8) | Should -BeExactly $before
    }

    It 'reports a manifest changed while its version is being read' {
        Mock -ModuleName ModuleVersion -CommandName Import-PowerShellDataFile -MockWith {
            param($LiteralPath)
            $data = Microsoft.PowerShell.Utility\Import-PowerShellDataFile -LiteralPath $LiteralPath
            [IO.File]::AppendAllText($LiteralPath,"`n# concurrent edit",[Text.UTF8Encoding]::new($false))
            $data
        }
        { Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Module Git -Bump patch } |
            Should -Throw -ExpectedMessage 'ModuleVersionManifestChanged:*'
        [IO.File]::ReadAllText($core,[Text.Encoding]::UTF8) | Should -BeExactly $coreText
        [IO.File]::ReadAllText($git,[Text.Encoding]::UTF8) | Should -BeExactly "$gitText`n# concurrent edit"
    }

    It 'increments the selected component and resets less significant components for generated versions' {
        $null = Invoke-QuietProperty -Name 'module-version-bump' -Seed $seed -Count 45 -Generator { param($random)
            @{ Major = $random.Next(0,100); Minor = $random.Next(1,100); Patch = $random.Next(1,100); Preview = $random.Next(1,10000) }
        } -Property { param($case)
            $numeric = "$($case.Major).$($case.Minor).$($case.Patch)"
            $label = "preview$($case.Preview)"
            $expected = @{
                Major = "$($case.Major + 1).0.0"
                Minor = "$($case.Major).$($case.Minor + 1).0"
                Patch = "$($case.Major).$($case.Minor).$($case.Patch + 1)"
                Preview = "$numeric-preview$($case.Preview + 1)"
            }
            foreach ($bump in $expected.Keys) {
                $result = & $versionLibrary {
                    param($numeric,$label,$bump)
                    Get-QuietBumpedModuleVersion -Version $numeric -Prerelease $label -Bump $bump
                } $numeric $label $bump
                if ($result -cne $expected[$bump]) { return $false }
            }
            return $true
        }
    }

    It 'rolls back an earlier replacement when Windows refuses a later one' -Skip:(!$IsWindows) {
        $lock = [IO.File]::Open($git,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            { Invoke-QuietScriptNewVersion -WorkspaceRoot $root -Bump patch } | Should -Throw
        } finally { $lock.Dispose() }
        [IO.File]::ReadAllText($core,[Text.Encoding]::UTF8) | Should -BeExactly $coreText
        [IO.File]::ReadAllText($git,[Text.Encoding]::UTF8) | Should -BeExactly $gitText
        @(Get-ChildItem -LiteralPath $root -Recurse -File).Count | Should -Be 2
    }
}
