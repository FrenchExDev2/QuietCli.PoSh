#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', 'support', 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $scriptPath = [IO.Path]::Combine((Get-QuietTestScriptsRoot), 'Sync-ScriptContracts.ps1')
    $creditsScript = [IO.Path]::Combine((Get-QuietTestScriptsRoot), 'Sync-DocsCredits.ps1')
}

Describe 'Sync-ScriptContracts.ps1' {
    It 'inserts a new contract above an existing credits footer' {
        $root = [IO.Path]::Combine($TestDrive, 'checkout')
        $docs = [IO.Path]::Combine($root, 'docs')
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'scripts/lib/Example.psm1')) 'function Get-Example { 42 }'
        $credits = New-QuietTestFile ([IO.Path]::Combine($root, 'CREDITS.md')) '# Licenses'
        $document = New-QuietTestFile ([IO.Path]::Combine($docs, 'scripts/lib/Example.md')) '# Example'
        $creditsArgs = @('-DocsPath', $docs, '-RootPath', $root, '-CreditsPath', $credits)
        $run = Invoke-QuietTestScript -ScriptPath $creditsScript -ArgumentList ($creditsArgs + '-Apply')
        $run.ExitCode | Should -Be 0 -Because $run.Error

        $run = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-WorkspaceRoot', $root, '-Apply')
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $content = [IO.File]::ReadAllText($document, [Text.Encoding]::UTF8)
        $content | Should -Match '(?s)<!-- script-contract:end -->\s+<!-- credits:begin -->.*<!-- credits:end -->\s*\z'
        $run = Invoke-QuietTestScript -ScriptPath $creditsScript -ArgumentList $creditsArgs
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $run = Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-WorkspaceRoot', $root)
        $run.ExitCode | Should -Be 0 -Because $run.Error
    }
}
