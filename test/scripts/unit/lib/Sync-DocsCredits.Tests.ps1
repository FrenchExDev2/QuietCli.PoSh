#requires -Version 7.6
BeforeAll {
    foreach ($helper in @('TestWorkspace', 'Generators', 'Property')) {
        Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', "$helper.psm1")) -DisableNameChecking -ErrorAction Stop
    }
    $null = Import-QuietTestLibrary -Name Sync-DocsCredits
}

Describe 'Invoke-QuietScriptSyncDocsCredits' {
    BeforeEach {
        $root = [IO.Path]::Combine($TestDrive, [guid]::NewGuid().ToString('N'))
        $docs = [IO.Path]::Combine($root, 'docs')
        $document = New-QuietTestFile ([IO.Path]::Combine($docs, 'guide.md'))
        $credits = New-QuietTestFile ([IO.Path]::Combine($root, 'CREDITS.md')) '# Licenses'
        $arguments = @{ RootPath = $root; DocsPath = $docs; CreditsPath = $credits }
        $footer = Format-QuietDocsCreditsBlock -Link '../CREDITS.md'
    }

    It 'reports a correct but misplaced block without writing in check or preview mode' {
        $inputText = "# Guide`n`n$footer`n`n## À conserver`n"
        $null = New-QuietTestFile $document $inputText
        { Invoke-QuietScriptSyncDocsCredits @arguments } | Should -Throw '*guide.md (Stale)*'
        { Invoke-QuietScriptSyncDocsCredits @arguments -Apply -WhatIf } | Should -Throw '*guide.md (Stale)*'
        [IO.File]::ReadAllText($document, [Text.Encoding]::UTF8) | Should -BeExactly $inputText

        (Invoke-QuietScriptSyncDocsCredits @arguments -Apply).State | Should -BeExactly 'Stale (Applied)'
        [IO.File]::ReadAllText($document, [Text.Encoding]::UTF8) | Should -BeExactly "# Guide`n`n## À conserver`n`n$footer`n"
        (Invoke-QuietScriptSyncDocsCredits @arguments -Apply).State | Should -BeExactly 'UpToDate'
    }

    It 'inserts a footer into an empty file and accepts trailing whitespace after it' {
        (Invoke-QuietScriptSyncDocsCredits @arguments -Apply).State | Should -BeExactly 'Missing (Applied)'
        [IO.File]::ReadAllText($document, [Text.Encoding]::UTF8) | Should -BeExactly "$footer`n"
        $null = New-QuietTestFile $document "$footer`n  `n"
        (Invoke-QuietScriptSyncDocsCredits @arguments).State | Should -BeExactly 'UpToDate'
    }

    It 'moves generated blocks while preserving Markdown examples in seeded documents' {
        $null = Invoke-QuietProperty -Name 'credits footer placement' -Seed (Get-QuietTestSeed) -Count 24 -Generator {
            param($random)
            @{
                Body = New-QuietRandomString $random -Alphabet 'abcéè' -MinLength 1 -MaxLength 16
                Fence = if ($random.Next(2)) { '~~~' } else { '````' }
                LineEnding = if ($random.Next(2)) { "`r`n" } else { "`n" }
                Copies = $random.Next(1, 4)
            }
        } -Property {
            param($case)
            $oldFooter = $footer.Replace('../CREDITS.md', 'old.md')
            $example = "$($case.Fence)markdown`n$oldFooter`n$($case.Fence)"
            $intro = "# Guide`n`n$example"
            $body = "$intro`n`n$($case.Body)"
            $inputText = ($intro + ("`n`n$oldFooter" * $case.Copies) + "`n`n$($case.Body)`n").Replace("`n", $case.LineEnding)
            [IO.File]::WriteAllText($document, $inputText, [Text.UTF8Encoding]::new($false))

            $null = Invoke-QuietScriptSyncDocsCredits @arguments -Apply
            $expected = "$body`n`n$footer`n".Replace("`n", $case.LineEnding)
            [IO.File]::ReadAllText($document, [Text.Encoding]::UTF8) | Should -BeExactly $expected
            (Invoke-QuietScriptSyncDocsCredits @arguments -Apply).State | Should -BeExactly 'UpToDate'
        }
    }

    It 'preserves malformed marker sequences and code examples in seeded documents' {
        $null = Invoke-QuietProperty -Name 'credits marker noise' -Seed (Get-QuietTestSeed) -Count 16 -Generator {
            param($random)
            @{
                Body = New-QuietRandomString $random -Alphabet 'abcéè' -MinLength 1 -MaxLength 16
                Isolated = $random.Next(1, 4)
                Example = Get-QuietRandomItem $random @(
                    'Inline `<!-- credits:begin -->` example.'
                    "    <!-- credits:begin -->`n    <!-- credits:end -->"
                    '> <!-- credits:begin -->'
                    '<!-- Credits:Begin -->'
                )
            }
        } -Property {
            param($case)
            $before = "<!-- credits:end -->`n`n$($case.Example)`n`n" +
                ("<!-- credits:begin -->`n`n" * $case.Isolated) + "## $($case.Body)"
            $null = New-QuietTestFile $document "$before`n`n$footer`n`n## After"

            $null = Invoke-QuietScriptSyncDocsCredits @arguments -Apply
            [IO.File]::ReadAllText($document, [Text.Encoding]::UTF8) | Should -BeExactly "$before`n`n## After`n`n$footer`n"
            (Invoke-QuietScriptSyncDocsCredits @arguments).State | Should -BeExactly 'UpToDate'
        }
    }
}

Describe 'Format-QuietDocsCreditsBlock' {
    It 'uses the requested wording and embeds each credit link as a valid Markdown destination' {
        foreach ($link in @('../CREDITS.md','https://github.com/FrenchExDev2/QuietCli.PoSh/blob/HEAD/CREDITS.md')) {
            $expected = @(
                '<!-- credits:begin -->'
                '## Credits'
                ''
                "This document is covered by the mandatory [CREDITS.md]($link), which records the licenses of all softwares which have QuietCli companions"
                '<!-- credits:end -->'
            ) -join "`n"
            $block = Format-QuietDocsCreditsBlock -Link $link
            $block | Should -BeExactly $expected
            (ConvertFrom-Markdown -InputObject $block).Html | Should -Match ('href="'+[regex]::Escape($link)+'"')
        }
    }
}
