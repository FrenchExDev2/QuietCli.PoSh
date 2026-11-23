#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null = Import-QuietTestLibrary -Name New-QuietCompanion
}

Describe 'Resolve-NewCompanionBranch' {
    It 'derives or validates the branch <Expected>' -ForEach @(
        @{Override=''; Expected='companion/packer'}
        @{Override='packer-parser'; Expected='companion/packer-parser'}
        @{Override='companion/parser/v2'; Expected='companion/parser/v2'}
    ) {
        InModuleScope New-QuietCompanion -Parameters @{Override=$Override; Expected=$Expected} {
            Resolve-NewCompanionBranch 'Packer' $Override | Should -BeExactly $Expected
        }
    }

    It 'rejects the invalid branch <Override>' -ForEach @(
        @{Override='feature/packer'; Expected='CompanionBranchKindRequired'}
        @{Override='companion/'; Expected='WorkBranchNameInvalid*'}
        @{Override='a..b'; Expected='WorkBranchNameInvalid*'}
    ) {
        InModuleScope New-QuietCompanion -Parameters @{Override=$Override; Expected=$Expected} {
            { Resolve-NewCompanionBranch 'Packer' $Override } | Should -Throw -ExpectedMessage $Expected
        }
    }
}

Describe 'Add-QuietCompanionRegistration' {
    It 'keeps existing lines and adds a source registration and a suite' {
        InModuleScope New-QuietCompanion {
            $catalogue = @('schema: 1','companions:','  Core: # keep','    requires: []','    image: base',
                'suites: # keep','  Core:','    core_evidence: true  ','') -join ([string][char]13 + [char]10)
            $expected = @(
                'schema: 1'
                'companions:'
                '  Core: # keep'
                '    requires: []'
                '    image: base'
                '  Packer:'
                '    requires: [Core]'
                '    image: none'
                'suites: # keep'
                '  Core:'
                '    core_evidence: true  '
                '  Packer:'
                '    test_project: FrenchExDev2.QuietCli.Packer.Tests.PoSh'
                '    command: Invoke-QuietPackerTests'
                '    requires: [Packer]'
                '    core_evidence: false'
                ''
            ) -join [char]10
            Add-QuietCompanionRegistration $catalogue 'Packer' | Should -BeExactly $expected
        }
    }

    It 'rejects a missing or duplicate suites section' {
        InModuleScope New-QuietCompanion {
            { Add-QuietCompanionRegistration 'companions:' 'Packer' } | Should -Throw 'CompanionCatalogueSuitesSectionInvalid'
            $duplicate = @('suites:', 'suites:') -join [char]10
            { Add-QuietCompanionRegistration $duplicate 'Packer' } | Should -Throw 'CompanionCatalogueSuitesSectionInvalid'
        }
    }
}

Describe 'Publish-NewQuietCompanion' {
    It 'restores shared bytes and removes newly installed files when a downstream write fails' {
        $target = [IO.Path]::Combine($TestDrive, 'target')
        $stage = [IO.Path]::Combine($TestDrive, 'stage')
        $null = New-QuietTestFile ([IO.Path]::Combine($target, 'shared.txt')) 'originalé'
        $null = New-QuietTestFile ([IO.Path]::Combine($stage, 'shared.txt')) 'updated'
        $null = New-QuietTestFile ([IO.Path]::Combine($stage, 'src/Packer/module.txt')) 'new'
        Mock -ModuleName New-QuietCompanion Install-NewCompanionFile {
            if ($Path.EndsWith('fail.txt')) { throw 'SimulatedWriteFailure' }
            [IO.File]::WriteAllBytes($Path, $Bytes)
        }
        InModuleScope New-QuietCompanion -Parameters @{Target=$target; Stage=$stage} {
            $original = @{'shared.txt'=[IO.File]::ReadAllBytes([IO.Path]::Combine($Target, 'shared.txt'))}
            [IO.File]::WriteAllText([IO.Path]::Combine($Stage,'fail.txt'), 'fail', [Text.UTF8Encoding]::new($false))
            { Publish-NewQuietCompanion $Target $Stage 'src/Packer' @('shared.txt','src/Packer/module.txt','fail.txt') $original } |
                Should -Throw -ExpectedMessage 'SimulatedWriteFailure'
        }
        [IO.File]::ReadAllText([IO.Path]::Combine($target,'shared.txt'), [Text.Encoding]::UTF8) | Should -BeExactly 'originalé'
        [IO.Directory]::Exists([IO.Path]::Combine($target,'src/Packer')) | Should -BeFalse
        [IO.File]::Exists([IO.Path]::Combine($target,'fail.txt')) | Should -BeFalse
    }
}

Describe 'Get-QuietCompanionScaffoldPlan and Invoke-QuietScriptNewQuietCompanion' {
    It 'previews the compiled files and invokes no writes before confirmation' {
        $root = [IO.Path]::Combine($TestDrive, 'preview')
        foreach ($directory in 'src','.github/workflows','docs/ci/github') {
            $null = [IO.Directory]::CreateDirectory([IO.Path]::Combine($root, $directory))
        }
        $credits = New-QuietTestFile ([IO.Path]::Combine($root, 'licenses.md')) ('## Fixture' + [char]10 + 'https://example.test/license')
        Mock -ModuleName New-QuietCompanion Get-QuietWorkspaceProjects {}
        $plan = Get-QuietCompanionScaffoldPlan -Name Packer -WorkspaceRoot $root -LicenseCreditsPath $credits -WithCSharp
        $plan.Branch | Should -BeExactly 'companion/packer'
        $plan.Paths | Should -Contain 'src/Packer/src/FrenchExDev2.QuietCli.Packer.PoSh/engine/QuietCli.Packer.Parser.csproj'
        $plan.Paths | Should -Not -Contain '.github/workflows/packer-ci.yml'
        $null = Invoke-QuietScriptNewQuietCompanion -Name Packer -WorkspaceRoot $root -LicenseCreditsPath $credits -WhatIf
        @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($root, 'src')) -Force).Count | Should -Be 0
    }
}
