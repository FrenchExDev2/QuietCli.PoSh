#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Invoke-ScriptsTests.ps1')
    $workspace=Get-QuietTestWorkspaceRoot
    $fixture=[IO.Path]::Combine($TestDrive,'fixture')
    $null=New-QuietTestFile ([IO.Path]::Combine($fixture,'unit','ok.Tests.ps1')) @'
Describe 'fixture ok' {
    It 'passes' { 1 | Should -Be 1 }
    It 'records the seed' { if($env:QUIETCLI_FIXTURE_PROBE){ [IO.File]::WriteAllText($env:QUIETCLI_FIXTURE_PROBE, [string]$env:QUIETCLI_TEST_SEED) } }
}
'@
    $null=New-QuietTestFile ([IO.Path]::Combine($fixture,'integration','ko.Tests.ps1')) @'
Describe 'fixture ko' { It 'fails' { 1 | Should -Be 2 } }
'@
    $slow=[IO.Path]::Combine($TestDrive,'slow')
    $null=New-QuietTestFile ([IO.Path]::Combine($slow,'unit','slow.Tests.ps1')) @'
Describe 'fixture slow' { It 'outlives the timeout' { Start-Sleep -Seconds 120 } }
'@
    $run={param([string[]]$Arguments,[hashtable]$Environment=@{})
        Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-Headless','-Offline','-WorkspaceRoot',$workspace)+$Arguments) -Environment $Environment -TimeoutSeconds 300
    }
    $newRun={[IO.Path]::Combine($TestDrive,'runs',[guid]::NewGuid().ToString('N'))}
    $readJson={param($directory,$name)Get-Content -LiteralPath ([IO.Path]::Combine($directory,$name)) -Raw -Encoding utf8|ConvertFrom-Json}
}

Describe 'Invoke-ScriptsTests.ps1' {
    It 'exits 0 for a green unit run and saves consistent report, JUnit and terminal status' {
        $directory=& $newRun;$probe=[IO.Path]::Combine($TestDrive,'seed.txt')
        $outcome=& $run @('-TestsRoot',$fixture,'-Kind','Unit','-Seed','4242','-RunDirectory',$directory) @{QUIETCLI_FIXTURE_PROBE=$probe}
        $outcome.ExitCode|Should -Be 0 -Because $outcome.Output
        $report=& $readJson $directory 'report.json'
        $report.State|Should -BeExactly 'Success'
        $report.Passed|Should -Be 2
        $report.Partial|Should -BeFalse
        $report.Seed|Should -Be 4242
        (& $readJson $directory 'status.json').State|Should -BeExactly 'Success'
        (& $readJson $directory 'summary.json').State.Passed|Should -Be 2
        [xml]$junit=Get-Content -LiteralPath ([IO.Path]::Combine($directory,'results.junit.xml')) -Raw
        [int]$junit.testsuites.tests|Should -Be 2
        [IO.File]::ReadAllText($probe)|Should -BeExactly '4242'
    }

    It 'exits 1 when one selected test fails' {
        $directory=& $newRun
        $outcome=& $run @('-TestsRoot',$fixture,'-Kind','All','-RunDirectory',$directory)
        $outcome.ExitCode|Should -Be 1
        $report=& $readJson $directory 'report.json'
        $report.State|Should -BeExactly 'Failed'
        $report.Failed|Should -Be 1
        $report.Seed|Should -BeGreaterThan 0
        (& $readJson $directory 'status.json').State|Should -BeExactly 'Failed'
    }

    It 'marks a path-filtered run partial' {
        $directory=& $newRun
        $outcome=& $run @('-TestsRoot',$fixture,'-Path','unit/ok.Tests.ps1','-RunDirectory',$directory)
        $outcome.ExitCode|Should -Be 0
        (& $readJson $directory 'report.json').Partial|Should -BeTrue
    }

    It 'writes nothing under -WhatIf' {
        $directory=& $newRun
        $outcome=& $run @('-TestsRoot',$fixture,'-RunDirectory',$directory,'-WhatIf')
        $outcome.ExitCode|Should -Be 0
        [IO.Directory]::Exists($directory)|Should -BeFalse
    }

    It 'rejects an invalid selector before creating the run directory' {
        $directory=& $newRun
        $outcome=& $run @('-TestsRoot',$fixture,'-Path','../outside','-RunDirectory',$directory)
        $outcome.ExitCode|Should -Be 1
        ($outcome.Output+$outcome.Error)|Should -Match 'ScriptsTestPathInvalid'
        [IO.Directory]::Exists($directory)|Should -BeFalse
    }

    It 'rejects an existing run directory' {
        $directory=& $newRun;[void][IO.Directory]::CreateDirectory($directory)
        $outcome=& $run @('-TestsRoot',$fixture,'-Kind','Unit','-RunDirectory',$directory)
        $outcome.ExitCode|Should -Be 1
        ($outcome.Output+$outcome.Error)|Should -Match 'TestRunDirectoryExists'
    }

    It 'stops the worker and saves Timeout when the run exceeds its limit' {
        $directory=& $newRun
        $outcome=& $run @('-TestsRoot',$slow,'-Kind','Unit','-TimeoutSeconds','6','-RunDirectory',$directory)
        $outcome.ExitCode|Should -Be 1
        (& $readJson $directory 'status.json').State|Should -BeExactly 'Timeout'
        [IO.File]::Exists([IO.Path]::Combine($directory,'report.json'))|Should -BeFalse
    }
}
