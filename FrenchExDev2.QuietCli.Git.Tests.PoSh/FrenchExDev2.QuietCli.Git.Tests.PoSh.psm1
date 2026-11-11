foreach($library in @('TestCaseMetadata','TestCaseScheduling')){
    $path=Join-Path (Split-Path $PSScriptRoot -Parent) ('scripts/lib/'+$library+'.psm1')
    if(Test-Path -LiteralPath $path){Import-Module $path -ErrorAction Stop}
}
. (Join-Path $PSScriptRoot 'IndexOperations.Tests.ps1')
. (Join-Path $PSScriptRoot 'Revisions.Tests.ps1')
. (Join-Path $PSScriptRoot 'PathQueries.Tests.ps1')
. (Join-Path $PSScriptRoot 'Attribution.Tests.ps1')
. (Join-Path $PSScriptRoot 'Queries.Tests.ps1')
. (Join-Path $PSScriptRoot 'RepositoryCommands.Tests.ps1')
. (Join-Path $PSScriptRoot 'Parser.Mutation.ps1')
. (Join-Path $PSScriptRoot 'Migration.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiImages.Tests.ps1')
#requires -Version 7.6
. (Join-Path $PSScriptRoot 'Semantic.Tests.ps1')
function Invoke-GitFixture {
    <#
.SYNOPSIS
Prepares independent disposable Git fixtures through explicit direct analysis.
    .PARAMETER Directory
    Disposable working directory.
    .PARAMETER Arguments
    Native fixture preparation vector.
    .PARAMETER Environment
    Isolated test Git configuration.
    #>
    param([string]$Directory,[string[]]$Arguments,[hashtable]$Environment)
    $r=quiet -AsObject -Role Infrastructure -WorkingDirectory $Directory -Environment $Environment -Output {param($e,$r)} -FilePath git -ArgumentList $Arguments
    if($r.Outcome -ne 'Success'){throw ('FixtureGitFailed: '+($Arguments -join ' ')+' '+($r.Error|ConvertTo-Json -Depth 6 -Compress))}
}
function Invoke-QuietGitTests {
    <#
.SYNOPSIS
Tests independently prepared repositories, hook counts and local bare push targets.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace root.
    .PARAMETER OnProgress
    Receives name, state, passed and failed counters.
    .PARAMETER RunDirectory
    Owned evidence directory; defaults to the shared temporary report root.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'tests') ([guid]::NewGuid().ToString('N'))}
    $root=Join-Path $RunDirectory 'git-fixtures'
    $repo=Join-Path $root 'working';$bare=Join-Path $root 'remote.git'
    [void][IO.Directory]::CreateDirectory($repo)
    $environment=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_GLOBAL=(Join-Path $root 'empty.gitconfig');GIT_AUTHOR_NAME='QuietCli2 Test';GIT_AUTHOR_EMAIL='quietcli2@example.invalid';GIT_COMMITTER_NAME='QuietCli2 Test';GIT_COMMITTER_EMAIL='quietcli2@example.invalid';GIT_TERMINAL_PROMPT='0';GIT_EDITOR='false';GIT_SEQUENCE_EDITOR='false'}
    Invoke-GitFixture $repo @('init','--initial-branch=main') $environment
    Invoke-GitFixture $repo @('config','commit.gpgsign','false') $environment
    $performance=[Collections.Generic.List[object]]::new()
    $cases=[ordered]@{}
    $cases['compiled Git parsers preserve migration vectors and measure local costs']={foreach($sample in Measure-QuietGitMigration){$performance.Add($sample)}}
    $cases['compiled Git formats and argument bindings satisfy independent assertions']={
        $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
        $assembly=Join-Path $PSScriptRoot 'lib/parser-tests/QuietCli.Git.Parser.Tests.dll'
        $schema=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/metadata/Git.ArgumentSchema.json'
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($event,$runtime)if($event.Stream -eq 'stdout'){[void]$runtime.Data.Append($event.Text)}} -Complete {param($runtime)$runtime.Data.ToString()|ConvertFrom-Json} $dotnet $assembly $schema
        Assert-QuietEqual $r.Outcome Success 'Compiled Git suite process'
        Assert-QuietEqual $r.Data.Passed 57 'Compiled Git independent cases'
        Assert-QuietEqual $r.Data.Failed 0 'Compiled Git independent failures'
    }
    $cases['status distinguishes unborn state and Unicode untracked paths']={
        [void][IO.File]::WriteAllTextAsync((Join-Path $repo 'é test.txt'),'first',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -C git-status -WorkingDirectory $repo -Environment $environment git status
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.Unborn $true
        Assert-QuietEqual $r.Data.Counts.Untracked 1
        Assert-QuietEqual $r.Data.Entries[0].Path 'é test.txt'
        Invoke-QuietConformance $r
    }
    $cases['commit mutates once and exposes independently observed HEAD']={
        Invoke-GitFixture $repo @('add','--','é test.txt') $environment
        $hook=Join-Path $repo '.git/hooks/pre-commit'
        [void][IO.File]::WriteAllTextAsync($hook,"#!/bin/sh`nprintf x >> hook-count.txt`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        if(!$IsWindows){[IO.File]::SetUnixFileMode($hook,[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)}
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $environment git commit -m 'Independent first commit'
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.Before $null
        Assert-QuietEqual $r.Data.Changed $true
        Assert-QuietEqual ([IO.File]::ReadAllTextAsync((Join-Path $repo 'hook-count.txt'),[Text.Encoding]::UTF8).GetAwaiter().GetResult()) 'x'
        if($r.Data.After -notmatch '^[0-9a-f]{40}$'){throw 'Missing observed commit identity'}
    }
    $cases['status preserves staged and unstaged observation scope']={
        [void][IO.File]::WriteAllTextAsync((Join-Path $repo 'é test.txt'),'second',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $environment -- git status -- 'é test.txt'
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.Counts.Unstaged 1
        Assert-QuietEqual $r.Data.Scope.RemoteState 'local refs only'
    }
    $cases['push observes porcelain references against a local bare target']={
        Invoke-GitFixture $root @('init','--bare',$bare) $environment
        Invoke-GitFixture $repo @('remote','add','origin',$bare) $environment
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $environment git push -u origin main
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Data.References.Count 1
        Assert-QuietEqual $r.Data.References[0].Accepted $true
        Assert-QuietEqual $r.Data.References[0].To 'refs/heads/main'
        $verify=quiet -AsObject -WorkingDirectory $repo -Environment $environment git ls-remote origin refs/heads/main
        Assert-QuietEqual $verify.Data.References.Count 1
    }
    $cases['probe cache avoids repeated version subprocesses']={
        $a=quiet -AsObject -WorkingDirectory $repo -Environment $environment git status
        $b=quiet -AsObject -WorkingDirectory $repo -Environment $environment git status
        Assert-QuietEqual $a.Outcome Success ('Git handler: '+($a.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $b.Outcome Success ('Git handler: '+($b.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual @($b.Internal.Sources.Values|Where-Object Role -EQ Probe).Count 0
    }
    $cases['generic context flag and native Git -C remain distinct']={
        $r=quiet -AsObject -C project-context -Environment $environment git -C $repo status
        Assert-QuietEqual $r.Outcome Success ('Git handler: '+($r.Error|ConvertTo-Json -Depth 6 -Compress))
        Assert-QuietEqual $r.Context project-context
    }
    $cases['official inventory is not certified by enumeration']={
        $coverage=@(Get-QuietGitCoverage)
        Assert-QuietEqual $coverage.Count 183
        Assert-QuietEqual @($coverage|Where-Object EntireInventoryQualified).Count 0
    }
    if($env:QUIETCLI_GIT_PUSH_MUTATION -eq '1'){$cases['push targeted mutations are detected by independent assertions']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot}}
    if($env:QUIETCLI_GIT_COMMAND_MUTATION -eq '1'){$cases['repository command C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Repository}}
    $repositoryCases=Get-QuietRepositoryCommandCases -RootDirectory $root -Environment $environment -WorkspaceRoot $WorkspaceRoot
    foreach($entry in $repositoryCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI_GIT_QUERY_MUTATION -eq '1'){$cases['query parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Query}}
    $queryCases=Get-QuietGitQueryCases -RootDirectory $root -Environment $environment
    foreach($entry in $queryCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI_GIT_ATTRIBUTION_MUTATION -eq '1'){$cases['attribution parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Attribution}}
    $attributionCases=Get-QuietGitAttributionCases -RootDirectory $root -Environment $environment
    foreach($entry in $attributionCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI_GIT_PATH_QUERY_MUTATION -eq '1'){$cases['pathquery parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue PathQuery}}
    $pathCases=Get-QuietGitPathQueryCases -RootDirectory $root -Environment $environment -WorkspaceRoot $WorkspaceRoot
    foreach($entry in $pathCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    if($env:QUIETCLI_GIT_SCHEMA_MUTATION -eq '1'){$cases['argument filter C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue ArgumentFilter}}
    if($env:QUIETCLI_GIT_SCHEMA_MUTATION -eq '1'){$cases['schema parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Schema}}
    if($env:QUIETCLI_GIT_INVOCATION_MUTATION -eq '1'){$cases['invocation parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Invocation}}
    if($env:QUIETCLI_GIT_REVISION_MUTATION -eq '1'){$cases['revision parser C# mutants are detected']={$null=Invoke-QuietGitParserMutation -WorkspaceRoot $WorkspaceRoot -Catalogue Revision}}
    $revisionCases=Get-QuietGitRevisionCases -RootDirectory $root -Environment $environment
    foreach($entry in $revisionCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    $indexCases=Get-QuietGitIndexOperationCases -RootDirectory $root -Environment $environment -WorkspaceRoot $WorkspaceRoot
    foreach($entry in $indexCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    $semanticCases=Get-QuietGitSemanticCases -RootDirectory $root -Environment $environment
    foreach($entry in $semanticCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    $ciImageCases=Get-QuietGitCiImageCases -WorkspaceRoot $WorkspaceRoot
    foreach($entry in $ciImageCases.GetEnumerator()){$cases[$entry.Key]=$entry.Value}
    $caseMetadata=@{
        'compiled Git parsers preserve migration vectors and measure local costs'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'compiled Git formats and argument bindings satisfy independent assertions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'status distinguishes unborn state and Unicode untracked paths'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'commit mutates once and exposes independently observed HEAD'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'status preserves staged and unstaged observation scope'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'push observes porcelain references against a local bare target'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'probe cache avoids repeated version subprocesses'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'generic context flag and native Git -C remain distinct'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'official inventory is not certified by enumeration'=@{TestKind='Integration';Dependencies=@('FileSystem','EngineState')}
        'push targeted mutations are detected by independent assertions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_PUSH_MUTATION=1'}
        'repository command C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_COMMAND_MUTATION=1'}
        'query parser C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_QUERY_MUTATION=1'}
        'attribution parser C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_ATTRIBUTION_MUTATION=1'}
        'pathquery parser C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_PATH_QUERY_MUTATION=1'}
        'argument filter C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_SCHEMA_MUTATION=1'}
        'schema parser C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_SCHEMA_MUTATION=1'}
        'invocation parser C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_INVOCATION_MUTATION=1'}
        'revision parser C# mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState','DotNetBuild');EnabledWhen='QUIETCLI_GIT_REVISION_MUTATION=1'}
        'index update-index observes removal and re-add without altering worktree contents'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'index read-tree empties then restores tree and checkout-index restores file bytes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'index failed native operation retains observed state and never reports success'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'index generated scope properties and isolated mutants reject foreign destinations'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'revision rev-parse separates scalar paths exact booleans object IDs and mixed outputs'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'revision describe preserves tag suffix boundaries distances and always fallback'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'revision name-rev distinguishes native labels from IDs and keeps name-only mode'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'revision shortlog summaries retain counts without discarding full default subjects'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'pathquery grep quiet file lists native records and invalid expressions remain distinct'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'pathquery attribute NUL fields preserve requested values and path names'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'pathquery ignore rules preserve negation nonmatching groups and caller stdin framing'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'pathquery mailmap returns native canonical contacts in one business execution'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'pathquery raw diff files index tree and patch display preserve native comparison scope'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'pathquery raw rename paths preserve distinct source and destination'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'pathquery PowerShell mode properties and display flags have isolated mutation evidence'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'attribution blame preserves quoted Unicode paths content CR and uncommitted line IDs'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'attribution annotate shares the parser while preserving selected line ranges'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'attribution requested incremental blame output remains its native format'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'attribution reflog selectors messages predicates and explicit formats execute once'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'queries ls-files preserves selected paths stages and requested formatting'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'queries refs retain local fields quiet predicates and explicit remote advertisements'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'queries object IDs preserve requested input and revision parent relationships'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'queries merge-base distinguishes ancestor non-ancestor and native revision errors'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'queries counters versions ref validation and detached symbolic refs have explicit results'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository switch restore reset mv rm and clean preserve independently observed index state'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository merge exposes conflict failure and explicit abort without retry'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository cherry-pick revert and rebase execute one native operation with correct content'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository tag handles lightweight annotated listings and deletion'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository remote add rename URL and remove report only local configuration'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository config preserves duplicate multiline values empty values and missing queries'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository init and local clone observe explicit destinations including bare repositories'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository missing worktree blocks execution and native failure is not retried'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'repository PowerShell interaction properties and targeted guard mutants'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'fragmented patch preserves hunk lines that look like file headers'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'patch no-final-newline markers are retained as business facts'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'combined patch keeps all parent ranges'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'octal-quoted patch labels remain distinct instead of lossy decoding'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'non-UTF8 patch payload is represented without replacement characters'=@{TestKind='Integration';Dependencies=@('FileSystem')}
        'live diff has typed hunks and one business subprocess'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'explicit word-diff format is not silently treated as ordinary patch'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'default log returns full identity subject and body without a hidden cap'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'explicit log format and flag-looking values preserve their meaning'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'ls-tree preserves awkward Unicode quote space and newline index paths'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'show classifies binary blobs through Git and produces exact owned business content'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'show does not classify a colon inside an option value as a blob'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'branch mutation and listing expose independently observed reference changes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'stash mutation and listing have typed reference and subject fields'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'worktree list preserves porcelain identity and path'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'checkout executes once and observes symbolic HEAD without replay'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'add executes once and an independent status observes staged content'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'status short branch and untracked modes retain their declared scope'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'verbose status contains staged and unstaged business patches'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'status rename consumes a distinct original-path NUL record'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'status parser preserves an invalid UTF8 native path as bytes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'PTY machine-format handler refuses a merged terminal rather than reporting empty success'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'fetch and pull use a local remote and one business execution each'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'worktree mutation executes once and exposes independent before-after lists'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'gain filters select the business module without serializing its objects'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','GitProcess','EngineState')}
        'Git module CI image plan derives from its own files and from Core, never the reverse'=@{TestKind='Integration';Dependencies=@('FileSystem')}
    }
    $inventory=Get-QuietCompanionTestInventory -ManifestPath (Join-Path $PSScriptRoot 'FrenchExDev2.QuietCli.Git.Tests.PoSh.psd1')
    Assert-QuietTestCaseMetadata -CaseNames $inventory.CaseNames -Metadata $caseMetadata
    $passed=0;$failed=0;$ttyExcluded=0;$skipped=0;$stoppedAt=$null;$results=[Collections.Generic.List[object]]::new()
    $selected=[Collections.Generic.List[string]]::new()
    $activeMetadata=Get-QuietActiveCaseMetadata -Metadata $caseMetadata
    Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys) -Metadata $activeMetadata
    $pattern=$env:QUIETCLI_TEST_CASE;$stopOnFirst=$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE -ceq '1'
    foreach($name in $cases.Keys){
        if($env:QUIETCLI_TEST_SKIP_TTY -ceq '1' -and $name -clike 'PTY *'){$ttyExcluded++;continue}
        if($pattern -and $name -notlike $pattern){$skipped++;continue}
        $selected.Add($name)
    }
    $policy=Get-QuietTestExecutionPolicy -ManifestPath $inventory.ManifestPath -CaseNames $inventory.CaseNames
    $budget=1
    if($env:QUIETCLI_TEST_MAX_CONCURRENCY -and (![int]::TryParse($env:QUIETCLI_TEST_MAX_CONCURRENCY,[ref]$budget) -or $budget -lt 1 -or $budget -gt 32)){throw 'TestMaxConcurrencyInvalid'}
    $plan=Get-QuietTestExecutionPlan -CaseNames $selected.ToArray() -Policy $policy -MaxConcurrency $budget
    Write-WorkspaceJson (Join-Path $RunDirectory 'git-execution-plan.json') $plan
    $batches=[Collections.Generic.List[object]]::new()
    foreach($stage in $plan.Stages){
        if($stoppedAt){$skipped+=$stage.Cases.Count;continue}
        if($stage.Mode -ceq 'IsolatedProcess' -and $env:QUIETCLI_TEST_CASE_WORKER -cne '1'){
            $counts=@{Passed=$passed;Failed=$failed}
            $batch=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Cases $stage.Cases.ToArray() -SuiteName 'Git' -MaxConcurrency $plan.MaxConcurrency -StopOnFirstFailure:$stopOnFirst -SkipTty:($env:QUIETCLI_TEST_SKIP_TTY -ceq '1') -ExpectedRuntimeIdentifier $env:QUIETCLI_TEST_EXPECT_RID -OnCase {
                param($name,$caseState,$caseResult)
                if($caseState -ceq 'Passed'){$counts.Passed++}elseif($caseState -ceq 'Failed'){$counts.Failed++}
                if($OnProgress){& $OnProgress ('['+$caseMetadata[$name].TestKind+'] '+$name) $caseState $counts.Passed $counts.Failed}
            }
            $passed=$counts.Passed;$failed=$counts.Failed;$skipped+=$batch.NotStarted.Count;$batches.Add($batch)
            foreach($item in $batch.Cases){
                $item|Add-Member NoteProperty TestKind $caseMetadata[$item.Name].TestKind
                $item|Add-Member NoteProperty Dependencies @($caseMetadata[$item.Name].Dependencies)
                $results.Add($item)
            }
            if($stopOnFirst -and @($batch.Cases|Where-Object State -CEQ Failed).Count){$stoppedAt='Stopped after an observed failure'}
            continue
        }
        foreach($planned in $stage.Cases){
            if($stoppedAt){$skipped++;continue}
            $name=$planned.Name;$metadata=$caseMetadata[$name];$progressName='['+$metadata.TestKind+'] '+$name
            if($OnProgress){& $OnProgress $progressName 'Running' $passed $failed}
            $failure=$null
            try{$null=& $cases[$name];$passed++;$state='Passed'}catch{$failed++;$state='Failed';$failure=$_.Exception.Message}
            $results.Add([pscustomobject]@{Name=$name;State=$state;Error=$failure;TestKind=$metadata.TestKind;Dependencies=@($metadata.Dependencies);ExecutionMode=$planned.Mode})
            if($OnProgress){& $OnProgress $progressName $state $passed $failed}
            if($state -ceq 'Failed' -and $stopOnFirst){$stoppedAt='Stopped after an observed failure'}
        }
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Git.PoSh';Passed=$passed;Failed=$failed;Partial=[bool]$pattern;Incomplete=[bool]$stoppedAt;StoppedAt=$stoppedAt;Skipped=$skipped;TtyExcluded=$ttyExcluded;Cases=$results.ToArray();Performance=$performance.ToArray();FixtureDirectory=$root;EntireInventoryQualified=$false;ExecutionPlan=$plan;ParallelBatches=$batches.ToArray()}
}
Export-ModuleMember -Function Invoke-QuietGitTests
