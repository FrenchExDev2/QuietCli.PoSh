#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $scripts=Get-QuietTestScriptsRoot
    $root=[IO.Path]::Combine($TestDrive,'component')
    $null=New-QuietTestFile ([IO.Path]::Combine($root,'lib','CompanionWorkflows.psm1')) @'
function Assert-QuietCompanionProfile { param($WorkspaceRoot,$Suite,$SolutionPath,$SourcePath,$TestPath) }
'@
    $null=New-QuietTestFile ([IO.Path]::Combine($root,'lib','CiCompanions.psm1')) @'
function Read-QuietCiCompanions { param($WorkspaceRoot) @{Companions=@{Git=@{Name='Git'}}} }
function Get-QuietCompanions { param($Configuration,$Name,$Capability) $Configuration.Companions[$Name].Name }
'@
    $null=New-QuietTestFile ([IO.Path]::Combine($root,'Build-Workspace.ps1')) 'param($WorkspaceRoot,$Suite,[switch]$ReuseVerifiedBuild,$RuntimeIdentifier)'
    $null=New-QuietTestFile ([IO.Path]::Combine($root,'Invoke-WorkspaceCi.ps1')) @'
param($WorkspaceRoot,$Suite,[switch]$SkipBuild,[switch]$SkipTty,$MaxConcurrency,$RunDirectory)
if ($Suite -cne 'Git' -or !$SkipBuild -or !$SkipTty -or $MaxConcurrency -lt 1 -or $MaxConcurrency -gt 4 -or $env:QUIETCLI_PROFILE_COMPANION) {
    throw 'Unexpected test invocation'
}
if ($env:QUIETCLI_COMPONENT_FIXTURE_FAIL -ceq 'true') { throw 'Fixture test failed' }
Start-Sleep -Milliseconds 5
'@
    Copy-Item -LiteralPath ([IO.Path]::Combine($scripts,'lib','WorkspaceJson.psm1')) -Destination ([IO.Path]::Combine($root,'lib'))
    $entry=[IO.Path]::Combine($root,'Invoke-ComponentCheck.ps1')
    Copy-Item -LiteralPath ([IO.Path]::Combine($scripts,'Invoke-ComponentCheck.ps1')) -Destination $entry
}

Describe 'Invoke-ComponentCheck performance campaign' {
    It 'records an elapsed measurement from an unprofiled companion test run' {
        $reports=[IO.Path]::Combine($root,'run-pass')
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @(
            '-WorkspaceRoot',$root,'-Suite','Git','-Campaign','performance','-RunDirectory',$reports
        ) -Environment @{GITHUB_ACTIONS='';QUIETCLI_PROFILE_COMPANION='';QUIETCLI_COMPONENT_FIXTURE_FAIL=''} -TimeoutSeconds 35
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        $receipt=Get-Content -LiteralPath ([IO.Path]::Combine($reports,'component-performance.json')) -Raw -Encoding utf8|ConvertFrom-Json
        $receipt.Suite|Should -BeExactly 'Git'
        $receipt.Workers|Should -BeGreaterThan 0
        $receipt.Workers|Should -BeLessOrEqual 4
        $receipt.TestRunElapsedMs|Should -BeGreaterThan 0
    }

    It 'does not publish a measurement when the companion test run fails' {
        $reports=[IO.Path]::Combine($root,'run-fail')
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @(
            '-WorkspaceRoot',$root,'-Suite','Git','-Campaign','performance','-RunDirectory',$reports
        ) -Environment @{GITHUB_ACTIONS='';QUIETCLI_PROFILE_COMPANION='';QUIETCLI_COMPONENT_FIXTURE_FAIL='true'} -TimeoutSeconds 35
        $result.ExitCode|Should -Be 1
        ($result.Output+$result.Error)|Should -Match 'Fixture test failed'
        [IO.File]::Exists([IO.Path]::Combine($reports,'component-performance.json'))|Should -BeFalse
    }
}
