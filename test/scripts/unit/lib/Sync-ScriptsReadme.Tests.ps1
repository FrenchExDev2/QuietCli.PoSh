#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null = Import-QuietTestLibrary -Name Sync-ScriptsReadme
    $newPaths = {
        $fixture = [IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))
        @{ ScriptsPath = [IO.Path]::Combine($fixture,'scripts'); DocsPath = [IO.Path]::Combine($fixture,'docs','scripts') }
    }
}

Describe 'Invoke-QuietScriptSyncScriptsReadme source links' {
    It 'synchronizes nested sources and profiles, preserves prose and is idempotent' {
        $paths = & $newPaths
        $null = New-QuietTestFile ([IO.Path]::Combine($paths.ScriptsPath,'lib/Foo.psm1')) '# Library'
        $null = New-QuietTestFile ([IO.Path]::Combine($paths.ScriptsPath,'RunProfiles/bench.profile.psd1')) '@{}'
        $original = "# Foo`r`n`r`n    Texte de référence.`r`n"
        $library = New-QuietTestFile ([IO.Path]::Combine($paths.DocsPath,'lib/Foo.md'))
        [IO.File]::WriteAllText($library,$original,[Text.UTF8Encoding]::new($false))
        $profileDoc = New-QuietTestFile ([IO.Path]::Combine($paths.DocsPath,'RunProfiles/bench.profile.md')) 'Profile body without a title.'
        { Invoke-QuietScriptSyncScriptsReadme @paths } | Should -Throw -ExpectedMessage 'ScriptsDocSourceLinksStale*'
        $preview = Invoke-QuietScriptSyncScriptsReadme @paths -Apply -WhatIf
        $preview.SourceLinksToSync | Should -Be 2
        [IO.File]::Exists($preview.Path) | Should -BeFalse
        [IO.File]::ReadAllText($library,[Text.Encoding]::UTF8) | Should -BeExactly $original
        $first = Invoke-QuietScriptSyncScriptsReadme @paths -Apply -Confirm:$false
        $first.SourceLinksToSync | Should -Be 2
        $first.State | Should -BeExactly 'Missing (Applied)'
        $before = [IO.File]::ReadAllText($library,[Text.Encoding]::UTF8)
        $expected = @('# Foo','','<!-- script-source:begin -->','Source file: [`lib/Foo.psm1`](../../../scripts/lib/Foo.psm1)','<!-- script-source:end -->','','    Texte de référence.','') -join "`n"
        $before | Should -BeExactly $expected
        $expectedProfile = @('<!-- script-source:begin -->','Source file: [`RunProfiles/bench.profile.psd1`](../../../scripts/RunProfiles/bench.profile.psd1)','<!-- script-source:end -->','','Profile body without a title.') -join "`n"
        [IO.File]::ReadAllText($profileDoc,[Text.Encoding]::UTF8) | Should -BeExactly $expectedProfile
        (Invoke-QuietScriptSyncScriptsReadme @paths).SourceLinksToSync | Should -Be 0
        [IO.File]::WriteAllText($library,$before.Replace('scripts/lib/Foo.psm1)','scripts/lib/Old.psm1)'),[Text.UTF8Encoding]::new($false))
        (Invoke-QuietScriptSyncScriptsReadme @paths -Apply -Confirm:$false).SourceLinksToSync | Should -Be 1
        [IO.File]::ReadAllText($library,[Text.Encoding]::UTF8) | Should -BeExactly $before
    }

    It 'fails without write for missing docs or malformed source markers' {
        $paths = & $newPaths
        $null = New-QuietTestFile ([IO.Path]::Combine($paths.ScriptsPath,'Foo.ps1')) '# Script'
        { Invoke-QuietScriptSyncScriptsReadme @paths -Apply -Confirm:$false } | Should -Throw -ExpectedMessage 'ScriptsDocsMissing*'
        $original = "# Foo`n`n<!-- script-source:begin -->`n"
        $doc = New-QuietTestFile ([IO.Path]::Combine($paths.DocsPath,'Foo.md')) $original
        { Invoke-QuietScriptSyncScriptsReadme @paths -Apply -Confirm:$false } | Should -Throw -ExpectedMessage 'ScriptsDocSourceBlockInvalid*'
        [IO.File]::ReadAllText($doc,[Text.Encoding]::UTF8) | Should -BeExactly $original
        $reversed = @('# Foo','','<!-- script-source:end -->','<!-- script-source:begin -->','') -join "`n"
        [IO.File]::WriteAllText($doc,$reversed,[Text.UTF8Encoding]::new($false))
        { Invoke-QuietScriptSyncScriptsReadme @paths -Apply -Confirm:$false } | Should -Throw -ExpectedMessage 'ScriptsDocSourceBlockInvalid*'
        [IO.File]::ReadAllText($doc,[Text.Encoding]::UTF8) | Should -BeExactly $reversed
    }
}
