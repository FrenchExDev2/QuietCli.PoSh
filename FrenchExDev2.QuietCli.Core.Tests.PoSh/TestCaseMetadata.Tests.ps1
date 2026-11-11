function Test-QuietCaseMetadata {
    <#
    .SYNOPSIS
    Checks the live catalogue, generated classifications, malformed entries and inert source mutations.
    .PARAMETER WorkspaceRoot
    Checkout containing the shared classification guard and read-only check.
    .PARAMETER RunDirectory
    Owned directory for source fixtures and the evidence receipt.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $runner=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1'
    $inventory=Get-QuietTestCaseInventory -Path $runner
    Assert-QuietEqual $inventory.Metadata['PowerShell functions have readable help and sources parse without errors'].TestKind Integration
    Assert-QuietEqual $inventory.Metadata['security audit counterexamples are closed with independent evidence'].TestKind Integration
    Assert-QuietEqual $inventory.Metadata['direct status callbacks preserve generated Unicode record digests'].TestKind Unit
    $random=[Random]::new(111187)
    foreach($iteration in 1..64){
        $names=@(for($index=0;$index -lt $random.Next(1,20);$index++){'case-é漢-'+$iteration+'-'+$index})
        $metadata=@{}
        foreach($name in $names){$metadata[$name]=if($random.Next(2)){@{TestKind='Unit';Dependencies=@()}}else{@{TestKind='Integration';Dependencies=@('FileSystem')}}}
        Assert-QuietTestCaseMetadata -CaseNames $names -Metadata $metadata
        Assert-QuietTestCaseMetadata -CaseNames @($names|Sort-Object -Descending) -Metadata $metadata
    }
    $bad=@(
        @{Names=@('a','hidden');Metadata=@{a=@{TestKind='Unit';Dependencies=@()}};Error='TestCaseMetadataMissing'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Unit';Dependencies=@()};orphan=@{TestKind='Unit';Dependencies=@()}};Error='TestCaseMetadataOrphan'},
        @{Names=@('a','A');Metadata=@{a=@{TestKind='Unit';Dependencies=@()}};Error='TestCaseMetadataDuplicate'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Unclassified';Dependencies=@()}};Error='TestCaseMetadataKindInvalid'},
        @{Names=@('a');Metadata=@{a=@{TestKind='unit';Dependencies=@()}};Error='TestCaseMetadataKindInvalid'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Unit';Dependencies=@('FileSystem')}};Error='TestCaseMetadataUnitHasDependencies'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Integration';Dependencies=@()}};Error='TestCaseMetadataIntegrationNeedsDependencies'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Integration';Dependencies='FileSystem'}};Error='TestCaseMetadataDependenciesInvalid'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Integration';Dependencies=@('Network')}};Error='TestCaseMetadataDependenciesInvalid'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Integration';Dependencies=@('FileSystem','FileSystem')}};Error='TestCaseMetadataDependenciesInvalid'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Unit'}};Error='TestCaseMetadataDependenciesInvalid'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Unit';Dependencies=@();TestKnd='Unit'}};Error='TestCaseMetadataFieldInvalid'},
        @{Names=@('a');Metadata=@{a=@{TestKind='Integration';Dependencies=@('FileSystem');NativeTransport='Unknown'}};Error='TestCaseMetadataTransportInvalid'}
    )
    foreach($sample in $bad){
        $rejected=$false
        try{Assert-QuietTestCaseMetadata -CaseNames $sample.Names -Metadata $sample.Metadata}catch{$rejected=$_.Exception.Message.StartsWith($sample.Error,[StringComparison]::Ordinal)}
        Assert-QuietEqual $rejected $true ('Malformed classification: '+$sample.Error)
    }
    $directory=Join-Path $RunDirectory 'test-case-metadata'
    $fixtureProject=Join-Path $directory 'FrenchExDev2.QuietCli.Core.Tests.PoSh'
    [void][IO.Directory]::CreateDirectory($fixtureProject)
    $path=Join-Path $fixtureProject 'FrenchExDev2.QuietCli.Core.Tests.PoSh.psm1'
    $source=@'
throw 'The checker must never execute this module'
function Invoke-QuietCoreTests {
    $cases=[ordered]@{}
    $cases['a']={throw 'The checker must never execute this case'}
    $caseMetadata=@{'a'=@{TestKind='Unit';Dependencies=@()}}
}
'@
    [IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($false))
    Assert-QuietEqual (Get-QuietTestCaseInventory -Path $path).Count 1
    $mutants=@(
        @("TestKind='Unit'","TestKind='Unclassified'"),
        @("'a'=@{TestKind","'renamed'=@{TestKind"),
        @("`$cases['a']={","`$cases['a']={};`$cases['a']={"),
        @("`$cases['a']={","`$cases[`$dynamic]={"),
        @("`$caseMetadata=@{","`$caseMetadata=Get-Item;`$ignored=@{"),
        @("`$caseMetadata=@{","`$caseMetadata=@{};`$caseMetadata=@{")
    )
    foreach($mutation in $mutants){
        if(!$source.Contains($mutation[0])){throw 'TestCaseMetadataMutationAnchorMissing'}
        [IO.File]::WriteAllText($path,$source.Replace($mutation[0],$mutation[1]),[Text.UTF8Encoding]::new($false))
        $rejected=$false;try{$null=Get-QuietTestCaseInventory -Path $path}catch{$rejected=$_.Exception.Message.StartsWith('TestCaseMetadata',[StringComparison]::Ordinal)}
        Assert-QuietEqual $rejected $true 'A damaged catalogue must fail without executing source'
        $gateRejected=$false;try{$null=& (Join-Path $WorkspaceRoot 'scripts/Test-TestCaseMetadata.ps1') -WorkspaceRoot $directory}catch{$gateRejected=$_.Exception.Message.StartsWith('TestCaseMetadata',[StringComparison]::Ordinal)}
        Assert-QuietEqual $gateRejected $true 'The actual check entry point must propagate each catalogue failure'
        $previewRejected=$false
        try{$null=& { $WhatIfPreference=$true; & (Join-Path $WorkspaceRoot 'scripts/Test-TestCaseMetadata.ps1') -WorkspaceRoot $directory }}catch{$previewRejected=$_.Exception.Message.StartsWith('TestCaseMetadata',[StringComparison]::Ordinal)}
        Assert-QuietEqual $previewRejected $true 'Commit previews must still reject damaged classifications'
    }
    # Check-only invocation must not rewrite its inputs or load the product as a side effect.
    $before=(Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash
    $check=& (Join-Path $WorkspaceRoot 'scripts/Test-TestCaseMetadata.ps1') -WorkspaceRoot $WorkspaceRoot
    Assert-QuietEqual $check.Cases $inventory.Count
    $preview=& { $WhatIfPreference=$true; & (Join-Path $WorkspaceRoot 'scripts/Test-TestCaseMetadata.ps1') -WorkspaceRoot $WorkspaceRoot }
    Assert-QuietEqual $preview.Cases $inventory.Count 'Read-only checks still run under inherited WhatIf'
    . (Join-Path $WorkspaceRoot 'scripts/ScriptReview.ps1')
    $review=@(Get-QuietScriptReview -WorkspaceRoot $WorkspaceRoot|Where-Object Path -CEQ 'scripts/Test-TestCaseMetadata.ps1')
    Assert-QuietEqual $review.Count 1
    Assert-QuietEqual $review[0].Mode ReadOnly
    Assert-QuietEqual $review[0].NeedsGuard $false 'The generator must not insert a guard that skips validation'
    Assert-QuietEqual (Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash $before
    $body=[IO.File]::ReadAllText($runner,[Text.Encoding]::UTF8)
    if($body.IndexOf('Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys)',[StringComparison]::Ordinal) -gt $body.IndexOf('$casePattern=$env:QUIETCLI_TEST_CASE',[StringComparison]::Ordinal) -or !$body.Contains('Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys)')){throw 'TestCaseMetadataGuardMustPrecedeFiltering'}
    $workflow=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/scripts-docs-check.yml'),[Text.Encoding]::UTF8)
    if(!$workflow.Contains("'FrenchExDev2.QuietCli.Core.Tests.PoSh/**'") -or !$workflow.Contains('run: ./scripts/Invoke-WorkspaceChecks.ps1')){throw 'TestCaseMetadataCiPathOrRegistryMissing'}
    Write-WorkspaceJson (Join-Path $directory 'summary.json') @{Cases=$inventory.Count;PropertyRuns=64;Malformed=$bad.Count;SourceMutantsKilled=$mutants.Count;ReadOnlyPreviewChecks=($mutants.Count+1);Seed=111187;SourceExecuted=$false}
}
