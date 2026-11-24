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
    $commitEntry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Commit-Workspace.ps1')
    $repository=Get-QuietTestWorkspaceRoot
    $yaml='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'
    $git={param([string[]]$Arguments)
        $output=& git -C $workspace @Arguments 2>&1
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
    # Child commit commands inherit this repository-local fixture configuration.
    $null=& $git @('config','--local','user.name','quiet-test')
    $null=& $git @('config','--local','user.email','quiet-test@invalid')
    $null=& $git @('config','--local','core.autocrlf','false')
    $null=& $git @('config','--local','commit.gpgsign','false')
    $null=& $git @('add','-A')
    # The production repository tracks this lock inside the ignored resources directory.
    $null=& $git @('add','-f','--','src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json')
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
    $plan={param([string]$Revision,[string[]]$Extra=@(),[string]$Trigger='push')
        $outputPath=[IO.Path]::Combine($TestDrive,'output-'+[guid]::NewGuid().ToString('N')+'.txt')
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-Revision',$Revision,'-Event',$Trigger,'-OutputPath',$outputPath)+$Extra) -Environment @{GITHUB_STEP_SUMMARY=''} -TimeoutSeconds 300
        $values=[ordered]@{}
        if([IO.File]::Exists($outputPath)){
            foreach($line in [IO.File]::ReadAllLines($outputPath)){$index=$line.IndexOf('=');$values[$line.Substring(0,$index)]=$line.Substring($index+1)}
        }
        [pscustomobject]@{Run=$run;Values=$values;OutputPath=$outputPath}
    }
    $suites={param($Values)[string[]]@(($Values['matrix']|ConvertFrom-Json).include|ForEach-Object suite|Sort-Object -CaseSensitive)}
    $images={param($Values)[string[]]@(($Values['image_suites']|ConvertFrom-Json)|Sort-Object -CaseSensitive)}
    $smokes={param($Values)[string[]]@(($Values['smoke_suites']|ConvertFrom-Json)|Sort-Object -CaseSensitive)}
    $commitPlanDriver=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'commit-plan-driver.ps1')) @'
param($Entry,$Workspace,[switch]$Preview,[string]$PlanPath,[switch]$Watch,[switch]$MergePullRequest)
$arguments = @{
    WorkspaceRoot = $Workspace
    Message = 'Exercise the commit plan contract'
    NoAll = $true
    WhatIf = $Preview
    Confirm = $false
    Watch = $Watch
    MergePullRequest = $MergePullRequest
    NoCommitFileSnifferWarning = $true
    SkipCheck = @('WorkspaceSolutions','CompanionWorkflows','ScriptLayout','PowerShellSources','TestCaseMetadata',
        'ScriptsReadme','GitHubWorkflowDocs','ScriptShouldProcess','ScriptAnalyzer','ScriptsInventory',
        'Resources','ScriptContracts','DocsCredits','Credits')
}
if ($PlanPath) { $arguments.CiPlanPath = $PlanPath }
& $Entry @arguments
'@
}

AfterAll {
    # Git writes its objects read-only on Windows; clear the flag so TestDrive can be removed.
    if($workspace -and [IO.Directory]::Exists($workspace)){
        foreach($file in [IO.Directory]::EnumerateFiles($workspace,'*',[IO.SearchOption]::AllDirectories)){[IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal)}
    }
}

Describe 'New-CiImpactPlan.ps1' {
    It 'keeps layout enabled when ReadyToRun is checked on a scripts-only pull request' {
        $revision=& $commit 'test/scripts/unit/lib/ImpactFixture.Tests.ps1'
        $root=Get-QuietTestWorkspaceRoot
        $description=[IO.File]::ReadAllText([IO.Path]::Combine($root,'.github/pull_request_template.md'),[Text.Encoding]::UTF8)
        $description=$description -creplace '(?m)^- \[ \](?=[^\r\n]*<!-- ci:readytorun -->\r?$)','- [x]'
        $output=[IO.Path]::Combine($TestDrive,'checklist-plan.txt')
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @(
            '-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-Revision',$revision,'-PullRequestBody',$description,'-OutputPath',$output
        ) -Environment @{GITHUB_STEP_SUMMARY=''}
        $run.ExitCode | Should -Be 0 -Because ($run.Output+$run.Error)
        $values=[IO.File]::ReadAllLines($output,[Text.Encoding]::UTF8)
        $values | Should -Contain 'tooling_scope=scripts'
        $values | Should -Contain 'run_products=false'
        $values | Should -Contain 'run_layout=true'
        $values | Should -Contain 'run_readytorun=true'
        $values | Should -Contain 'pr_ci_options=["readytorun"]'
    }

    It 'writes a standalone Markdown plan to a path relative to the checkout and honors preview' {
        $revision=& $commit 'docs/README-standalone-plan-fixture.md'
        $relative='.artifacts/standalone-plan.md'
        $markdown=[IO.Path]::Combine($workspace,$relative)
        $arguments=@('-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-Revision',$revision,'-MarkdownPath',$relative)
        $preview=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList ($arguments+@('-WhatIf'))
        $preview.ExitCode | Should -Be 0
        [IO.File]::Exists($markdown) | Should -BeFalse
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList $arguments
        $run.ExitCode | Should -Be 0 -Because ($run.Output+$run.Error)
        $text=Get-Content -LiteralPath $markdown -Raw -Encoding utf8
        $text | Should -Match ([regex]::Escape("Base: $baseRevision; candidate: $revision."))
        $text | Should -Match 'Tooling: none\.'
        $text | Should -Match 'Script test files: 0\.'
    }

    It 'generates the default plan from the new commit and ignores unstaged changes to a selected test' {
        $parent=& $commit 'docs/README-before-plan-fixture.md'
        $null=& $git @('update-ref','refs/remotes/origin/develop',$baseRevision)
        $path='test/scripts/unit/PlanCommitFixture.Tests.ps1'
        $file=New-QuietTestFile ([IO.Path]::Combine($workspace,$path)) "Describe 'commit plan fixture' { }`n"
        $null=& $git @('add','--',$path)
        Add-Content -LiteralPath $file -Encoding utf8 -Value '#ScriptsImpact: RequiresBuild'
        try {
            $run=Invoke-QuietTestScript -ScriptPath $commitPlanDriver -ArgumentList @($commitEntry,$workspace) -TimeoutSeconds 300
            $run.ExitCode | Should -Be 0 -Because ($run.Output+$run.Error)
            $revision=& $git @('rev-parse','HEAD')
            $revision | Should -Not -BeExactly $parent
            (& $git @('rev-parse','HEAD^')) | Should -BeExactly $parent
            $markdown=[IO.Path]::Combine($workspace,'artifacts','plan.md')
            $run.Output | Should -Match ([regex]::Escape($markdown))
            [IO.File]::Exists($markdown) | Should -BeTrue -Because ($run.Output+$run.Error)
            $text=Get-Content -LiteralPath $markdown -Raw -Encoding utf8
            $text | Should -Match ([regex]::Escape("Base: $baseRevision; candidate: $revision."))
            $text | Should -Match ([regex]::Escape($path))
            $text | Should -Match 'Script tests require a Core/Git build: False\.'
            (& $git @('status','--porcelain')) | Should -BeExactly ('M '+$path)
        } finally {
            $null=& $git @('restore','--worktree','--',$path)
        }
    }

    It 'writes an overridden destination only after a commit succeeds' {
        $parent=& $commit 'docs/README-before-custom-plan-fixture.md'
        $null=& $git @('update-ref','-d','refs/remotes/origin/develop')
        $path='.artifacts/custom-commit-plan.md'
        $markdown=[IO.Path]::Combine($workspace,$path)
        $arguments=@($commitEntry,$workspace,'-PlanPath',$path)
        $failed=Invoke-QuietTestScript -ScriptPath $commitPlanDriver -ArgumentList $arguments
        $failed.ExitCode | Should -Not -Be 0
        ($failed.Output+$failed.Error) | Should -Match 'CommitWorkspaceNothingStaged'
        [IO.File]::Exists($markdown) | Should -BeFalse

        $change='docs/README-custom-plan-fixture.md'
        $null=New-QuietTestFile ([IO.Path]::Combine($workspace,$change)) "# custom plan fixture`n"
        $null=& $git @('add','--',$change)
        $preview=Invoke-QuietTestScript -ScriptPath $commitPlanDriver -ArgumentList ($arguments+@('-Preview','-Watch','-MergePullRequest')) -TimeoutSeconds 300
        $preview.ExitCode | Should -Be 0 -Because ($preview.Output+$preview.Error)
        (& $git @('rev-parse','HEAD')) | Should -BeExactly $parent
        (& $git @('diff','--cached','--name-only')) | Should -BeExactly $change
        [IO.File]::Exists($markdown) | Should -BeFalse

        $run=Invoke-QuietTestScript -ScriptPath $commitPlanDriver -ArgumentList $arguments -TimeoutSeconds 300
        $run.ExitCode | Should -Be 0 -Because ($run.Output+$run.Error)
        $revision=& $git @('rev-parse','HEAD')
        $revision | Should -Not -BeExactly $parent
        [IO.File]::Exists($markdown) | Should -BeTrue -Because ($run.Output+$run.Error)
        (Get-Content -LiteralPath $markdown -Raw -Encoding utf8) | Should -Match ([regex]::Escape("Base: $parent; candidate: $revision."))
    }

    It 'returns the same plan with a null or omitted output path without writing reports' {
        $revision=& $commit 'docs/README-impact-object.md'
        $driver=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'read-plan-object.ps1')) @'
param($Entry,$Workspace,$Base,$Revision,$Mode,$OutputPath)
$arguments=@{WorkspaceRoot=$Workspace;Base=$Base;Revision=$Revision;AsObject=$true}
if($Mode -ceq 'Null'){$arguments.OutputPath=$null}
if($Mode -ceq 'File'){$arguments.OutputPath=$OutputPath}
$plan=@(& $Entry @arguments)
ConvertTo-Json -InputObject $plan -Depth 10 -Compress
'@
        $summary=[IO.Path]::Combine($TestDrive,'object-step-summary.md')
        $outputPath=[IO.Path]::Combine($TestDrive,'object-plan.txt')
        $reportPath=[IO.Path]::Combine($workspace,'artifacts','ci-plan','plan.json')
        $markdownPath=[IO.Path]::Combine($workspace,'artifacts','ci-plan','impact.md')
        $readReports={
            foreach($path in $reportPath,$markdownPath){
                if([IO.File]::Exists($path)){[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)}
            }
        }
        $before=ConvertTo-Json -InputObject @(& $readReports) -Compress
        $plans=@(foreach($mode in 'Omitted','Null','File'){
            $run=Invoke-QuietTestScript -ScriptPath $driver -ArgumentList @($entry,$workspace,$baseRevision,$revision,$mode,$outputPath) -Environment @{GITHUB_STEP_SUMMARY=$summary}
            $run.ExitCode | Should -Be 0 -Because ($run.Output+$run.Error)
            if($mode -cne 'File'){
                [IO.File]::Exists($outputPath) | Should -BeFalse
                [IO.File]::Exists($summary) | Should -BeFalse
                (ConvertTo-Json -InputObject @(& $readReports) -Compress) | Should -BeExactly $before
            }
            $observed=ConvertFrom-Json -InputObject $run.Output -NoEnumerate
            @($observed).Count | Should -Be 1
            $observed[0].ChangedPaths | Should -Be @('docs/README-impact-object.md')
            $observed[0].ToolingScope | Should -BeExactly 'none'
            $run.Output
        })
        $plans[0] | Should -BeExactly $plans[2]
        $plans[1] | Should -BeExactly $plans[2]
        [IO.File]::Exists($outputPath) | Should -BeTrue
        [IO.File]::Exists($summary) | Should -BeTrue
        [IO.File]::Exists($reportPath) | Should -BeTrue
        [IO.File]::Exists($markdownPath) | Should -BeTrue
    }

    It 'requires an output path for the existing file mode' {
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-Revision',$baseRevision)
        $run.ExitCode | Should -Not -Be 0
        ($run.Output+$run.Error) | Should -Match 'CiImpactOutputPathRequired'
    }

    It 'returns YAML with typed fields and leaves explicit job outputs in GitHub format' {
        $path='test/scripts/unit/YamlPreviewFixture.Tests.ps1'
        $revision=& $commit $path
        $summary=[IO.Path]::Combine($TestDrive,'yaml-step-summary.md')
        $outputPath=[IO.Path]::Combine($TestDrive,'yaml-job-outputs.txt')
        $arguments=@('-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-Revision',$revision,'-AsYaml')
        $yaml=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList $arguments -Environment @{GITHUB_STEP_SUMMARY=$summary}
        $yaml.ExitCode | Should -Be 0 -Because ($yaml.Output+$yaml.Error)
        $parsed=[YamlDotNet.Serialization.DeserializerBuilder]::new().WithAttemptingUnquotedStringTypeDeserialization().Build().Deserialize($yaml.Output)
        $parsed['ToolingScope'] | Should -BeExactly 'scripts'
        $parsed['RunProducts'] | Should -BeOfType [bool]
        $parsed['RunProducts'] | Should -BeFalse
        $parsed['ChangedPaths'] | Should -Be @($path)
        $parsed['Reasons'][0]['Action'] | Should -BeExactly 'script-test'
        [IO.File]::Exists($summary) | Should -BeFalse

        $file=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList ($arguments+@('-OutputPath',$outputPath)) -Environment @{GITHUB_STEP_SUMMARY=$summary}
        $file.ExitCode | Should -Be 0 -Because ($file.Output+$file.Error)
        $file.Output | Should -BeExactly $yaml.Output
        [IO.File]::ReadAllText($outputPath,[Text.Encoding]::UTF8) | Should -Match '(?m)^tooling_scope=scripts$'
        [IO.File]::Exists($summary) | Should -BeTrue
    }

    It 'rejects simultaneous object and YAML output formats' {
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot',$workspace,'-Base',$baseRevision,'-Revision',$baseRevision,'-AsObject','-AsYaml')
        $run.ExitCode | Should -Not -Be 0
        ($run.Output+$run.Error) | Should -Match 'CiImpactOutputFormatConflict'
    }

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

    It 'keeps the same CI job selection when a script commit also changes .gitignore' {
        $scriptRevision=& $commit 'scripts/lib/CiPlanResults.psm1'
        $withoutIgnore=& $plan $scriptRevision
        $withoutIgnore.Run.ExitCode|Should -Be 0 -Because ($withoutIgnore.Run.Output+$withoutIgnore.Run.Error)
        $withoutIgnore.Values['tooling_scope']|Should -BeExactly 'scripts'

        Add-Content -LiteralPath ([IO.Path]::Combine($workspace,'.gitignore')) -Encoding utf8 -Value '/ignore-impact-fixture/'
        $null=& $git @('add','--','.gitignore')
        $null=& $git @('commit','-q','-m','Update Git ignore rules')
        $withIgnore=& $plan (& $git @('rev-parse','HEAD'))
        $withIgnore.Run.ExitCode|Should -Be 0 -Because ($withIgnore.Run.Output+$withIgnore.Run.Error)

        (ConvertTo-Json -InputObject $withIgnore.Values -Compress)|Should -BeExactly (ConvertTo-Json -InputObject $withoutIgnore.Values -Compress)
        $receipt=Get-Content -LiteralPath ([IO.Path]::Combine($workspace,'artifacts','ci-plan','plan.json')) -Raw -Encoding utf8|ConvertFrom-Json
        $receipt.Plan.ChangedPaths|Should -Contain '.gitignore'
        $receipt.Plan.ConservativeFull|Should -BeFalse
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
        $pattern=[regex]::new("(?s)(Name = 'SqliteDocumentation'.*?Break = )100")
        $edited=$pattern.Replace($catalogueText,'${1}99',1)
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

    It 'passes the cache checkbox without expanding the selected script mutation targets' {
        $body=@'
<!-- quietcli-ci:begin -->
- [ ] Script mutation <!-- ci:script-mutation -->
- [x] Refresh mutation cache <!-- ci:script-mutation-no-input-cache -->
- [ ] Sequential <!-- ci:mutation-serial -->
- [ ] ReadyToRun <!-- ci:readytorun -->
- [ ] Preview <!-- ci:preview -->
<!-- quietcli-ci:end -->
'@
        $observed=& $plan (& $commit 'scripts/lib/SqliteDocumentation.psm1') @('-PullRequestBody',$body) 'pull_request'
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $observed.Values['script_mutation_no_input_cache']|Should -BeExactly 'true'
        $observed.Values['script_mutation_targets']|Should -BeExactly '["SqliteDocumentation"]'
    }

    It 'plans only the selected companion effects from the Git and Vagrant task-list checkboxes' {
        $body=Get-Content -LiteralPath ([IO.Path]::Combine($repository,'.github','pull_request_template.md')) -Raw -Encoding utf8
        foreach ($option in @('performance-git','profiling-vagrant')) {
            $checkbox=[regex]::new('(?m)^- \[ \](?= [^\r\n]* <!-- ci:' + $option + ' -->\r?$)')
            $checkbox.Matches($body).Count|Should -Be 1 -Because "the PR template has one unchecked $option item"
            $body=$checkbox.Replace($body,'- [x]')
        }
        $observed=& $plan (& $commit 'docs/README-ci-checklist.md') @('-PullRequestBody',$body) 'pull_request'
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $checks=($observed.Values['companion_checks']|ConvertFrom-Json).include
        $checks.suite|Should -BeExactly @('Git','Vagrant')
        $checks.campaign|Should -BeExactly @('performance','profiling')
        $observed.Values['run_companion_checks']|Should -BeExactly 'true'
        $observed.Values['run_products']|Should -BeExactly 'false'
        $observed.Values['script_mutation_targets']|Should -BeExactly '[]'
    }

    It 'selects image preparation without product tests for a renewal-only PR' {
        $body=Get-Content -LiteralPath ([IO.Path]::Combine($repository,'.github','pull_request_template.md')) -Raw -Encoding utf8
        $body=$body -creplace '(?m)^- \[ \](?= .*<!-- ci:renew-images-caches -->)', '- [x]'
        $observed=& $plan (& $commit 'docs/README-ci-image-renewal.md') @('-PullRequestBody',$body) 'pull_request'
        $observed.Run.ExitCode|Should -Be 0 -Because ($observed.Run.Output+$observed.Run.Error)
        $observed.Values['renew_image_caches']|Should -BeExactly 'true'
        $observed.Values['run_products']|Should -BeExactly 'false'
        (& $images $observed.Values) -join ','|Should -BeExactly ((@($catalogue.Companions.Keys)|Sort-Object -CaseSensitive) -join ',')
    }

    It 'writes every output key once, in a stable order' {
        $observed=& $plan (& $commit 'docs/README-impact-keys.md')
        $observed.Values['script_mutation_no_input_cache']|Should -BeExactly 'false'
        @($observed.Values.Keys) -join ','|Should -BeExactly 'suite,run_products,run_tooling,companion_checks,image_suites,matrix,mutation_parallel,pr_ci_options,renew_image_caches,run_companion_checks,run_distribution,run_layout,run_readytorun,run_smokes,script_mutation_no_input_cache,script_mutation_targets,script_tests,smoke_suites,tooling_scope'
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
        @($values.Keys) -join ','|Should -BeExactly 'suite,run_products,run_tooling,companion_checks,image_suites,matrix,mutation_parallel,pr_ci_options,renew_image_caches,run_companion_checks,run_distribution,run_layout,run_readytorun,run_smokes,script_mutation_no_input_cache,script_mutation_targets,script_tests,smoke_suites,tooling_scope'
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
