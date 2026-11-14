Set-StrictMode -Version Latest

function Get-QuietMutationShard {
    <#
    .SYNOPSIS
    Partitions an ordered, uniquely named catalogue without omitting or repeating a mutant.
    .PARAMETER Catalogue
    Complete source-controlled mutation definitions.
    .PARAMETER Index
    Zero-based shard index.
    .PARAMETER Count
    Number of nonempty shards.
    #>
    param([object[]]$Catalogue,[int]$Index=0,[int]$Count=1)
    if(!$Catalogue.Count -or $Count -lt 1 -or $Count -gt $Catalogue.Count -or $Index -lt 0 -or $Index -ge $Count){throw 'MutationShardRangeInvalid'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in $Catalogue){if(!$entry.Name -or !$seen.Add($entry.Name)){throw 'MutationCatalogueNamesInvalid'}}
    for($ordinal=0;$ordinal -lt $Catalogue.Count;$ordinal++){if($ordinal%$Count -eq $Index){$Catalogue[$ordinal]}}
}

function Get-QuietRunProfileMutationIdentity {
    <#
    .SYNOPSIS
    Hashes the mutation subjects, tests and execution helpers without importing product code.
    .PARAMETER WorkspaceRoot
    Source checkout supplying the catalogue and its copied sandbox inputs.
    #>
    param([string]$WorkspaceRoot)
    $paths=@('scripts/New-RunProfile.ps1','scripts/Invoke-RunProfile.ps1','scripts/Measure-ColdStart.ps1','scripts/Initialize-Profilers.ps1','scripts/lib/Ci.Process.psm1')
    $paths+=@(Get-ChildItem -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib')) -File -Recurse | ForEach-Object {[IO.Path]::GetRelativePath($WorkspaceRoot,$_.FullName).Replace('\','/')})
    $paths+=@('RunProfiles.Tests.ps1','RunProfiles.Benchmark.Tests.ps1','RunProfiles.Profiler.Tests.ps1','RunProfiles.Mutation.ps1','RunProfiles.MutationWorker.ps1','RunProfiles.Mutation.Catalogue.psd1')|ForEach-Object {'FrenchExDev2.QuietCli.Core.Tests.PoSh/'+$_}
    $lines=@($paths|Sort-Object -Unique|ForEach-Object {$_+' '+(Get-FileHash -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,$_)) -Algorithm SHA256).Hash})
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))).ToLowerInvariant()
}

function Assert-QuietMutationShard {
    <#
    .SYNOPSIS
    Validates one complete partition while retaining its partial-catalogue evidence status.
    .PARAMETER Report
    Parsed mutation report from the selected worker.
    .PARAMETER Catalogue
    Authoritative complete mutation catalogue.
    .PARAMETER SourceSHA256
    Locally verified mutation input identity.
    .PARAMETER Revision
    Exact workflow revision.
    .PARAMETER Index
    Expected zero-based shard index, supplied independently of the report.
    .PARAMETER Count
    Expected shard count, supplied independently of the report.
    #>
    param($Report,[object[]]$Catalogue,[string]$SourceSHA256,[string]$Revision,[int]$Index,[int]$Count)
    if($SourceSHA256 -cnotmatch '\A[a-f0-9]{64}\z' -or $Revision -cnotmatch '\A[a-f0-9]{40}\z'){throw 'MutationShardEvidenceMissing'}
    $expected=@(Get-QuietMutationShard -Catalogue $Catalogue -Index $Index -Count $Count)
    if(($Report.ShardIndex -isnot [int] -and $Report.ShardIndex -isnot [long]) -or ($Report.ShardCount -isnot [int] -and $Report.ShardCount -isnot [long])){throw 'MutationShardIndexInvalid'}
    if($Report.ShardIndex -ne $Index -or $Report.ShardCount -ne $Count -or $Report.TotalCatalogue -ne $Catalogue.Count -or $Report.SourceSHA256 -cne $SourceSHA256 -or $Report.Revision -cne $Revision -or $Report.BaselinePassed -isnot [bool] -or !$Report.BaselinePassed -or $Report.Seed -ne 61207 -or $Report.Iterations -ne 120 -or $Report.Partial -isnot [bool] -or $Report.Partial -ne ($Count -gt 1)){throw 'MutationShardIdentityMismatch'}
    if($Report.Results.Count -ne $expected.Count){throw 'MutationShardCoverageIncomplete'}
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $expectedNames=@($expected|ForEach-Object Name)
    foreach($result in $Report.Results){
        if($result.Outcome -cne 'Killed' -or $result.Name -cnotin $expectedNames -or !$names.Add($result.Name)){throw 'MutationShardOutcomeOrCoverageInvalid'}
    }
    [pscustomobject]@{Partial=($Count -gt 1);ShardIndex=$Index;ShardCount=$Count;Selected=$expected.Count;Killed=$names.Count;Revision=$Revision;SourceSHA256=$SourceSHA256}
}

function Assert-QuietMutationShards {
    <#
    .SYNOPSIS
    Requires complete, source-identical, baseline-green mutation evidence across every shard.
    .PARAMETER Reports
    Parsed bounded shard documents from the same workflow revision.
    .PARAMETER Catalogue
    Authoritative complete mutation catalogue.
    .PARAMETER SourceSHA256
    Locally verified mutation input identity.
    .PARAMETER Revision
    Exact workflow revision, never a mutable branch name.
    .PARAMETER Count
    Expected shard count.
    #>
    param([object[]]$Reports,[object[]]$Catalogue,[string]$SourceSHA256,[string]$Revision,[int]$Count=2)
    if($Count -lt 1 -or $Reports.Count -ne $Count -or $SourceSHA256 -cnotmatch '\A[a-f0-9]{64}\z' -or $Revision -cnotmatch '\A[a-f0-9]{40}\z'){throw 'MutationShardEvidenceMissing'}
    $indices=[Collections.Generic.HashSet[int]]::new()
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($report in $Reports){
        if($report.ShardIndex -isnot [int] -and $report.ShardIndex -isnot [long]){throw 'MutationShardIndexInvalid'}
        if(!$indices.Add([int]$report.ShardIndex)){throw 'MutationShardIdentityMismatch'}
        $null=Assert-QuietMutationShard -Report $report -Catalogue $Catalogue -SourceSHA256 $SourceSHA256 -Revision $Revision -Index $report.ShardIndex -Count $Count
        foreach($result in $report.Results){
            if(!$names.Add($result.Name)){throw 'MutationShardOutcomeOrCoverageInvalid'}
        }
    }
    if($names.Count -ne $Catalogue.Count){throw 'MutationCatalogueCoverageIncomplete'}
    [pscustomobject]@{Complete=$true;Shards=$Count;Selected=$Catalogue.Count;Killed=$names.Count;Revision=$Revision;SourceSHA256=$SourceSHA256}
}

Export-ModuleMember -Function Get-QuietMutationShard,Get-QuietRunProfileMutationIdentity,Assert-QuietMutationShard,Assert-QuietMutationShards
