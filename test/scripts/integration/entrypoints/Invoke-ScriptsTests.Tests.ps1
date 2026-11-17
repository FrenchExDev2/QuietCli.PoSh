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
    # A library the runner itself imports (ScriptsTests) must still resolve to the copy under -ScriptsRoot,
    # which is what lets the mutation engine test a mutated copy; Pester must be the single pinned instance.
    $isolation=[IO.Path]::Combine($TestDrive,'isolation')
    $copy=[IO.Path]::Combine($TestDrive,'scripts-copy')
    [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($copy,'lib'))
    [IO.File]::Copy([IO.Path]::Combine((Get-QuietTestScriptsRoot),'lib','ScriptsTests.psm1'),[IO.Path]::Combine($copy,'lib','ScriptsTests.psm1'))
    $null=New-QuietTestFile ([IO.Path]::Combine($isolation,'unit','isolation.Tests.ps1')) @'
BeforeAll { Import-Module ([IO.Path]::Combine($env:QUIETCLI_SCRIPTS_ROOT,'lib','ScriptsTests.psm1')) -Force -Global -DisableNameChecking -ErrorAction Stop }
Describe 'fixture isolation' {
    It 'resolves the copy' { [IO.File]::WriteAllText($env:QUIETCLI_FIXTURE_PROBE, ((Get-Command Get-QuietScriptsTestExitCode).Module.Path+'|'+@(Get-Module Pester -All).Count)) }
}
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

    It 'runs the tests against the -ScriptsRoot copy even for a library the runner imports, with one pinned Pester' {
        $directory=& $newRun;$probe=[IO.Path]::Combine($TestDrive,'isolation.txt')
        $outcome=& $run @('-TestsRoot',$isolation,'-ScriptsRoot',$copy,'-Kind','Unit','-RunDirectory',$directory) @{QUIETCLI_FIXTURE_PROBE=$probe}
        $outcome.ExitCode|Should -Be 0 -Because $outcome.Output
        (& $readJson $directory 'report.json').Passed|Should -Be 1
        $path,$count=[IO.File]::ReadAllText($probe).Split('|')
        $path|Should -BeExactly ([IO.Path]::GetFullPath([IO.Path]::Combine($copy,'lib','ScriptsTests.psm1')))
        $count|Should -BeExactly '1'
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
