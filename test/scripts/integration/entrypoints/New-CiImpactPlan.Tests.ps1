#requires -Version 7.6
BeforeDiscovery {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-QuietTestLibrary -Name CiCompanions
    $companionCases=@((Read-QuietCiCompanions -WorkspaceRoot (Get-QuietTestWorkspaceRoot)).Companions.Keys|ForEach-Object {@{Companion=$_}})
}

BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-QuietTestLibrary -Name CiCompanions
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'New-CiImpactPlan.ps1')
    $repository=Get-QuietTestWorkspaceRoot
    $yaml='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'
    $git={param([string[]]$Arguments)
        $output=& git -C $workspace -c user.name=quiet-test -c user.email=quiet-test@invalid -c core.autocrlf=false -c commit.gpgsign=false @Arguments 2>&1
        if($LASTEXITCODE){throw ('git '+($Arguments -join ' ')+': '+($output -join "`n"))}
        ($output -join "`n").Trim()
    }
    # The fixture is the working tree of this repository (tracked and new files) committed into a fresh repository,
    # so it runs on shallow CI checkouts and covers the catalogue under review, not the last commit.
    $workspace=[IO.Path]::Combine($TestDrive,'workspace')
    $listed=& git -C $repository ls-files -z --cached --others --exclude-standard
    if($LASTEXITCODE){throw 'git ls-files failed'}
    foreach($relative in @(($listed -join '').Split([char]0,[StringSplitOptions]::RemoveEmptyEntries)|Sort-Object -Unique)){
        $source=[IO.Path]::Combine($repository,$relative)
        if(![IO.File]::Exists($source)){continue}
        $target=[IO.Path]::Combine($workspace,$relative)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        [IO.File]::Copy($source,$target)
    }
    $null=& $git @('init','-q','-b','develop')
    $null=& $git @('add','-A')
    $null=& $git @('commit','-q','-m','base')
    $baseRevision=& $git @('rev-parse','HEAD')
    # The pinned YAML parser is a restored, ignored resource; copy it so the child never restores from the network.
    $parser=[IO.Path]::Combine($workspace,$yaml)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($parser))
    [IO.File]::Copy([IO.Path]::Combine($repository,$yaml),$parser)
    $catalogue=Read-QuietCiCompanions -WorkspaceRoot $workspace
    $dependents={param([string]$Name)
        $found=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
        $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($Name)
        while($queue.Count){
            $current=$queue.Dequeue()
            foreach($companion in $catalogue.Companions.Values){
                if(@($companion.requires) -ccontains $current -and $found.Add($companion.Name)){$queue.Enqueue($companion.Name)}
            }
        }
        [string[]]@($found)
    }
    $commit={param([string]$Path)
        $null=& $git @('checkout','-q','--detach',$baseRevision)
        $null=New-QuietTestFile ([IO.Path]::Combine($workspace,$Path)) "# impact fixture`n"
        $null=& $git @('add','--',$Path)
        $null=& $git @('commit','-q','-m',('touch '+$Path))
        & $git @('rev-parse','HEAD')
    }
    $plan={param([string]$Revision,[string[]]$Extra=@())
        $outputPath=[IO.Path]::Combine($TestDrive,'output-'+[guid]::NewGuid().ToString('N')+'.txt')
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-Revision',$Revision,'-Event','push','-OutputPath',$outputPath)+$Extra) -Environment @{GITHUB_STEP_SUMMARY=''} -TimeoutSeconds 300
        $values=[ordered]@{}
        if([IO.File]::Exists($outputPath)){
            foreach($line in [IO.File]::ReadAllLines($outputPath)){$index=$line.IndexOf('=');$values[$line.Substring(0,$index)]=$line.Substring($index+1)}
        }
        [pscustomobject]@{Run=$run;Values=$values;OutputPath=$outputPath}
    }
    $suites={param($Values)[string[]]@(($Values['matrix']|ConvertFrom-Json).include|ForEach-Object suite|Sort-Object -CaseSensitive)}
    $images={param($Values)[string[]]@(($Values['image_suites']|ConvertFrom-Json)|Sort-Object -CaseSensitive)}
    $smokes={param($Values)[string[]]@(($Values['smoke_suites']|ConvertFrom-Json)|Sort-Object -CaseSensitive)}
}

AfterAll {
    # Git writes its objects read-only on Windows; clear the flag so TestDrive can be removed.
    if($workspace -and [IO.Directory]::Exists($workspace)){
        foreach($file in [IO.Directory]::EnumerateFiles($workspace,'*',[IO.SearchOption]::AllDirectories)){[IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal)}
    }
}

Describe 'New-CiImpactPlan.ps1' {
    It 'selects exactly <Companion> when only its sources change, and smokes its dependents' -ForEach $companionCases {
        $source="src/$Companion/src/FrenchExDev2.QuietCli.$Companion.PoSh/Private/ImpactFixture.ps1"
        $observed=& $plan (& $commit $source)
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        (& $suites $observed.Values) -join ','|Should -BeExactly $Companion
        (& $images $observed.Values) -join ','|Should -BeExactly $Companion -Because 'the warm-up job prepares exactly the qualified suites'
        $expectedSmokes=[string[]](& $dependents $Companion)
        (& $smokes $observed.Values) -join ','|Should -BeExactly ($expectedSmokes -join ',')
        $observed.Values['suite']|Should -BeExactly $Companion
        $observed.Values['run_products']|Should -BeExactly 'true'
        $observed.Values['run_tooling']|Should -BeExactly 'false'
        $observed.Values['run_distribution']|Should -BeExactly 'false'
        $observed.Values['run_smokes']|Should -BeExactly $(if($expectedSmokes.Count){'true'}else{'false'})
        $row=($observed.Values['matrix']|ConvertFrom-Json).include[0]
        $row.solution_path|Should -BeExactly "src/$Companion/$Companion.slnx"
        $row.test_path|Should -BeExactly "src/$Companion/test"
    }

    It 'selects nothing for a documentation-only change' {
        $observed=& $plan (& $commit 'docs/README-impact-fixture.md')
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $observed.Values['suite']|Should -BeExactly 'None'
        $observed.Values['run_products']|Should -BeExactly 'false'
        $observed.Values['run_tooling']|Should -BeExactly 'false'
        $observed.Values['run_smokes']|Should -BeExactly 'false'
        @(& $suites $observed.Values).Count|Should -Be 0
        @(& $images $observed.Values).Count|Should -Be 0
    }

    It 'runs only the tooling when a script test changes' {
        $observed=& $plan (& $commit 'test/scripts/unit/lib/ImpactFixture.Tests.ps1')
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $observed.Values['run_tooling']|Should -BeExactly 'true'
        $observed.Values['run_products']|Should -BeExactly 'false'
        @(& $suites $observed.Values).Count|Should -Be 0
        @(& $images $observed.Values).Count|Should -Be 0
    }

    It 'runs every companion and the tooling when shared automation changes' {
        $observed=& $plan (& $commit 'scripts/lib/ImpactFixture.psm1')
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        (& $suites $observed.Values) -join ','|Should -BeExactly ((@($catalogue.Companions.Keys)|Sort-Object -CaseSensitive) -join ',')
        (& $images $observed.Values) -join ','|Should -BeExactly ((& $suites $observed.Values) -join ',')
        $observed.Values['run_tooling']|Should -BeExactly 'true'
        @(& $smokes $observed.Values).Count|Should -Be 0 -Because 'a fully selected suite is never smoked'
    }

    It 'writes every output key once, in a stable order' {
        $observed=& $plan (& $commit 'docs/README-impact-keys.md')
        @($observed.Values.Keys) -join ','|Should -BeExactly 'suite,run_products,run_tooling,image_suites,matrix,run_distribution,run_smokes,smoke_suites'
    }

    It 'fails with CiImpactCompleteDiffRequired when the base revision is unknown' {
        $revision=& $commit 'docs/README-impact-unknown.md'
        $outputPath=[IO.Path]::Combine($TestDrive,'unknown-base.txt')
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot',$workspace,'-Base',('0'*40),'-Revision',$revision,'-OutputPath',$outputPath) -Environment @{GITHUB_STEP_SUMMARY=''} -TimeoutSeconds 300
        $run.ExitCode|Should -Not -Be 0
        ($run.Output+$run.Error)|Should -Match 'CiImpactCompleteDiffRequired'
        [IO.File]::Exists($outputPath)|Should -BeFalse
    }

    It 'writes neither outputs nor the plan report under -WhatIf' {
        $revision=& $commit 'docs/README-impact-whatif.md'
        $report=[IO.Path]::Combine($workspace,'artifacts','ci-plan')
        if([IO.Directory]::Exists($report)){[IO.Directory]::Delete($report,$true)}
        $observed=& $plan $revision @('-WhatIf')
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        [IO.File]::Exists($observed.OutputPath)|Should -BeFalse
        [IO.Directory]::Exists($report)|Should -BeFalse
    }
}
