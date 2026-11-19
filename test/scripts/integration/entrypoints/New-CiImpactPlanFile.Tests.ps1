#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $entry = [IO.Path]::Combine((Get-QuietTestScriptsRoot), 'New-CiImpactPlanFile.ps1')
    $sha = 'a' * 40
    $newFixture = {
        $root = [IO.Path]::Combine($TestDrive, [guid]::NewGuid().ToString('N'))
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'New-CiImpactPlanFile.ps1')) ([IO.File]::ReadAllText($entry, [Text.Encoding]::UTF8))
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'New-CiImpactPlan.ps1')) @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$Base, [switch]$WorkingTree, [string]$OutputPath)
[IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot, 'invocation.txt'), $OutputPath, [Text.Encoding]::UTF8)
if ($env:QUIETCLI_TEST_PLAN_FAIL) { throw 'FixturePlannerFailure' }
if (!$WorkingTree) { throw 'ExpectedWorkingTree' }
[IO.File]::AppendAllText($OutputPath, "# base=$Base`n# scope=scripts — aperçu`n", [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Base = $Base }
'@
        # Export aliases for the fixture commands. The wrapper test does not exercise the real library exports.
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'lib', 'Ci.Process.psm1')) @'
function Invoke-FixtureMergeBase {
    param($FilePath, $ArgumentList, $WorkingDirectory, $State, $OnOutput)
    if ($FilePath -cne 'git' -or ($ArgumentList -join ' ') -cne 'merge-base origin/develop HEAD') {
        throw 'ExpectedMergeBase'
    }
    [IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot, '..', 'git-called.txt'), $WorkingDirectory, [Text.Encoding]::UTF8)
    & $OnOutput @{ Stream = 'stdout'; Text = 'a' * 40 } $State
    [pscustomobject]@{ Outcome = 'Success' }
}
$commandName = 'Invoke-' + 'CiProcess'
Set-Alias -Name $commandName -Value Invoke-FixtureMergeBase
Export-ModuleMember -Function Invoke-FixtureMergeBase -Alias $commandName
'@
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'lib', 'EditorExtensions.psm1')) @'
function Resolve-FixtureEditor {
    param([switch]$Insiders)
    $channel = if ($Insiders) { 'Insiders' } else { 'Stable' }
    [IO.File]::AppendAllLines([IO.Path]::Combine($PSScriptRoot, '..', 'editors.txt'), [string[]]@($channel), [Text.UTF8Encoding]::new($false))
    if ($env:QUIETCLI_TEST_EDITOR -cne $channel) { throw "FixtureEditorUnavailable: $channel" }
    [pscustomobject]@{ FilePath = [Environment]::ProcessPath }
}
$commandName = 'Resolve-' + 'DevelopmentEditorCli'
Set-Alias -Name $commandName -Value Resolve-FixtureEditor
Export-ModuleMember -Function Resolve-FixtureEditor -Alias $commandName
'@
        $root
    }
    $invoke = {
        param($Root, [string[]]$Arguments, [hashtable]$Environment = @{})
        Invoke-QuietTestScript -ScriptPath ([IO.Path]::Combine($Root, 'New-CiImpactPlanFile.ps1')) -ArgumentList $Arguments -Environment $Environment
    }
}

Describe 'New-CiImpactPlanFile.ps1' {
    BeforeEach { $root = & $newFixture }

    It 'uses both defaults and returns the UTF-8 file contents' {
        $run = & $invoke $root @('-GetContent')
        $scratch = [IO.File]::ReadAllText([IO.Path]::Combine($root, 'invocation.txt'), [Text.Encoding]::UTF8)
        try {
            $run.ExitCode | Should -Be 0 -Because ($run.Output + $run.Error)
            $run.Output | Should -Match ([regex]::Escape("# base=$sha"))
            $run.Output | Should -Match 'aperçu'
            Test-Path -LiteralPath $scratch -PathType Leaf | Should -BeTrue
            [IO.Path]::GetDirectoryName($scratch) | Should -Be ([IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath()))
            Test-Path -LiteralPath ([IO.Path]::Combine($root, 'git-called.txt')) | Should -BeTrue
        } finally {
            [IO.File]::Delete($scratch)
        }
    }

    It 'replaces the explicit output without accumulating lines (<Name>)' -ForEach @(
        @{ Name = 'spaces and accents'; Leaf = 'plan de prévision.txt' }
        @{ Name = 'literal brackets'; Leaf = 'plan[1].txt' }
    ) {
        $destination = [IO.Path]::Combine($root, 'nested folder', $Leaf)
        foreach ($attempt in 1, 2) {
            $run = & $invoke $root @('-Base', $sha, '-Output', $destination, '-GetContent')
            $run.ExitCode | Should -Be 0 -Because ($run.Output + $run.Error)
        }
        [IO.File]::ReadAllLines($destination, [Text.Encoding]::UTF8) | Should -Be @("# base=$sha", '# scope=scripts — aperçu')
        Test-Path -LiteralPath ([IO.Path]::Combine($root, 'git-called.txt')) | Should -BeFalse
    }

    It 'leaves the previous output intact if planning fails' {
        $destination = New-QuietTestFile ([IO.Path]::Combine($root, 'previous.txt')) 'previous result'
        $run = & $invoke $root @('-Base', $sha, '-OutputPath', $destination) @{ QUIETCLI_TEST_PLAN_FAIL = '1' }
        $run.ExitCode | Should -Not -Be 0
        [IO.File]::ReadAllText($destination, [Text.Encoding]::UTF8) | Should -Match 'previous result'
    }

    It 'tries Insiders before Stable and keeps the generated file (<Channel>)' -ForEach @(
        @{ Channel = 'Insiders'; Expected = 'Insiders'; ExitCode = 0 }
        @{ Channel = 'Stable'; Expected = 'Insiders,Stable'; ExitCode = 0 }
        @{ Channel = 'Neither'; Expected = 'Insiders,Stable'; ExitCode = 1 }
    ) {
        # The fake planner writes comments only. The test process accepts this file as its first argument.
        $destination = [IO.Path]::Combine($root, 'plan preview.ps1')
        $run = & $invoke $root @('-Base', $sha, '-OutputPath', $destination, '-Open', '-GetContent') @{ QUIETCLI_TEST_EDITOR = $Channel }
        $run.ExitCode | Should -Be $ExitCode -Because ($run.Output + $run.Error)
        [IO.File]::ReadAllLines([IO.Path]::Combine($root, 'editors.txt'), [Text.Encoding]::UTF8) -join ',' | Should -BeExactly $Expected
        Test-Path -LiteralPath $destination -PathType Leaf | Should -BeTrue
    }

    It 'does no planning, editor discovery or writing under WhatIf' {
        $destination = [IO.Path]::Combine($root, 'not-created', 'preview.txt')
        $run = & $invoke $root @('-OutputPath', $destination, '-Open', '-WhatIf')
        $run.ExitCode | Should -Be 0
        foreach ($path in $destination, ([IO.Path]::Combine($root, 'not-created')), ([IO.Path]::Combine($root, 'git-called.txt')), ([IO.Path]::Combine($root, 'invocation.txt')), ([IO.Path]::Combine($root, 'editors.txt'))) {
            Test-Path -LiteralPath $path | Should -BeFalse
        }
    }
}
