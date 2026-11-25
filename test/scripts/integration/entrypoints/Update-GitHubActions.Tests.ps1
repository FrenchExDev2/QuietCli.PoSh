#requires -Version 7.6
# Runs the real entry point in a child pwsh against a fixture checkout, offline: releases come from a catalog.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Update-GitHubActions.ps1')
    $oldCheckout='11d5960a326750d5838078e36cf38b85af677262'
    $newCheckout='3d3c42e5aac5ba805825da76410c181273ba90b1'
    $oldCache='0057852bfaa89a56745cba8c7296529d2fc39830'
    $newCache='55cc8345863c7cc4c66a329aec7e433d2d1c52a9'
    $workflow=@(
        'name: ci'
        'on: push'
        'jobs:'
        '  build:'
        '    runs-on: ubuntu-latest'
        '    steps:'
        "      - uses: actions/checkout@$oldCheckout # v4, reviewed upstream reference"
        '        with:'
        '          persist-credentials: false'
        '      - uses: ./.github/actions/setup'
        "      - uses: actions/cache/restore@$oldCache # v4.3.0"
        '      - uses: actions/upload-artifact@v4'
        '      - uses: octo/tool@main'
        '      - run: |'
        '          uses: octo/unrelated@v1'
        ''
        '          - uses: actions/upload-artifact@v4 # sample text'
        ''
    ) -join "`n"
    $action=@(
        'name: setup'
        'runs:'
        '  using: composite'
        '  steps:'
        "    - uses: actions/cache@$oldCache"
        ''
    ) -join "`n"
    $catalog=@{
        'actions/checkout'=@{Tag='v7.0.1';Sha=$newCheckout}
        'actions/cache'=@{Tag='v6.1.0';Sha=$newCache}
        'actions/upload-artifact'=@{Tag='v7.0.2';Sha='cf430e030ddbb5b0abf93d22962f4752f3646cd9'}
        'octo/tool'=@{Tag='v1.0.0';Sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}
    }
    $hash={param([string]$Path)(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
    $newFixture={param([string]$Label,[string]$Receipt)
        $root=[IO.Path]::Combine($TestDrive,$Label)
        $files=@{
            Workflow=New-QuietTestFile ([IO.Path]::Combine($root,'.github','workflows','ci.yml')) $workflow
            Action=New-QuietTestFile ([IO.Path]::Combine($root,'.github','actions','setup','action.yml')) $action
            Catalog=New-QuietTestFile ([IO.Path]::Combine($root,'catalog.json')) ($catalog|ConvertTo-Json -Depth 4)
        }
        $recorded=if($Receipt){$Receipt}else{& $hash $files.Workflow}
        $files.Document=New-QuietTestFile ([IO.Path]::Combine($root,'docs','ci','github','script-ci.md')) "# ci.yml`n`n<!-- workflow-source-sha256: $recorded -->`n`n## Purpose`n"
        [pscustomobject]@{Root=$root;Files=$files}
    }
    $state={param($Fixture)@(foreach($key in @('Workflow','Action','Document')){& $hash $Fixture.Files[$key]}) -join ','}
    $run={param($Fixture,[string[]]$Arguments,[switch]$Online)
        $catalogArguments=if($Online){@()}else{@('-ReleaseCatalogPath',$Fixture.Files.Catalog)}
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$Fixture.Root)+$catalogArguments+$Arguments) -TimeoutSeconds 120
        $result.TimedOut|Should -BeFalse
        $text=($result.Output+"`n"+$result.Error) -replace '\x1B\[[0-?]*[ -/]*[@-~]','' -replace '\s+',' '
        $result|Add-Member -NotePropertyName Text -NotePropertyValue $text -PassThru
    }
}

Describe 'Update-GitHubActions.ps1' {
    It 'reports the updates without writing anything when -Apply is absent' {
        $fixture=& $newFixture 'report'
        $before=& $state $fixture
        $result=& $run $fixture @()
        $result.ExitCode|Should -Be 0 -Because $result.Text
        & $state $fixture|Should -BeExactly $before
        $result.Text|Should -BeLike '*Summary: 5 reference(s) in 2 file(s); 4 to update in 2 file(s), 0 up to date, 1 skipped.*'
        $result.Text|Should -BeLike '*NotReleasePinned*'
        $result.Text|Should -BeLike '*Nothing written: run with -Apply*'
    }

    It 'writes nothing under -Apply -WhatIf and previews each file and its receipt' {
        $fixture=& $newFixture 'whatif'
        $before=& $state $fixture
        $result=& $run $fixture @('-Apply','-RefreshWorkflowReceipts','-WhatIf')
        $result.ExitCode|Should -Be 0 -Because $result.Text
        & $state $fixture|Should -BeExactly $before
        # The host may be localized ('What If :' on a French host): match the preview prefix loosely.
        $result.Text|Should -Match '(?i)what if ?:[^:]*?\.github/workflows/ci\.yml and docs/ci/github/script-ci\.md'
        $result.Text|Should -Match '(?i)what if ?:[^:]*?\.github/actions/setup/action\.yml'
        $result.Text|Should -BeLike '*Applied : False*'
        @(Get-ChildItem -LiteralPath $fixture.Root -Recurse -Filter '*.tmp').Count|Should -Be 0
    }

    It 'applies every update, keeps everything else byte for byte, and converges' {
        $fixture=& $newFixture 'apply'
        $receipt=[IO.File]::ReadAllText($fixture.Files.Document)
        $result=& $run $fixture @('-Appy','-Confirm:$false')
        $result.ExitCode|Should -Be 0 -Because $result.Text
        $expected=$workflow.Replace("actions/checkout@$oldCheckout # v4, reviewed upstream reference","actions/checkout@$newCheckout # v7.0.1, reviewed upstream reference").Replace("actions/cache/restore@$oldCache # v4.3.0","actions/cache/restore@$newCache # v6.1.0").Replace("      - uses: actions/upload-artifact@v4`n","      - uses: actions/upload-artifact@v7.0.2`n")
        [IO.File]::ReadAllText($fixture.Files.Workflow)|Should -BeExactly $expected
        [IO.File]::ReadAllText($fixture.Files.Action)|Should -BeExactly $action.Replace("actions/cache@$oldCache","actions/cache@$newCache # v6.1.0")
        [IO.File]::ReadAllText($fixture.Files.Document)|Should -BeExactly $receipt -Because 'receipts move only with -RefreshWorkflowReceipts'
        $again=& $run $fixture @('-Apply','-Confirm:$false')
        $again.ExitCode|Should -Be 0 -Because $again.Text
        $again.Text|Should -BeLike '*0 to update in 0 file(s), 4 up to date, 1 skipped.*'
    }

    It 'moves a current workflow receipt to the new hash with -RefreshWorkflowReceipts' {
        $fixture=& $newFixture 'receipt'
        $result=& $run $fixture @('-Apply','-RefreshWorkflowReceipts','-Confirm:$false')
        $result.ExitCode|Should -Be 0 -Because $result.Text
        [IO.File]::ReadAllText($fixture.Files.Document)|Should -BeExactly ("# ci.yml`n`n<!-- workflow-source-sha256: "+(& $hash $fixture.Files.Workflow)+" -->`n`n## Purpose`n")
    }

    It 'writes nothing when a workflow receipt is not current' {
        $fixture=& $newFixture 'stale' ('C'*64)
        $before=& $state $fixture
        $result=& $run $fixture @('-Apply','-RefreshWorkflowReceipts','-Confirm:$false')
        $result.ExitCode|Should -Not -Be 0
        $result.Text|Should -BeLike '*GitHubActionReceiptNotCurrent: docs/ci/github/script-ci.md*'
        & $state $fixture|Should -BeExactly $before
    }

    It 'writes nothing when one release is unknown' {
        $fixture=& $newFixture 'unknown'
        $partial=$catalog.Clone();$partial.Remove('actions/cache')
        $null=New-QuietTestFile $fixture.Files.Catalog ($partial|ConvertTo-Json -Depth 4)
        $before=& $state $fixture
        $result=& $run $fixture @('-Apply','-Confirm:$false')
        $result.ExitCode|Should -Not -Be 0
        $result.Text|Should -BeLike '*GitHubActionReleaseUnknown: actions/cache is not in the release catalog*'
        & $state $fixture|Should -BeExactly $before
    }

    It 'updates only the actions selected by -Include and -Exclude' {
        $fixture=& $newFixture 'filter'
        $actionBefore=& $hash $fixture.Files.Action
        $result=& $run $fixture @('-Apply','-Confirm:$false','-Include','actions/*','-Exclude','actions/cache')
        $result.ExitCode|Should -Be 0 -Because $result.Text
        $text=[IO.File]::ReadAllText($fixture.Files.Workflow)
        $text|Should -BeLike "*actions/checkout@$newCheckout # v7.0.1*"
        $text|Should -BeLike "*actions/cache/restore@$oldCache # v4.3.0*"
        $text|Should -BeLike '*octo/tool@main*'
        & $hash $fixture.Files.Action|Should -BeExactly $actionBefore
    }
}
