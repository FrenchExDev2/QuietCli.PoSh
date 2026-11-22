#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name CiPlanReport
    $newPlan={
        [pscustomobject]@{
            FullSuites=@('Core','Git')
            SmokeSuites=@('Vagrant')
            ToolingScope='scripts'
            RunLayout=$false
            RunDistribution=$true
            ScriptTests=@('one','two')
            ScriptTestsRequireBuild=$true
            ScriptMutationTargets=@('TargetA','TargetB')
            Reasons=@([pscustomobject]@{
                Input='scripts/example.ps1'
                Package='Pkg'
                Project='Project'
                Companion='Scripts'
                Action='script-test'
                Reason="First | second`ncontinued"
            })
        }
    }
}

Describe 'Write-QuietCiPlanReport' {
    BeforeEach { Push-Location -LiteralPath $TestDrive }
    AfterEach { Pop-Location }

    It 'replaces a standalone report with complete UTF-8 Markdown and no sidecars' {
        $directory=[IO.Path]::Combine($TestDrive,'standalone')
        $target=New-QuietTestFile ([IO.Path]::Combine($directory,'prévision.md')) 'older plan'
        Write-QuietCiPlanReport -Plan (& $newPlan) -Base base -Revision head -MarkdownPath $target -Confirm:$false

        $expected=@'
# QuietCli selective CI

Base: base; candidate: head.

Full suites: Core, Git.
Smoke suites: Vagrant.
Tooling: scripts.
Layout tests: False.
Distribution: True.
Script test files: 2.
Script tests require a Core/Git build: True.
Script mutation targets: TargetA, TargetB.

| Changed input | Package | Consumer project | Companion | Action | Reason |
|---|---|---|---|---|---|
| scripts/example.ps1 | Pkg | Project | Scripts | script-test | First \| second continued |

Unselected scopes were not tested. Build/cache preparation is separate from qualification.
'@
        (Get-Content -LiteralPath $target -Raw -Encoding utf8) | Should -BeExactly ($expected.Replace("`r`n","`n")+"`n")
        @(Get-ChildItem -LiteralPath $directory -Force).Name | Should -BeExactly @('prévision.md')
        [IO.File]::Exists([IO.Path]::Combine($TestDrive,'plan.json')) | Should -BeFalse
    }

    It 'keeps the standard bundle and appends its Markdown to the GitHub summary' {
        $directory=[IO.Path]::Combine($TestDrive,'bundle')
        $summary=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'summary.md')) "previous`n"
        $plan=[pscustomobject]@{FullSuites=@();SmokeSuites=@();Reasons=@()}
        Write-QuietCiPlanReport -Plan $plan -Base base -Revision head -Directory $directory -SummaryPath $summary -Confirm:$false

        $json=Get-Content -LiteralPath ([IO.Path]::Combine($directory,'plan.json')) -Raw -Encoding utf8 | ConvertFrom-Json
        $json.Base | Should -BeExactly 'base'
        $json.Revision | Should -BeExactly 'head'
        $json.Plan.FullSuites.Count | Should -Be 0
        $markdown=Get-Content -LiteralPath ([IO.Path]::Combine($directory,'impact.md')) -Raw -Encoding utf8
        $markdown | Should -Not -Match 'Tooling:|Script test files:'
        (Get-Content -LiteralPath $summary -Raw -Encoding utf8) | Should -BeExactly ("previous`n"+$markdown)
    }

    It 'preserves an existing report and does not create a destination directory in preview' {
        $target=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'previous.md')) 'older plan'
        $missing=[IO.Path]::Combine($TestDrive,'missing','plan.md')
        Write-QuietCiPlanReport -Plan (& $newPlan) -MarkdownPath $target -WhatIf
        Write-QuietCiPlanReport -Plan (& $newPlan) -MarkdownPath $missing -WhatIf

        (Get-Content -LiteralPath $target -Raw -Encoding utf8) | Should -BeExactly 'older plan'
        [IO.Directory]::Exists([IO.Path]::GetDirectoryName($missing)) | Should -BeFalse
    }

    It 'removes the temporary file when a directory occupies the destination' {
        $directory=[IO.Path]::Combine($TestDrive,'occupied')
        $target=[IO.Path]::Combine($directory,'plan.md')
        [void][IO.Directory]::CreateDirectory($target)

        { Write-QuietCiPlanReport -Plan (& $newPlan) -MarkdownPath $target -Confirm:$false } | Should -Throw
        @(Get-ChildItem -LiteralPath $directory -Force).Name | Should -BeExactly @('plan.md')
        [IO.Directory]::Exists($target) | Should -BeTrue
    }
}
