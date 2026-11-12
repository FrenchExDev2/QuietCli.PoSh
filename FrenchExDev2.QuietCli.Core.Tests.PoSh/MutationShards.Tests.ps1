function Test-QuietMutationShardContracts {
    <#
    .SYNOPSIS
    Verifies disjoint shard properties, malformed receipts and real no-write/export boundaries.
    .PARAMETER WorkspaceRoot
    Checkout supplying the authoritative catalogue and scripts.
    .PARAMETER RunDirectory
    Owned evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/MutationShards.psm1') -Force
    $catalogue=@((Import-PowerShellDataFile (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/RunProfiles.Mutation.Catalogue.psd1')).Mutants)
    $properties=0
    foreach($count in 1..16){
        $all=@(foreach($index in 0..($count-1)){Get-QuietMutationShard $catalogue $index $count})
        Assert-QuietEqual $all.Count $catalogue.Count
        Assert-QuietEqual (@($all.Name|Sort-Object -Unique).Count) $catalogue.Count
        foreach($index in 0..($count-1)){
            $shard=@(Get-QuietMutationShard $catalogue $index $count)
            foreach($entry in $shard){Assert-QuietEqual ([array]::IndexOf($catalogue.Name,$entry.Name)%$count) $index;$properties++}
        }
    }
    $hash=Get-QuietRunProfileMutationIdentity $WorkspaceRoot;$revision='b'*40
    $reports=@(foreach($index in 0..1){
        [pscustomobject]@{ShardIndex=$index;ShardCount=2;TotalCatalogue=$catalogue.Count;SourceSHA256=$hash;Revision=$revision;BaselinePassed=$true;Seed=61207;Iterations=120;Results=@(Get-QuietMutationShard $catalogue $index 2|ForEach-Object {[pscustomobject]@{Name=$_.Name;Outcome='Killed'}})}
    })
    Assert-QuietEqual (Assert-QuietMutationShards $reports $catalogue $hash $revision).Killed $catalogue.Count
    $serialized=ConvertTo-Json -InputObject $reports -Depth 8
    $damages=@(
        {param($r)$r[1].ShardIndex=0},
        {param($r)$r[1].ShardCount=3},
        {param($r)$r[1].BaselinePassed=$false},
        {param($r)$r[1].SourceSHA256='a'*64},
        {param($r)$r[1].Revision='c'*40},
        {param($r)$r[1].Iterations=10},
        {param($r)$r[1].Seed=1},
        {param($r)$r[1].Results=$r[1].Results[1..($r[1].Results.Count-1)]},
        {param($r)$r[1].Results[0].Name=$r[1].Results[1].Name},
        {param($r)$r[1].Results[0].Name='unknown-mutant'},
        {param($r)$r[1].Results[0].Outcome='Survived'},
        {param($r)$r[1].Results[0].Outcome='Crashed'},
        {param($r)$r[1].Results[0].Outcome='Invalid'},
        {param($r)$r[1].Results[0].Outcome='Timeout'}
    )
    foreach($damage in $damages){
        $bad=ConvertFrom-Json $serialized; & $damage $bad
        $rejected=$false;try{$null=Assert-QuietMutationShards $bad $catalogue $hash $revision}catch{$rejected=$true}
        Assert-QuietEqual $rejected $true 'Damaged shard evidence must block completeness'
    }
    foreach($bad in @(@($reports[0]),@($reports[0],$reports[1],$reports[0]))){
        $rejected=$false;try{$null=Assert-QuietMutationShards $bad $catalogue $hash $revision}catch{$rejected=$true};Assert-QuietEqual $rejected $true
    }
    $root=Join-Path $RunDirectory 'mutation-shard-fixtures';$output=Join-Path $root 'complete.json'
    $script=Join-Path $WorkspaceRoot 'scripts/Assert-RunProfileMutationShards.ps1'
    $null=& $script -ReportRoot $root -WorkspaceRoot $WorkspaceRoot -Revision $revision -OutputPath $output -WhatIf
    Assert-QuietEqual (Test-Path $root) $false
    foreach($index in 0..1){Write-WorkspaceJson (Join-Path $root "$index/run-profiles-mutation.json") $reports[$index]}
    $null=& $script -ReportRoot $root -WorkspaceRoot $WorkspaceRoot -Revision $revision -OutputPath $output
    Assert-QuietEqual ((Get-Content $output -Raw -Encoding utf8|ConvertFrom-Json).Complete) $true
    $bad=ConvertFrom-Json $serialized;$bad[0].Results[0].Outcome='Survived'
    Write-WorkspaceJson (Join-Path $root '0/run-profiles-mutation.json') $bad[0]
    $rejected=$false;try{$null=& $script -ReportRoot $root -WorkspaceRoot $WorkspaceRoot -Revision $revision -OutputPath (Join-Path $root 'rejected.json')}catch{$rejected=$true}
    Assert-QuietEqual $rejected $true
    Assert-QuietEqual (Test-Path (Join-Path $root 'rejected.json')) $false
    $source=(Get-Command Get-QuietMutationShard).ScriptBlock.ToString()
    $mutant=[scriptblock]::Create($source.Replace('$ordinal%$Count -eq $Index','$true'))
    Assert-QuietEqual @(& $mutant -Catalogue $catalogue -Index 0 -Count 2).Count $catalogue.Count 'A duplicate-all partition mutant must differ from a half catalogue'
    Write-WorkspaceJson (Join-Path $RunDirectory 'mutation-shard-properties.json') @{Properties=$properties;MalformedReceipts=$damages.Count+2;MutantsDetected=1;PreviewNoWrite=$true;Catalogue=$catalogue.Count}
}
