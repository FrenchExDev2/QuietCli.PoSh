#requires -Version 7.6
# Drives the orchestrator in-process against fixture checkouts, offline: releases come from a catalog.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name Update-GitHubActions
    $old='0057852bfaa89a56745cba8c7296529d2fc39830'
    $new='55cc8345863c7cc4c66a329aec7e433d2d1c52a9'
    $checkout='3d3c42e5aac5ba805825da76410c181273ba90b1'
    $catalogText=(@{
        'actions/cache'=@{Tag='v6.1.0';Sha=$new}
        'actions/checkout'=@{Tag='v7.0.1';Sha=$checkout}
    }|ConvertTo-Json -Depth 4)
    $hashOf={param([string]$Path)[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path)))}
    # Checkout with one workflow (cache/restore commit pin, checkout version tag), its document and a catalog.
    $newCheckout={param([string]$Workflow,[switch]$NoDocument)
        $root=[IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))
        $text=if($PSBoundParameters.ContainsKey('Workflow')){$Workflow}else{"jobs:`n  b:`n    steps:`n      - uses: actions/cache/restore@$old # v4.3.0`n      - uses: actions/checkout@v4`n"}
        $path=New-QuietTestFile ([IO.Path]::Combine($root,'.github','workflows','ci.yml')) $text
        $document=$null
        if(!$NoDocument){$document=New-QuietTestFile ([IO.Path]::Combine($root,'docs','ci','github','script-ci.md')) ("# ci`n`n<!-- workflow-source-sha256: "+(& $hashOf $path)+" -->`n")}
        [pscustomobject]@{Root=$root;Workflow=$path;Document=$document;Catalog=(New-QuietTestFile ([IO.Path]::Combine($root,'catalog.json')) $catalogText)}
    }
    $invoke={param($Fixture,[hashtable]$Extra=@{})
        Invoke-QuietScriptUpdateGitHubActions -WorkspaceRoot $Fixture.Root -ReleaseCatalogPath $Fixture.Catalog @Extra
    }
}

Describe 'Invoke-QuietScriptUpdateGitHubActions' {
    BeforeEach {Mock Write-Host {} -ModuleName Update-GitHubActions}

    It 'reports the plan without writing when -Apply is absent' {
        $fixture=& $newCheckout
        $before=& $hashOf $fixture.Workflow
        $result=& $invoke $fixture
        $result.Check|Should -BeExactly 'GitHubActions'
        $result.Files|Should -Be 1
        $result.References|Should -Be 2
        $result.Updates|Should -Be 2
        $result.PlannedFiles|Should -BeExactly @('.github/workflows/ci.yml')
        $result.WrittenFiles.Count|Should -Be 0
        $result.Applied|Should -BeFalse
        & $hashOf $fixture.Workflow|Should -BeExactly $before
        Should -Invoke Write-Host -ModuleName Update-GitHubActions -ParameterFilter {"$Object" -like 'Nothing written: run with -Apply*'} -Times 1 -Exactly
    }

    It 'reports one row per distinct reference, with the sub path and short commit ids' {
        $rows=(& $invoke (& $newCheckout)).Rows
        $rows.Count|Should -Be 2
        $rows[0].Action|Should -BeExactly 'actions/cache/restore'
        $rows[0].From|Should -BeExactly '0057852bfaa8 (v4.3.0)'
        $rows[0].To|Should -BeExactly '55cc8345863c (v6.1.0)'
        $rows[1].Action|Should -BeExactly 'actions/checkout'
        $rows[1].From|Should -BeExactly 'v4'
        $rows[1].To|Should -BeExactly 'v7.0.1'
    }

    It 'writes nothing under -Apply -WhatIf' {
        $fixture=& $newCheckout
        $before=(& $hashOf $fixture.Workflow)+(& $hashOf $fixture.Document)
        $result=& $invoke $fixture @{Apply=$true;RefreshWorkflowReceipts=$true;WhatIf=$true}
        $result.Applied|Should -BeFalse
        $result.WrittenFiles.Count|Should -Be 0
        $result.RefreshedReceipts.Count|Should -Be 0
        (& $hashOf $fixture.Workflow)+(& $hashOf $fixture.Document)|Should -BeExactly $before
    }

    It 'writes the updates and moves the receipt under -Apply -RefreshWorkflowReceipts' {
        $fixture=& $newCheckout
        $result=& $invoke $fixture @{Apply=$true;RefreshWorkflowReceipts=$true;Confirm=$false}
        $result.Applied|Should -BeTrue
        $result.WrittenFiles|Should -BeExactly @('.github/workflows/ci.yml')
        $result.RefreshedReceipts|Should -BeExactly @('docs/ci/github/script-ci.md')
        [IO.File]::ReadAllText($fixture.Workflow)|Should -BeExactly "jobs:`n  b:`n    steps:`n      - uses: actions/cache/restore@$new # v6.1.0`n      - uses: actions/checkout@v7.0.1`n"
        [IO.File]::ReadAllText($fixture.Document)|Should -BeExactly ("# ci`n`n<!-- workflow-source-sha256: "+(& $hashOf $fixture.Workflow)+" -->`n")
    }

    It 'leaves the receipt alone without -RefreshWorkflowReceipts' {
        $fixture=& $newCheckout
        $document=& $hashOf $fixture.Document
        $result=& $invoke $fixture @{Apply=$true;Confirm=$false}
        $result.RefreshedReceipts.Count|Should -Be 0
        & $hashOf $fixture.Document|Should -BeExactly $document
    }

    It 'writes a workflow without document and refreshes no receipt' {
        $fixture=& $newCheckout -NoDocument
        $result=& $invoke $fixture @{Apply=$true;RefreshWorkflowReceipts=$true;Confirm=$false}
        $result.WrittenFiles|Should -BeExactly @('.github/workflows/ci.yml')
        $result.RefreshedReceipts.Count|Should -Be 0
    }

    It 'keeps a UTF-8 BOM and CRLF line endings' {
        $fixture=& $newCheckout -NoDocument
        # Written as raw bytes: New-QuietTestFile normalizes line endings.
        [IO.File]::WriteAllBytes($fixture.Workflow,[byte[]](@(0xEF,0xBB,0xBF)+[Text.Encoding]::UTF8.GetBytes("jobs:`r`n  b:`r`n    steps:`r`n      - uses: actions/checkout@v4`r`n")))
        $null=& $invoke $fixture @{Apply=$true;Confirm=$false}
        $bytes=[IO.File]::ReadAllBytes($fixture.Workflow)
        $bytes[0..2]|Should -Be @(0xEF,0xBB,0xBF)
        [Text.Encoding]::UTF8.GetString($bytes,3,$bytes.Length-3)|Should -BeExactly "jobs:`r`n  b:`r`n    steps:`r`n      - uses: actions/checkout@v7.0.1`r`n"
    }

    It 'selects actions with -Include and removes them with -Exclude' -ForEach @(
        @{Include=@('actions/check*');Exclude=@();Updated=@('actions/checkout')}
        @{Include=@('*');Exclude=@('actions/checkout');Updated=@('actions/cache')}
        @{Include=@('actions/*');Exclude=@('*');Updated=@()}
        @{Include=@('octo/*');Exclude=@();Updated=@()}
    ) {
        $result=& $invoke (& $newCheckout) @{Include=$Include;Exclude=$Exclude}
        $result.References|Should -Be $Updated.Count
        (@($result.Rows|ForEach-Object {$_.Action -replace '/restore\z',''}) -join ',')|Should -BeExactly ($Updated -join ',')
    }

    It 'converges: a second run finds every reference up to date' {
        $fixture=& $newCheckout
        $null=& $invoke $fixture @{Apply=$true;Confirm=$false}
        $again=& $invoke $fixture @{Apply=$true;Confirm=$false}
        $again.Updates|Should -Be 0
        $again.UpToDate|Should -Be 2
        $again.PlannedFiles.Count|Should -Be 0
        $again.Applied|Should -BeFalse
    }

    It 'returns an empty report for a checkout without workflows' {
        $root=[IO.Path]::Combine($TestDrive,'empty')
        $catalog=New-QuietTestFile ([IO.Path]::Combine($root,'catalog.json')) '{}'
        $result=Invoke-QuietScriptUpdateGitHubActions -WorkspaceRoot $root -ReleaseCatalogPath $catalog -Apply -Confirm:$false
        $result.Files|Should -Be 0
        $result.References|Should -Be 0
        $result.Rows.Count|Should -Be 0
        $result.Applied|Should -BeFalse
    }

    It 'refuses a workflow that is not UTF-8' {
        $fixture=& $newCheckout -NoDocument
        [IO.File]::WriteAllBytes($fixture.Workflow,[byte[]]@(0x6A,0xFF,0xFE,0x0A))
        {& $invoke $fixture}|Should -Throw -ExpectedMessage 'GitHubActionFileNotUtf8: *ci.yml'
    }

    It 'refuses a stale receipt before writing anything' {
        $fixture=& $newCheckout
        $null=New-QuietTestFile $fixture.Document ("# ci`n`n<!-- workflow-source-sha256: "+('D'*64)+" -->`n")
        $before=& $hashOf $fixture.Workflow
        {& $invoke $fixture @{Apply=$true;RefreshWorkflowReceipts=$true;Confirm=$false}}|Should -Throw -ExpectedMessage 'GitHubActionReceiptNotCurrent: docs/ci/github/script-ci.md does not record the current .github/workflows/ci.yml; review it first'
        & $hashOf $fixture.Workflow|Should -BeExactly $before
    }

    It 'leaves a file edited after it was read untouched and leaves no temporary file' {
        $fixture=& $newCheckout -NoDocument
        $concurrent="jobs: {}`n"
        Mock Get-QuietGitHubActionRewrittenText -ModuleName Update-GitHubActions {
            [IO.File]::WriteAllText($fixture.Workflow,$concurrent)
            'rewritten'
        }
        {& $invoke $fixture @{Apply=$true;Confirm=$false}}|Should -Throw -ExpectedMessage 'GitHubActionSourceChanged: *ci.yml changed since it was read'
        [IO.File]::ReadAllText($fixture.Workflow)|Should -BeExactly $concurrent
        @(Get-ChildItem -LiteralPath $fixture.Root -Recurse -Filter '*.tmp').Count|Should -Be 0
    }
}
