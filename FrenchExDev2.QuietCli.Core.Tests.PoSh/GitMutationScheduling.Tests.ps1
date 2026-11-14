function Test-QuietGitMutationScheduling {
    <#
    .SYNOPSIS
    Verifies compiler-catalogue isolation and pristine forced builds through an independent process double.
    .PARAMETER WorkspaceRoot
    Checkout supplying the Git runner, catalogue and scheduling declarations.
    .PARAMETER RunDirectory
    Owned fixture and evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $manifest=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.Tests.PoSh/FrenchExDev2.QuietCli.Git.Tests.PoSh.psd1'
    $inventory=Get-QuietCompanionTestInventory -ManifestPath $manifest
    $policy=Get-QuietTestExecutionPolicy -ManifestPath $manifest -CaseNames $inventory.CaseNames
    $mutations=@('push targeted mutations are detected by independent assertions','repository command C# mutants are detected','query parser C# mutants are detected','attribution parser C# mutants are detected','pathquery parser C# mutants are detected','argument filter C# mutants are detected','schema parser C# mutants are detected','invocation parser C# mutants are detected','revision parser C# mutants are detected')
    $ordered=@($inventory.CaseNames|Where-Object {$_ -cnotin $mutations})+$mutations
    $plan=Get-QuietTestExecutionPlan -CaseNames $ordered -Policy $policy -MaxConcurrency 8
    Assert-QuietEqual $plan.MaxConcurrency 2
    $parallel=@($plan.Stages|Where-Object Mode -CEQ IsolatedProcess)
    Assert-QuietEqual $parallel.Count 1
    Assert-QuietEqual $parallel[0].Cases.Count 9
    Assert-QuietEqual $plan.Stages[-1].Mode IsolatedProcess
    $fixture=Join-Path $RunDirectory 'git-mutation-build-fixture'
    $engine='FrenchExDev2.QuietCli.Git.PoSh/engine';$tests='FrenchExDev2.QuietCli.Git.Tests.PoSh/parser-tests'
    foreach($path in @('scripts/lib',$engine,$tests)){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $path))}
    foreach($name in @('global.json','Directory.Build.props','Directory.Packages.props')){Copy-Item (Join-Path $WorkspaceRoot $name) $fixture}
    Copy-Item (Join-Path $WorkspaceRoot 'scripts/lib/ReportPaths.psm1') (Join-Path $fixture 'scripts/lib')
    Copy-Item (Join-Path $WorkspaceRoot ($engine+'/*')) (Join-Path $fixture $engine) -Include *.cs,*.csproj
    [IO.File]::WriteAllText((Join-Path $fixture ($tests+'/QuietCli.Git.Parser.Tests.csproj')),'<Project />',[Text.UTF8Encoding]::new($false))
    $definitions=Get-Content (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.Tests.PoSh/mutation/catalogues.json') -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
    Write-WorkspaceJson (Join-Path $fixture 'expected.json') @{Mutants=$definitions.Catalogues.Query.Mutants;ExpectedCases=$definitions.ExpectedCases;Prefix=$definitions.Catalogues.Query.CasePrefix}
    $mock=@'
function Invoke-CiProcess {
    param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds,$OnOutput,$State)
    $root=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($PSScriptRoot))
    $spec=Get-Content (Join-Path $root expected.json) -Raw -Encoding utf8|ConvertFrom-Json
    $ordinalPath=Join-Path $root ordinal.txt
    $ordinal=if(Test-Path $ordinalPath){[int](Get-Content $ordinalPath -Raw -Encoding utf8)}else{0}
    if($ArgumentList[0] -ceq 'build'){
        if($ArgumentList -cnotcontains '--no-incremental' -or (($ArgumentList -ccontains '--no-restore') -ne ($ordinal -gt 0))){throw 'MutationBuildPolicyChanged'}
        $stage=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($ArgumentList[1])) '../../FrenchExDev2.QuietCli.Git.PoSh/engine'))
        foreach($original in Get-ChildItem (Join-Path $root 'FrenchExDev2.QuietCli.Git.PoSh/engine') -Filter *.cs -File){
            $expected=[IO.File]::ReadAllText($original.FullName,[Text.Encoding]::UTF8)
            if($ordinal -gt 0){$m=$spec.Mutants[$ordinal-1];if($m.File -ceq $original.Name){$expected=$expected.Replace($m.From,$m.To)}}
            if([IO.File]::ReadAllText((Join-Path $stage $original.Name),[Text.Encoding]::UTF8) -cne $expected){throw 'MutationSourceLeakedAcrossBuilds'}
        }
        [IO.File]::WriteAllText($ordinalPath,[string]($ordinal+1),[Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{Outcome='Success';ExitCode=0}
    }
    $failed=if($ordinal -eq 1){0}else{1}
    $report=@{Passed=($spec.ExpectedCases-$failed);Failed=$failed;Cases=@(@{Name=($spec.Prefix+'independent fixture assertion');State=$(if($failed){'Failed'}else{'Passed'})})}
    & $OnOutput ([pscustomobject]@{Text=($report|ConvertTo-Json -Depth 5 -Compress);Stream='stdout'}) $State
    [pscustomobject]@{Outcome=$(if($failed){'Failed'}else{'Success'});ExitCode=$failed}
}
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'scripts/lib/Ci.Process.psm1'),$mock+"`n",[Text.UTF8Encoding]::new($false))
    . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.Tests.PoSh/Parser.Mutation.ps1')
    $reportRoot=Invoke-QuietGitParserMutation -WorkspaceRoot $fixture -Catalogue Query
    $report=Get-Content (Join-Path $reportRoot summary.json) -Raw -Encoding utf8|ConvertFrom-Json
    Assert-QuietEqual $report.Killed 8
    Assert-QuietEqual $report.BuildCount 9
    Assert-QuietEqual $report.RestoreCount 1
    Assert-QuietEqual $report.ForcedCompilation $true
    Write-WorkspaceJson (Join-Path $RunDirectory 'git-mutation-scheduling.json') @{IsolatedCatalogues=9;WorkerCap=2;PristineBuilds=$report.BuildCount;Restores=$report.RestoreCount;NativeBuildExecuted=$false}
}
