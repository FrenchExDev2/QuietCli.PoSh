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
    It 'previews staged, unstaged and untracked paths while respecting Git ignore rules' {
        $null=& $git @('checkout','-q','--detach',$baseRevision)
        $staged='test/scripts/unit/LocalStaged.Tests.ps1'
        $unstaged='docs/README.md'
        $untracked='test/scripts/unit/LocalUntracked.Tests.ps1'
        $ignored='docs/roadmaps/local-impact.md'
        foreach($path in $staged,$untracked,$ignored){
            $null=New-QuietTestFile ([IO.Path]::Combine($workspace,$path)) '# local impact fixture'
        }
        $null=& $git @('add','--',$staged)
        [IO.File]::AppendAllText([IO.Path]::Combine($workspace,$unstaged),"`n<!-- local impact fixture -->`n",[Text.UTF8Encoding]::new($false))
        try{
            $outputPath=[IO.Path]::Combine($TestDrive,'working-tree-output.txt')
            $before=& $git @('status','--porcelain=v1','--untracked-files=all')
            $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-WorkingTree','-OutputPath',$outputPath) -TimeoutSeconds 300
            $run.ExitCode | Should -Be 0 -Because ($run.Output+$run.Error)
            $report=[IO.File]::ReadAllText([IO.Path]::Combine($workspace,'artifacts','ci-plan','plan.json'),[Text.Encoding]::UTF8) | ConvertFrom-Json
            $report.Revision | Should -BeExactly 'working-tree'
            @($report.Plan.ChangedPaths | Sort-Object) -join ',' | Should -BeExactly "$unstaged,$staged,$untracked"
            $report.Plan.ToolingScope | Should -BeExactly 'scripts'
            $report.Plan.RunScriptTooling | Should -BeTrue
            $report.Plan.RunProducts | Should -BeFalse
            $report.Plan.ScriptTestsRequireBuild | Should -BeFalse
            $report.Plan.ScriptTests | Should -Contain 'unit/LocalStaged.Tests.ps1'
            $report.Plan.ScriptTests | Should -Contain 'unit/LocalUntracked.Tests.ps1'
            (& $git @('status','--porcelain=v1','--untracked-files=all')) | Should -BeExactly $before
        }finally{
            $null=& $git @('reset','-q','HEAD','--',$staged)
            $null=& $git @('restore','--',$unstaged)
            foreach($path in $staged,$untracked,$ignored){[IO.File]::Delete([IO.Path]::Combine($workspace,$path))}
        }
    }

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
        $observed.Values['run_layout']|Should -BeExactly 'true'
        $observed.Values['tooling_scope']|Should -BeExactly 'none'
        $observed.Values['script_tests']|Should -BeExactly '[]'
        $observed.Values['script_mutation_targets']|Should -BeExactly '[]'
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
        $observed.Values['tooling_scope']|Should -BeExactly 'none'
        @(& $suites $observed.Values).Count|Should -Be 0
        @(& $images $observed.Values).Count|Should -Be 0
    }

    It 'runs only the script tests <Tests> and mutation targets <Targets> when <Path> changes' -ForEach @(
        @{Path='test/scripts/unit/lib/ImpactFixture.Tests.ps1';Tests='unit/lib/ImpactFixture.Tests.ps1';Targets=''}
        @{Path='scripts/lib/ImpactFixture.psm1';Tests='';Targets=''}
        @{Path='scripts/Invoke-ImpactFixture.ps1';Tests='';Targets=''}
        @{Path='scripts/lib/CiPlanResults.psm1';Tests='unit/lib/CiPlanResults.Tests.ps1';Targets='CiPlanResults'}
    ) {
        $observed=& $plan (& $commit $Path)
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $observed.Values['tooling_scope']|Should -BeExactly 'scripts'
        $observed.Values['run_tooling']|Should -BeExactly 'true'
        $observed.Values['run_layout']|Should -BeExactly 'false' -Because 'script tests are the whole plan'
        $observed.Values['run_products']|Should -BeExactly 'false'
        $observed.Values['run_smokes']|Should -BeExactly 'false'
        $observed.Values['run_distribution']|Should -BeExactly 'false'
        @(& $suites $observed.Values).Count|Should -Be 0 -Because 'companion qualification after a script change is a manual dispatch'
        @(& $images $observed.Values).Count|Should -Be 0
        $selectedTests=[string[]](ConvertFrom-Json $observed.Values['script_tests'])
        $selectedTargets=[string[]](ConvertFrom-Json $observed.Values['script_mutation_targets'])
        foreach($name in @(([string]$Tests).Split(',',[StringSplitOptions]::RemoveEmptyEntries))){$selectedTests|Should -Contain $name}
        $selectedTests|Should -Contain 'unit/quality/Inventory.Tests.ps1' -Because 'the inventory reads every script'
        $selectedTests|Should -Not -Contain 'unit/lib/CiImpact.Tests.ps1' -Because 'nothing it reaches changed'
        (@($selectedTargets) -join ',')|Should -BeExactly ([string]$Targets)
    }

    It 'plans the edited mutation shard and its tests without a product or layout run' {
        $path='test/scripts/mutation.targets.psd1'
        $null=& $git @('checkout','-q','--detach',$baseRevision)
        $absolute=[IO.Path]::Combine($workspace,$path)
        $catalogueText=[IO.File]::ReadAllText($absolute,[Text.Encoding]::UTF8)
        $pattern=[regex]::new("(?s)(Name = 'SqliteDocumentation'.*?Break = )80")
        $edited=$pattern.Replace($catalogueText,'${1}81',1)
        $edited | Should -Not -BeExactly $catalogueText
        [IO.File]::WriteAllText($absolute,$edited,[Text.UTF8Encoding]::new($false))
        $null=& $git @('add','--',$path)
        $null=& $git @('commit','-q','-m','change one mutation target')
        $observed=& $plan (& $git @('rev-parse','HEAD'))
        $observed.Run.ExitCode | Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $observed.Values['run_products'] | Should -BeExactly 'false'
        $observed.Values['run_layout'] | Should -BeExactly 'false'
        $observed.Values['tooling_scope'] | Should -BeExactly 'scripts'
        $observed.Values['script_mutation_targets'] | Should -BeExactly '["SqliteDocumentation"]'
        $observed.Values['script_tests'] | Should -BeExactly '["unit/lib/SqliteDocumentation.Tests.ps1"]'
    }

    It 'runs every script test with coverage and every target when the test runner <Path> changes' -ForEach @(
        @{Path='scripts/lib/ScriptsTests.psm1'}
    ) {
        $observed=& $plan (& $commit $Path)
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $observed.Values['tooling_scope']|Should -BeExactly 'scripts'
        $observed.Values['script_tests']|Should -BeExactly 'all'
        $observed.Values['script_mutation_targets']|Should -BeExactly 'all'
        $observed.Values['run_layout']|Should -BeExactly 'false'
        $report=[IO.File]::ReadAllText([IO.Path]::Combine($workspace,'artifacts','ci-plan','impact.md'))
        $report|Should -Match 'Tooling: scripts\.'
        $report|Should -Match ('\| '+[regex]::Escape($Path)+' \|  \| unit/lib/CiImpact\.Tests\.ps1 \| Scripts \| script-test \| TestRunnerChanged \|')
    }

    It 'runs every companion and the tooling when an unknown shared input changes' {
        $observed=& $plan (& $commit 'build/impact-fixture.txt')
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        (& $suites $observed.Values) -join ','|Should -BeExactly ((@($catalogue.Companions.Keys)|Sort-Object -CaseSensitive) -join ',')
        (& $images $observed.Values) -join ','|Should -BeExactly ((& $suites $observed.Values) -join ',')
        $observed.Values['run_tooling']|Should -BeExactly 'true'
        $observed.Values['tooling_scope']|Should -BeExactly 'full'
        $observed.Values['script_tests']|Should -BeExactly 'all'
        $observed.Values['script_mutation_targets']|Should -BeExactly 'all'
        $observed.Values['run_layout']|Should -BeExactly 'true'
        @(& $smokes $observed.Values).Count|Should -Be 0 -Because 'a fully selected suite is never smoked'
    }

    It 'writes every output key once, in a stable order' {
        $observed=& $plan (& $commit 'docs/README-impact-keys.md')
        @($observed.Values.Keys) -join ','|Should -BeExactly 'suite,run_products,run_tooling,image_suites,matrix,run_distribution,run_layout,run_smokes,script_mutation_targets,script_tests,smoke_suites,tooling_scope'
    }

    It 'qualifies <Expected> in full on a manual dispatch of <Suite>, without reading a diff' -ForEach @(
        @{Suite='all';Expected='*';Tooling='full'},@{Suite='core';Expected='Core';Tooling='none'},@{Suite=' Git , Core ';Expected='Core,Git';Tooling='none'}
        @{Suite='Tooling';Expected='';Tooling='full'},@{Suite='core,tooling';Expected='Core';Tooling='full'}
    ) {
        $revision=& $commit 'docs/README-impact-dispatch.md'
        $outputPath=[IO.Path]::Combine($TestDrive,'dispatch-'+[guid]::NewGuid().ToString('N')+'.txt')
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot',$workspace,'-Revision',$revision,'-Event','workflow_dispatch','-Suite',$Suite,'-OutputPath',$outputPath) -Environment @{GITHUB_STEP_SUMMARY=''} -TimeoutSeconds 300
        $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
        $values=[ordered]@{}
        foreach($line in [IO.File]::ReadAllLines($outputPath)){$index=$line.IndexOf('=');$values[$line.Substring(0,$index)]=$line.Substring($index+1)}
        $all=(@($catalogue.Companions.Keys)|Sort-Object -CaseSensitive) -join ','
        $full=if($Expected -ceq '*'){$all}else{$Expected}
        (& $suites $values) -join ','|Should -BeExactly $full
        (& $images $values) -join ','|Should -BeExactly $full
        $values['run_products']|Should -BeExactly $(if($full){'true'}else{'false'})
        $values['run_tooling']|Should -BeExactly $(if($Tooling -ceq 'full'){'true'}else{'false'})
        $values['tooling_scope']|Should -BeExactly $Tooling
        $values['script_tests']|Should -BeExactly $(if($Tooling -ceq 'full'){'all'}else{'[]'})
        $values['script_mutation_targets']|Should -BeExactly $(if($Tooling -ceq 'full'){'all'}else{'[]'})
        $values['run_layout']|Should -BeExactly 'true'
        $values['run_distribution']|Should -BeExactly 'false'
        @($values.Keys) -join ','|Should -BeExactly 'suite,run_products,run_tooling,image_suites,matrix,run_distribution,run_layout,run_smokes,script_mutation_targets,script_tests,smoke_suites,tooling_scope'
        $report=[IO.File]::ReadAllText([IO.Path]::Combine($workspace,'artifacts','ci-plan','impact.md'))
        $report|Should -Match 'Base: manual-dispatch;'
        $report|Should -Match '\| workflow_dispatch \|.*\| full \| ManualDispatch \|'
    }

    It 'rejects <Name> with <Error> and writes no outputs' -ForEach @(
        @{Name='a dispatch with a base';Arguments=@('-Event','workflow_dispatch','-Suite','all','-Base','BASE');Error='CiImpactDispatchTakesNoBase'}
        @{Name='a diff event without a base';Arguments=@('-Event','push');Error='CiImpactBaseRequired'}
        @{Name='a suite outside a dispatch';Arguments=@('-Event','pull_request','-Base','BASE','-Suite','Core');Error='CiImpactSuiteRequiresDispatch'}
        @{Name='a dispatch without a suite';Arguments=@('-Event','workflow_dispatch');Error='CiDispatchSuiteRequired'}
        @{Name='a dispatch of an unknown companion';Arguments=@('-Event','workflow_dispatch','-Suite','Nope');Error='CiDispatchSuiteUnknown: Nope'}
    ) {
        $revision=& $commit 'docs/README-impact-reject.md'
        $outputPath=[IO.Path]::Combine($TestDrive,'reject-'+[guid]::NewGuid().ToString('N')+'.txt')
        $arguments=@($Arguments|ForEach-Object {if($_ -ceq 'BASE'){$baseRevision}else{$_}})
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$workspace,'-Revision',$revision,'-OutputPath',$outputPath)+$arguments) -Environment @{GITHUB_STEP_SUMMARY=''} -TimeoutSeconds 300
        $run.ExitCode|Should -Not -Be 0
        ($run.Output+$run.Error)|Should -Match ([regex]::Escape($Error))
        [IO.File]::Exists($outputPath)|Should -BeFalse
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
