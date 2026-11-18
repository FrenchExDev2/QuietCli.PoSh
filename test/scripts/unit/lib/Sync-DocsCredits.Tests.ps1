#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null = Import-QuietTestLibrary -Name Sync-DocsCredits
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
