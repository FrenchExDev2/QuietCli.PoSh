#requires -Version 7.6

BeforeAll {
    foreach ($helper in @('TestWorkspace', 'Generators', 'Property')) {
        Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', "$helper.psm1")) -DisableNameChecking -ErrorAction Stop
    }
    $null = Import-QuietTestLibrary -Name Sync-DocsCredits
    $null = Import-QuietTestLibrary -Name ResourceDocumentation
    $seed = Get-QuietTestSeed
}

Describe 'Credits for relocated README guides' {
    BeforeEach {
        $fixture = [IO.Path]::Combine($TestDrive, [guid]::NewGuid().ToString('N'))
        $docs = [IO.Path]::Combine($fixture, 'docs')
        $null = [IO.Directory]::CreateDirectory($docs)
        $credits = New-QuietTestFile ([IO.Path]::Combine($fixture, 'CREDITS.md')) '# Credits'
        $arguments = @{ RootPath = $fixture; DocsPath = $docs; CreditsPath = $credits }
    }

    It 'validates the credits link of each generated guide name and ignores files outside the pattern' {
        $null = Invoke-QuietProperty -Name 'credits for direct guide files' -Seed $seed -Count 8 -Generator {
            param($random)
            'README-' + (New-QuietRandomString $random -Alphabet 'abcxyz01234 -é' -MinLength 1 -MaxLength 16) + '.md'
        } -Property {
            param($guideName)
            $guide = New-QuietTestFile ([IO.Path]::Combine($fixture, 'readmes', $guideName)) '# Guide'
            $excluded = @(
                New-QuietTestFile ([IO.Path]::Combine($fixture, 'readmes', 'notes.md')) '# Notes'
                New-QuietTestFile ([IO.Path]::Combine($fixture, 'readmes', 'nested', $guideName)) '# Nested'
                New-QuietTestFile ([IO.Path]::Combine($fixture, 'readmes', 'README-not-a-guide.txt')) 'Other format'
            )

            { Invoke-QuietScriptSyncDocsCredits @arguments -Apply -WhatIf } | Should -Throw '*DocsCreditsNonCompliant*'
            [IO.File]::ReadAllText($guide, [Text.Encoding]::UTF8) | Should -BeExactly '# Guide'

            $null = Invoke-QuietScriptSyncDocsCredits @arguments -Apply -Confirm:$false
            $report = @(Invoke-QuietScriptSyncDocsCredits @arguments -NoRecurse)
            ($report | Where-Object Path -EQ $guide).State | Should -BeExactly 'UpToDate'
            @($report | Where-Object Path -In $excluded).Count | Should -Be 0
            [IO.File]::ReadAllText($guide, [Text.Encoding]::UTF8) | Should -Match '\[CREDITS\.md\]\(\.\./CREDITS\.md\)'
        }
    }

    It 'accepts a fixture without a readmes directory' {
        @(Invoke-QuietScriptSyncDocsCredits @arguments).Count | Should -Be 0
        $null = New-QuietTestFile ([IO.Path]::Combine($fixture, 'readmes')) 'A file with that name'
        @(Invoke-QuietScriptSyncDocsCredits @arguments).Count | Should -Be 0
    }
}

Describe 'Resource inventory links' {
    It 'links to the relocated guide and root credits when the workspace declares Core resources' {
        $root = [IO.Path]::Combine($TestDrive, 'inventory')
        $module = [IO.Path]::Combine($root, 'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh')
        $null = New-QuietTestFile ([IO.Path]::Combine($module, 'resources/dependencies.lock.json')) '{"Files":[],"Packages":[]}'

        $body = Get-QuietResourceDocumentation -WorkspaceRoot $root
        $body.TrimEnd().Split("`n")[-1] | Should -BeExactly '[Resource contract](../../readmes/README-resources.md) · [CREDITS.md](../../CREDITS.md).'
    }
}
