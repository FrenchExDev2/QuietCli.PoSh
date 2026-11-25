#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $testProject=[IO.Path]::Combine((Get-QuietTestWorkspaceRoot),'src','Core','test','FrenchExDev2.QuietCli.Core.Tests.PoSh')
}

Describe 'RunProfiles PowerShell qualification' {
    It 'publishes one Pester completion per selected case and retains skipped cases' {
        $entry=[IO.Path]::Combine($testProject,'RunProfiles.Tests.ps1')
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-CasePattern','format:*','-Iterations','10') -TimeoutSeconds 90
        $result.ExitCode | Should -Be 0 -Because ($result.Output+$result.Error)
        $result.Output | Should -Match '(?m)^PESTER_CASE 0 0 Running format:'
        $result.Output | Should -Match '(?m)^PESTER_CASE 6 0 Passed format:'
        $result.Output | Should -Match '(?m)^SUMMARY Passed=6 Failed=0 Skipped=[1-9]\d*\s*$'
    }

    It 'uses Pester failures in a copied mutation fixture to reject a behavioral mutant' {
        $entry=[IO.Path]::Combine($testProject,'RunProfiles.Mutation.ps1')
        $receipt=[IO.Path]::Combine($TestDrive,'run-profile-mutant.json')
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-MutantName','name-anchor-loose','-Iterations','10','-OutputPath',$receipt) -TimeoutSeconds 180
        $result.ExitCode | Should -Be 0 -Because ($result.Output+$result.Error)
        $report=Get-Content -LiteralPath $receipt -Raw -Encoding utf8 | ConvertFrom-Json
        $report.BaselinePassed | Should -BeTrue
        $report.Partial | Should -BeTrue
        @($report.Results).Count | Should -Be 1
        $report.Results[0].Outcome | Should -BeExactly 'Killed'
        $report.Results[0].Detail | Should -Match '^[1-9]\d* failing case\(s\)$'
    }
}
