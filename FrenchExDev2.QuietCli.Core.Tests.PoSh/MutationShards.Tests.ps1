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
        [pscustomobject]@{ShardIndex=$index;ShardCount=2;TotalCatalogue=$catalogue.Count;SourceSHA256=$hash;Revision=$revision;BaselinePassed=$true;Seed=61207;Iterations=120;Partial=$true;Results=@(Get-QuietMutationShard $catalogue $index 2|ForEach-Object {[pscustomobject]@{Name=$_.Name;Outcome='Killed'}})}
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
        {param($r)$r[1].Partial=$false},
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
    Test-QuietGitHubMutationShardEntry -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
    Write-WorkspaceJson (Join-Path $RunDirectory 'mutation-shard-properties.json') @{Properties=$properties;MalformedReceipts=$damages.Count+2;MutantsDetected=1;PreviewNoWrite=$true;Catalogue=$catalogue.Count}
}

function Test-QuietGitHubMutationShardEntry {
    <#
    .SYNOPSIS
    Exercises the real GitHub entry with synthetic worker reports, including rejected partial products.
    .PARAMETER WorkspaceRoot
    Checkout supplying the entry point, validator and catalogue.
    .PARAMETER RunDirectory
    Owned parent report directory for disposable process fixtures.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $root=Join-Path $RunDirectory 'github-mutation-entry';$scripts=Join-Path $root 'scripts'
    [void][IO.Directory]::CreateDirectory((Join-Path $scripts 'lib'))
    $testRoot=Join-Path $root 'FrenchExDev2.QuietCli.Core.Tests.PoSh'
    [void][IO.Directory]::CreateDirectory($testRoot)
    foreach($name in @('New-RunProfile.ps1','Invoke-RunProfile.ps1','Measure-ColdStart.ps1','Initialize-Profilers.ps1','Ci.Process.ps1')){Copy-Item -LiteralPath (Join-Path $WorkspaceRoot ('scripts/'+$name)) -Destination (Join-Path $scripts $name)}
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'scripts/lib/MutationShards.psm1') -Destination (Join-Path $scripts 'lib/MutationShards.psm1')
    foreach($name in @('RunProfiles.Tests.ps1','RunProfiles.Benchmark.Tests.ps1','RunProfiles.Profiler.Tests.ps1','RunProfiles.Mutation.ps1','RunProfiles.MutationWorker.ps1','RunProfiles.Mutation.Catalogue.psd1')){Copy-Item -LiteralPath (Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.Tests.PoSh/'+$name)) -Destination (Join-Path $testRoot $name)}
    $entryPath=Join-Path $scripts 'Invoke-GitHubCi.ps1'
    $entrySource=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot 'scripts/Invoke-GitHubCi.ps1'),[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($entryPath,$entrySource,[Text.UTF8Encoding]::new($false))
    $workspaceStub=@'
function New-QuietWorkspaceSuiteParameter {
    param($WorkspaceRoot,$Scope)
    $attributes=[Collections.ObjectModel.Collection[Attribute]]::new()
    $attributes.Add([Management.Automation.ParameterAttribute]::new())
    $parameters=[Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $parameters.Add('Suite',[Management.Automation.RuntimeDefinedParameter]::new('Suite',[string],$attributes))
    return $parameters
}
'@
    $commonStub=@'
function Get-QuietWorkspaceProjects {param($WorkspaceRoot) @()}
function Write-WorkspaceFailureDiagnostics {param($Summary,$RunDirectory)}
'@
    $workerStub=@'
param($WorkspaceRoot,$RunDirectory,$Suite,[bool]$SkipTty,[int]$MaxConcurrency)
$response=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'response.json') -Raw -Encoding utf8|ConvertFrom-Json
foreach($item in @(@('summary.json',$response.Summary),@('run-profiles-mutation.json',$response.Report))){
    [IO.File]::WriteAllText((Join-Path $RunDirectory $item[0]),($item[1]|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
}
'@
    $harness=@'
param($Root,$Run,$Suite,$Index,$Count,[switch]$Preview)
$ErrorActionPreference='Stop'
$env:GITHUB_ACTIONS='true';$env:GITHUB_SHA='b'*40
$env:QUIETCLI_MUTATION_SHARD_INDEX=$Index;$env:QUIETCLI_MUTATION_SHARD_COUNT=$Count
$result=& (Join-Path $Root 'scripts/Invoke-GitHubCi.ps1') -WorkspaceRoot $Root -Suite $Suite -SkipBuild -RunDirectory $Run -WhatIf:$Preview
if(!$Preview){[IO.File]::WriteAllText((Join-Path $Run 'entry-result.json'),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
'@
    foreach($item in @(@('WorkspaceProjects.ps1',$workspaceStub),@('Common.ps1',$commonStub),@('Invoke-TestWorker.ps1',$workerStub))){[IO.File]::WriteAllText((Join-Path $scripts $item[0]),$item[1],[Text.UTF8Encoding]::new($false))}
    $harnessPath=Join-Path $root 'entry-harness.ps1'
    [IO.File]::WriteAllText($harnessPath,$harness,[Text.UTF8Encoding]::new($false))
    $catalogue=@((Import-PowerShellDataFile (Join-Path $testRoot 'RunProfiles.Mutation.Catalogue.psd1')).Mutants)
    $hash=Get-QuietRunProfileMutationIdentity $root
    $runEntry={
        param($response,[string]$name,[string]$suite='RunProfilesMutation',[string]$index='0',[string]$count='2',[switch]$Preview)
        Write-WorkspaceJson (Join-Path $root 'response.json') $response
        $run=Join-Path $root $name
        $arguments=@('-File',$harnessPath,'-Root',$root,'-Run',$run,'-Suite',$suite,'-Index',$index,'-Count',$count)
        if($Preview){$arguments+='-Preview'}
        $diagnostics=@{Lines=[Collections.Generic.Queue[string]]::new()}
        $process=Invoke-CiProcess -FilePath (Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})) -ArgumentList $arguments -WorkingDirectory $root -TimeoutSeconds 60 -State $diagnostics -OnOutput {param($e,$s)if($s.Lines.Count -ge 8){$null=$s.Lines.Dequeue()};$s.Lines.Enqueue($e.Text)}
        [pscustomobject]@{Success=($process.Outcome -ceq 'Success');Run=$run;Diagnostics=($diagnostics.Lines -join "`n")}
    }
    $positive=0;$rejected=0
    foreach($index in 0..1){
        $report=[pscustomobject]@{Partial=$true;ShardIndex=$index;ShardCount=2;TotalCatalogue=$catalogue.Count;SourceSHA256=$hash;Revision=('b'*40);BaselinePassed=$true;Seed=61207;Iterations=120;Results=@(Get-QuietMutationShard $catalogue $index 2|ForEach-Object {[pscustomobject]@{Name=$_.Name;Outcome='Killed'}})}
        $response=[pscustomobject]@{Report=$report;Summary=[pscustomobject]@{State=[pscustomobject]@{State='Success';Passed=46;Failed=0};Suites=@([pscustomobject]@{Project='RunProfiles';Mutation=$true;Partial=$true;Incomplete=$false;Passed=46;Failed=0;Skipped=0})}}
        $accepted=& $runEntry $response ('valid-'+$index) 'RunProfilesMutation' ([string]$index)
        Assert-QuietEqual $accepted.Success $true $accepted.Diagnostics
        $result=Get-Content -LiteralPath (Join-Path $accepted.Run 'entry-result.json') -Raw -Encoding utf8|ConvertFrom-Json
        Assert-QuietEqual $result.Partial $true 'A shard must not become complete qualification'
        Assert-QuietEqual $result.Passed 46
        $positive++
        if($index -eq 0){$valid=ConvertTo-Json -InputObject $response -Depth 10}
    }
    $damages=@(
        {param($r)$r.Report.BaselinePassed=$false},
        {param($r)$r.Report.ShardIndex=1},
        {param($r)$r.Report.ShardCount=3},
        {param($r)$r.Report.ShardCount='2'},
        {param($r)$r.Report.SourceSHA256='a'*64},
        {param($r)$r.Report.Revision='c'*40},
        {param($r)$r.Report.TotalCatalogue=91},
        {param($r)$r.Report.Seed=1},
        {param($r)$r.Report.Iterations=1},
        {param($r)$r.Report.Partial=$false},
        {param($r)$r.Report.Results=$r.Report.Results[1..45]},
        {param($r)$r.Report.Results[0].Name=$r.Report.Results[1].Name},
        {param($r)$r.Report.Results[0].Outcome='Survived'},
        {param($r)$r.Summary.Suites[0].Incomplete=$true},
        {param($r)$r.Summary.Suites[0].Partial=$false},
        {param($r)$r.Summary.Suites[0].Mutation=$false},
        {param($r)$r.Summary.Suites[0].Project='Core'},
        {param($r)$r.Summary.Suites[0].Passed=45},
        {param($r)$r.Summary.Suites[0].Skipped=1},
        {param($r)$r.Summary.State.State='Failed'},
        {param($r)$r.Summary.State.Passed=45},
        {param($r)$r.Summary.Suites+=$r.Summary.Suites[0]}
    )
    foreach($damage in $damages){
        $bad=ConvertFrom-Json $valid;& $damage $bad
        $result=& $runEntry $bad ('damaged-'+$rejected)
        Assert-QuietEqual $result.Success $false ('Damaged intermediate evidence was accepted: '+$rejected)
        $rejected++
    }
    foreach($context in @(@('RunProfilesMutation','',''),@('RunProfilesMutation','0',''),@('RunProfilesMutation','0','1'),@('RunProfilesMutation','2','2'),@('Git','0','2'))){
        $result=& $runEntry (ConvertFrom-Json $valid) ('context-'+$rejected) $context[0] $context[1] $context[2]
        Assert-QuietEqual $result.Success $false 'Shard controls cannot waive product/full-run completeness'
        $rejected++
    }
    $product=ConvertFrom-Json $valid;$product.Summary.Suites[0].Partial=$false
    $complete=& $runEntry $product 'complete-product' 'Git' '' ''
    Assert-QuietEqual $complete.Success $true $complete.Diagnostics
    $product.Summary.Suites[0].Incomplete=$true
    Assert-QuietEqual (& $runEntry $product 'incomplete-product' 'Git' '' '').Success $false
    $preview=& $runEntry (ConvertFrom-Json $valid) 'preview' 'RunProfilesMutation' '0' '2' -Preview
    Assert-QuietEqual $preview.Success $true $preview.Diagnostics
    Assert-QuietEqual (Test-Path -LiteralPath $preview.Run) $false
    $mutants=0
    try{
        $oldGuard=$entrySource.Replace('$mutationShard=$true','$mutationShard=$false')
        Assert-QuietEqual ($oldGuard -cne $entrySource) $true
        [IO.File]::WriteAllText($entryPath,$oldGuard,[Text.UTF8Encoding]::new($false))
        Assert-QuietEqual (& $runEntry (ConvertFrom-Json $valid) 'mutant-original-rejection').Success $false
        $mutants++
        $waivedGuard=$entrySource.Replace("throw 'GitHubCiRequiresCompleteUnfilteredSuites'",'$null')
        Assert-QuietEqual ($waivedGuard -cne $entrySource) $true
        [IO.File]::WriteAllText($entryPath,$waivedGuard,[Text.UTF8Encoding]::new($false))
        Assert-QuietEqual (& $runEntry (ConvertFrom-Json $valid) 'mutant-product-bypass' 'Git' '' '').Success $true
        $mutants++
    }finally{[IO.File]::WriteAllText($entryPath,$entrySource,[Text.UTF8Encoding]::new($false))}
    Write-WorkspaceJson (Join-Path $RunDirectory 'github-mutation-shard-entry.json') @{SyntheticWorker=$true;AcceptedShards=$positive;RejectedEvidenceAndContexts=($rejected+1);CompleteProductAccepted=$true;PreviewNoWrite=$true;GuardMutantsDetected=$mutants;HostedQualification=$false}
}
