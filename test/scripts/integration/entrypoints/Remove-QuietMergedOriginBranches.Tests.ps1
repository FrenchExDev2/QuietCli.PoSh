#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $entry = [IO.Path]::Combine((Get-QuietTestScriptsRoot), 'Remove-QuietMergedOriginBranches.ps1')
    $module = Import-QuietTestLibrary -Name Remove-QuietMergedOriginBranches
    $git = {
        param([string[]]$Arguments)
        $output = & git -C $TestDrive -c user.name=quiet-test -c user.email=quiet-test@invalid -c commit.gpgsign=false @Arguments 2>&1
        if ($LASTEXITCODE) { throw ($output -join "`n") }
        ($output -join "`n").Trim()
    }
}

Describe 'Remove-QuietMergedOriginBranches.ps1' {
    It 'previews before reaching Git even with a missing checkout' {
        $missing = [IO.Path]::Combine($TestDrive, 'missing')
        $result = Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot', $missing, '-Apply', '-WhatIf')
        $result.ExitCode | Should -Be 0 -Because $result.Error
        $result.Output | Should -Match 'origin'
        Test-Path -LiteralPath $missing | Should -BeFalse
    }

    It 'refuses a non-GitHub origin even with Apply enabled' {
        $null = & $git @('init', '-q')
        $null = & $git @('remote', 'add', 'origin', 'https://example.invalid/owner/repo.git')
        $result = Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot', $TestDrive, '-Apply')
        $result.ExitCode | Should -Not -Be 0
        $result.Error | Should -Match 'MergedOriginRepositoryMismatch'
        & $git @('remote', 'get-url', 'origin') | Should -BeExactly 'https://example.invalid/owner/repo.git'
    }

    It 'keeps the entire batch when a lease is stale, then deletes exactly the refs with current leases' {
        $origin = [IO.Path]::Combine($TestDrive, 'lease.git')
        $work = [IO.Path]::Combine($TestDrive, 'lease-work')
        $null = & $git @('init', '-q', '--bare', '-b', 'develop', $origin)
        $null = & $git @('init', '-q', '-b', 'develop', $work)
        $null = & $git @('-C', $work, 'commit', '-q', '--allow-empty', '-m', 'base')
        $base = & $git @('-C', $work, 'rev-parse', 'HEAD')
        $null = & $git @('-C', $work, 'remote', 'add', 'origin', $origin)
        $null = & $git @('-C', $work, 'push', '-q', 'origin', 'HEAD:refs/heads/develop', 'HEAD:refs/heads/fix/one', 'HEAD:refs/heads/fix/two')
        $null = & $git @('-C', $work, 'commit', '-q', '--allow-empty', '-m', 'advance fix/two')
        $tip = & $git @('-C', $work, 'rev-parse', 'HEAD')
        $null = & $git @('-C', $work, 'push', '-q', 'origin', 'HEAD:refs/heads/fix/two')
        $delete = {
            param($SecondTip)
            & $module {
                param($Root, $FirstTip, $SecondTip)
                Invoke-QuietOriginBranchTool git @('-c', 'remote.origin.mirror=false', 'push', '--atomic', '--no-follow-tags', '--recurse-submodules=no',
                    "--force-with-lease=refs/heads/fix/one:$FirstTip", "--force-with-lease=refs/heads/fix/two:$SecondTip",
                    'origin', ':refs/heads/fix/one', ':refs/heads/fix/two') $Root
            } $work $base $SecondTip
        }
        $before = & $git @('--git-dir', $origin, 'show-ref', '--heads')
        { & $delete $base } | Should -Throw -ExpectedMessage 'MergedOriginToolFailed*'
        & $git @('--git-dir', $origin, 'show-ref', '--heads') | Should -BeExactly $before
        $null = & $delete $tip
        & $git @('--git-dir', $origin, 'show-ref', '--heads') | Should -BeExactly "$base refs/heads/develop"
        & $git @('-C', $work, 'rev-parse', 'refs/heads/develop') | Should -BeExactly $tip
    }
}
