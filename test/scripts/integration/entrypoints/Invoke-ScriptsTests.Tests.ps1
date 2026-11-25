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
    # A colored message, as captured from a child pwsh, and a NUL in a test name are not valid XML as they are.
    $unsafe=[IO.Path]::Combine($TestDrive,'unsafe')
    $null=New-QuietTestFile ([IO.Path]::Combine($unsafe,'unit','unsafe.Tests.ps1')) @'
Describe 'fixture unsafe' { It ('fails with a NUL'+[char]0+'in its name') { throw ("colored `e[31mred`e[0m and a bell"+[char]7) } }
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

    It 'renders the first failure immediately in the serial watcher' {
        $directory=& $newRun
        $serial=[IO.Path]::Combine($TestDrive,'serial')
        $null=New-QuietTestFile ([IO.Path]::Combine($serial,'unit','counter.Tests.ps1')) @'
Describe 'serial fixture' {
    It 'fails first' { throw 'expected first failure' }
    It 'sees the failure while the run is active' {
        $path=[IO.Path]::Combine($env:QUIETCLI_FIXTURE_RUN,'status.json')
        $state=Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
        $state.State | Should -BeExactly 'Running'
        $state.TestPassed | Should -Be 0
        $state.TestFailed | Should -Be 1
        & $env:QUIETCLI_FIXTURE_WATCH -RunDirectory $env:QUIETCLI_FIXTURE_RUN
    }
    It 'fails again' { throw 'expected second failure' }
}
'@
        $watch=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Watch-Tests.ps1')
        $outcome=& $run @('-TestsRoot',$serial,'-Kind','Unit','-RunDirectory',$directory) @{QUIETCLI_FIXTURE_RUN=$directory;QUIETCLI_FIXTURE_WATCH=$watch}
        $outcome.ExitCode|Should -Be 1
        $report=& $readJson $directory 'report.json'
        $report.TestPassed|Should -Be 1
        $report.TestFailed|Should -Be 2
        $workerLog=Get-Content -LiteralPath ([IO.Path]::Combine($directory,'worker.stdout.log')) -Raw -Encoding utf8
        $workerLog|Should -Match '(?m)│[^│]+│Running\s+│[^│]+│[^│]+│\s+0│\s+1│'
    }

    It 'publishes real test outcomes while parallel files are still running' {
        $directory=& $newRun
        $parallel=[IO.Path]::Combine($TestDrive,'parallel')
        $null=New-QuietTestFile ([IO.Path]::Combine($parallel,'unit','a.Tests.ps1')) @'
Describe 'first file' {
    It 'passes' { 1 | Should -Be 1 }
    It 'fails' { throw 'expected failure' }
}
'@
        $null=New-QuietTestFile ([IO.Path]::Combine($parallel,'unit','b.Tests.ps1')) @'
Describe 'second file' {
    It 'observes completed outcomes before this file finishes' {
        $path=[IO.Path]::Combine($env:QUIETCLI_FIXTURE_RUN,'status.json')
        $deadline=[DateTimeOffset]::UtcNow.AddSeconds(30)
        do {
            $state=Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
            if($state.TestPassed -eq 1 -and $state.TestFailed -eq 1){break}
            Start-Sleep -Milliseconds 100
        } while([DateTimeOffset]::UtcNow -lt $deadline)
        $state.State | Should -BeExactly 'Running'
        $state.TestPassed | Should -Be 1
        $state.TestFailed | Should -Be 1
        $state.Runs.Count | Should -Be 2
        Import-Module $env:QUIETCLI_FIXTURE_SUPPORT -DisableNameChecking -ErrorAction Stop
        $frame=Invoke-QuietTestScript -ScriptPath $env:QUIETCLI_FIXTURE_WATCH -ArgumentList @('-RunDirectory',$env:QUIETCLI_FIXTURE_RUN) -TimeoutSeconds 10
        $frame.ExitCode | Should -Be 0 -Because $frame.Error
        [IO.File]::WriteAllText([IO.Path]::Combine($env:QUIETCLI_FIXTURE_RUN,'watcher-frame.txt'),$frame.Output,[Text.Encoding]::UTF8)
        [IO.File]::WriteAllText([IO.Path]::Combine($env:QUIETCLI_FIXTURE_RUN,'parallel.complete'),'ok',[Text.Encoding]::UTF8)
    }
}
'@
        $null=New-QuietTestFile ([IO.Path]::Combine($parallel,'unit','serial.Tests.ps1')) @'
#pester:no-parallel
Describe 'serial file' {
    It 'runs after the parallel files' {
        [IO.File]::Exists([IO.Path]::Combine($env:QUIETCLI_FIXTURE_RUN,'parallel.complete')) | Should -BeTrue
    }
}
'@
        $watch=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Watch-Tests.ps1')
        $support=(Get-Command Invoke-QuietTestScript).Module.Path
        $outcome=& $run @('-TestsRoot',$parallel,'-Kind','Unit','-MaxConcurrency','2','-RunDirectory',$directory) @{QUIETCLI_FIXTURE_RUN=$directory;QUIETCLI_FIXTURE_WATCH=$watch;QUIETCLI_FIXTURE_SUPPORT=$support}
        $outcome.ExitCode|Should -Be 1
        $report=& $readJson $directory 'report.json'
        $report.TestPassed|Should -Be 3 -Because $outcome.Output
        $report.TestFailed|Should -Be 1
        $report.Incomplete|Should -BeFalse
        $status=& $readJson $directory 'status.json'
        $status.TestPassed|Should -Be 3
        $status.TestFailed|Should -Be 1
        $frame=Get-Content -LiteralPath ([IO.Path]::Combine($directory,'watcher-frame.txt')) -Raw -Encoding utf8
        $frame|Should -Match '(?m)│Total\s+│Running\s+│[^│]+│[^│]+│\s+1│\s+1│'
        $junit=[xml](Get-Content -LiteralPath ([IO.Path]::Combine($directory,'results.junit.xml')) -Raw -Encoding utf8)
        $junit.SelectNodes('//testcase').Count|Should -Be 4
    }

    It 'keeps companion case state and private fixtures in the owning module' {
        $fixtureScript=[IO.Path]::Combine($TestDrive,'companion-bridge.ps1')
        $null=New-QuietTestFile $fixtureScript @'
param($WorkspaceRoot,$ScriptsRoot,$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($ScriptsRoot,'lib/PesterProgress.psm1')) -DisableNameChecking -ErrorAction Stop
$pester=Import-QuietTestPester -WorkspaceRoot $WorkspaceRoot
$suite=New-Module -ScriptBlock {function Read-PrivateFixture {'témoins'}}
$observed=& $suite {
    param($workspace,$directory,$pester)
    $privateValue='témoins'
    $notifications=[Collections.Generic.List[string]]::new()
    $invoker={param($configuration,$body) if($body){& $body}else{Pester\Invoke-Pester -Configuration $configuration}}
    $cases=[ordered]@{
        'uses suite state'={
            if((Read-PrivateFixture) -cne $privateValue){throw 'PrivateFixtureLost'}
            $nested=Invoke-QuietPesterCaseTable -WorkspaceRoot $workspace -Suite Focused -Cases ([ordered]@{inside={if($privateValue -cne 'témoins'){throw 'NestedFixtureLost'}}}) -InvokePester $invoker
            if($nested.Passed -ne 1){throw 'NestedCaseFailed'}
        }
        'intentional failure'={throw 'CaseFailedAsExpected'}
        'skips the remaining case'={throw 'MustNotRun'}
    }
    $metadata=@{};$index=0
    $stages=@(foreach($name in $cases.Keys){
        $metadata[$name]=@{TestKind='Unit';Dependencies=@()}
        $stage=[Collections.Generic.List[object]]::new()
        $stage.Add([pscustomobject]@{Name=$name;Mode='Ordered';Index=$index})
        $index++
        @{Mode='Ordered';Cases=$stage}
    })
    $env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE='1'
    $plan=@{Cases=$cases.Count;Stages=$stages}
    $result=Invoke-QuietPesterCompanionPlan -WorkspaceRoot $workspace -RunDirectory $directory -Suite Fixture -Plan $plan -Cases $cases -Metadata $metadata -InvokePester $invoker -OnProgress {
        param($name,$state,$passed,$failed)
        if($state -ne 'Running'){$notifications.Add("$state/$passed/$failed")}
    }
    $config={Pester\Invoke-Pester -Configuration @{Run=@{PassThru=$true;ScriptBlock={Describe 'hook' {It 'passes' {}}}};TestRegistry=@{Enabled=$false};Output=@{Verbosity='None'}}}
    $hook=[Collections.Generic.List[string]]::new()
    $null=Invoke-QuietPesterWithProgress -Pester $pester -Run $config -OnTest {param($test,$state) $hook.Add($state)}
    @{Passed=$result.Passed;Failed=$result.Failed;Skipped=$result.Skipped;Error=$result.Cases[-1].Error;Notifications=$notifications.ToArray();Hook=$hook.ToArray()}
} $WorkspaceRoot $OutputDirectory $pester
$observed | ConvertTo-Json -Compress
'@
        $directory=& $newRun
        $outcome=Invoke-QuietTestScript -ScriptPath $fixtureScript -ArgumentList @($workspace,(Get-QuietTestScriptsRoot),$directory) -TimeoutSeconds 60
        $outcome.ExitCode|Should -Be 0 -Because ($outcome.Output+$outcome.Error)
        $observed=$outcome.Output|ConvertFrom-Json
        $observed.Passed|Should -Be 1
        $observed.Failed|Should -Be 1
        $observed.Skipped|Should -Be 1
        $observed.Error|Should -BeExactly 'CaseFailedAsExpected'
        ($observed.Notifications -join ',')|Should -BeExactly 'Passed/1/0,Failed/1/1'
        ($observed.Hook -join ',')|Should -BeExactly 'Running,Passed'
        $first=& $readJson ([IO.Path]::Combine($directory,'core-cases','pester-0')) 'case-result.json'
        $first.Name|Should -BeExactly 'uses suite state'
    }

    It 'saves a valid JUnit report for a failure message and a test name that XML cannot hold as they are' {
        $directory=& $newRun
        $outcome=& $run @('-TestsRoot',$unsafe,'-Kind','Unit','-RunDirectory',$directory)
        $outcome.ExitCode|Should -Be 1
        $report=& $readJson $directory 'report.json'
        $report.Incomplete|Should -BeFalse
        $report.Failed|Should -Be 1
        $junit=[xml](Get-Content -LiteralPath ([IO.Path]::Combine($directory,'results.junit.xml')) -Raw -Encoding utf8)
        $case=$junit.SelectSingleNode('//testcase')
        $case.name|Should -BeExactly 'fixture unsafe.fails with a NULU+0000in its name'
        $case.SelectSingleNode('failure').message|Should -BeLike '*colored red and a bellU+0007*'
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
