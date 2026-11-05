function New-QuietGitRepositoryFixture {
    <#
    .SYNOPSIS
    Creates an independent disposable repository for one repository-command workflow.
    .PARAMETER Root
    Owned fixture root.
    .PARAMETER Environment
    Isolated native Git configuration.
    #>
    param([string]$Root,[hashtable]$Environment)
    $path=Join-Path $Root ('repository-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($path)
    Invoke-GitFixture $path @('init','--initial-branch=main') $Environment
    [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"base`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    Invoke-GitFixture $path @('add','file.txt') $Environment
    Invoke-GitFixture $path @('commit','-m','baseline') $Environment
    return $path
}
function Test-QuietGitRepositoryInteraction {
    <#
    .SYNOPSIS
    Applies independent generated properties to the production interaction guard or one isolated mutant.
    .PARAMETER GuardSource
    Exact guard function source, compiled only in this local test scope.
    #>
    param([string]$GuardSource)
    . ([scriptblock]::Create($GuardSource))
    $vectors=@(@('restore','--patch'),@('reset','-p'),@('rebase','-i'),@('clean','-i'),@('config','--edit'),@('tag','--annotate'))
    $random=[Random]::new(72054)
    foreach($vector in $vectors){
        foreach($index in 1..40){
            $runtime=@{Request=@{}}
            $request=@{Name=$vector[0]}
            $binding=@{Options=@(@{Name=$vector[1];Value=('value'+$random.Next())});Subcommand=$null}
            $rejected=$false
            try{Assert-QuietGitInteraction $runtime $request $binding}catch{if($_.Exception.Message -ne 'ExplicitInteractionRequired'){throw};$rejected=$true}
            if(!$rejected){throw ('Interactive form executed without input: '+$vector[0])}
            $runtime.Request.InputText='explicit test input'
            Assert-QuietGitInteraction $runtime $request $binding
            $runtime.Request.Clear()
            # Flag-looking values must not be interpreted as interactive option names.
            $binding.Options=@(@{Name='--message';Value=$vector[1]})
            Assert-QuietGitInteraction $runtime $request $binding
        }
    }
}
function Get-QuietRepositoryCommandCases {
    <#
    .SYNOPSIS
    Creates command workflows and generated PowerShell guard qualification.
    .PARAMETER RootDirectory
    Owned fixture directory.
    .PARAMETER Environment
    Isolated Git configuration and noninteractive test editors.
    .PARAMETER WorkspaceRoot
    Source root for guard provenance and mutation reports.
    #>
    param([string]$RootDirectory,[hashtable]$Environment,[string]$WorkspaceRoot)
    $factory=Get-Command New-QuietGitRepositoryFixture;$prepare=Get-Command Invoke-GitFixture
    $assert=Get-Command Assert-QuietEqual;$success=Get-Command Assert-QuietGitSuccess
    $cases=[ordered]@{}
    $cases['repository switch restore reset mv rm and clean preserve independently observed index state']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git switch -c feature
        & $success $r;& $assert $r.Data.After.Branch feature
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"changed`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git restore -- file.txt
        & $success $r;& $assert $r.Data.Before.Counts.Unstaged 1;& $assert $r.Data.After.Clean $true
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"staged`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('add','file.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git reset -- file.txt
        & $success $r;& $assert $r.Data.Before.Counts.Staged 1;& $assert $r.Data.After.Counts.Staged 0;& $assert $r.Data.After.Counts.Unstaged 1
        & $prepare $path @('restore','file.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git mv -- file.txt 'renamed é.txt'
        & $success $r;& $assert $r.Data.After.Counts.Renamed 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rm -f -- 'renamed é.txt'
        & $success $r;& $assert (Test-Path -LiteralPath (Join-Path $path 'renamed é.txt')) $false
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'scratch.txt'),'scratch',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git clean -n -- scratch.txt
        & $success $r;& $assert (Test-Path -LiteralPath (Join-Path $path 'scratch.txt')) $true
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git clean -f -- scratch.txt
        & $success $r;& $assert (Test-Path -LiteralPath (Join-Path $path 'scratch.txt')) $false
    }.GetNewClosure()
    $cases['repository merge exposes conflict failure and explicit abort without retry']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('switch','-c','topic') $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"topic`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('commit','-am','topic') $Environment
        & $prepare $path @('switch','main') $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"main`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('commit','-am','main') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git merge --no-edit topic
        & $assert $r.Outcome Failed;& $assert $r.Data.State FailedWithConflicts;& $assert $r.Data.Conflicts 1
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git merge --abort
        & $success $r;& $assert $r.Data.After.Clean $true
    }.GetNewClosure()
    $cases['repository cherry-pick revert and rebase execute one native operation with correct content']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('switch','-c','topic') $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'topic.txt'),'topic',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('add','topic.txt') $Environment;& $prepare $path @('commit','-m','topic') $Environment
        & $prepare $path @('switch','main') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git cherry-pick topic
        & $success $r;& $assert (Test-Path -LiteralPath (Join-Path $path 'topic.txt')) $true
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git revert --no-edit HEAD
        & $success $r;& $assert (Test-Path -LiteralPath (Join-Path $path 'topic.txt')) $false
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rebase main topic
        & $success $r;& $assert $r.Data.After.Branch topic;& $assert $r.Data.After.Clean $true
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
    }.GetNewClosure()
    $cases['repository tag handles lightweight annotated listings and deletion']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git tag light
        & $success $r;& $assert $r.Data.ReferenceChanges[0].Kind Added
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git tag -a annotated -m 'Tag message'
        & $success $r
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git tag --list
        & $success $r;& $assert $r.Data.Tags.Count 2
        $tag=@($r.Data.Tags|Where-Object Name -EQ annotated)[0]
        & $assert $tag.Type tag
        if($tag.TargetObjectId -notmatch '^[a-f0-9]{40}(?:[a-f0-9]{24})?$'){throw 'Annotated target missing'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git tag -d light
        & $success $r;& $assert $r.Data.ReferenceChanges[0].Kind Removed
    }.GetNewClosure()
    $cases['repository remote add rename URL and remove report only local configuration']={
        $path=& $factory $RootDirectory $Environment
        $url=Join-Path $RootDirectory 'local remote.git'
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git remote add origin $url
        & $success $r;& $assert $r.Data.Before.Count 0;& $assert $r.Data.After.Count 2
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git remote rename origin upstream
        & $success $r;& $assert $r.Data.After[0].Name upstream
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git remote -v
        & $success $r;& $assert $r.Data.Remotes[0].Url $url
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git remote remove upstream
        & $success $r;& $assert $r.Data.After.Count 0
    }.GetNewClosure()
    $cases['repository config preserves duplicate multiline values empty values and missing queries']={
        $path=& $factory $RootDirectory $Environment
        foreach($value in @("é first`nsecond",'')){
            $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git config --local --add test.repeat $value
            & $success $r;& $assert $r.Data.Operation Write
        }
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git config --local --get-all test.repeat
        & $success $r;& $assert $r.Data.Values.Count 2;& $assert $r.Data.Values[0] "é first`nsecond";& $assert $r.Data.Values[1] ''
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git config --local --list
        & $success $r;& $assert @($r.Data.Entries|Where-Object Name -EQ test.repeat).Count 2
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git config --local --get test.missing
        & $success $r;& $assert $r.Data.Found $false;& $assert $r.Data.Values.Count 0
    }.GetNewClosure()
    $cases['repository init and local clone observe explicit destinations including bare repositories']={
        $source=& $factory $RootDirectory $Environment
        $target=Join-Path $RootDirectory ('clone-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $r=quiet -AsObject -WorkingDirectory $RootDirectory -Environment $Environment git clone -- $source $target
        & $success $r;& $assert $r.Data.DestinationObserved $true;& $assert $r.Data.Repository.Bare $false
        & $assert (Test-Path -LiteralPath (Join-Path $target 'file.txt')) $true
        $bare=Join-Path $RootDirectory ('bare-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $r=quiet -AsObject -WorkingDirectory $RootDirectory -Environment $Environment git init --bare $bare
        & $success $r;& $assert $r.Data.DestinationObserved $true;& $assert $r.Data.Repository.Bare $true
    }.GetNewClosure()
    $cases['repository missing worktree blocks execution and native failure is not retried']={
        $empty=Join-Path ([IO.Path]::GetTempPath()) ('qgit-empty-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($empty)
        $isolatedEnvironment=$Environment.Clone();$isolatedEnvironment.GIT_CEILING_DIRECTORIES=Split-Path $empty -Parent
        $missing='quietcli-missing-'+[guid]::NewGuid().ToString('N')
        $r=quiet -AsObject -WorkingDirectory $empty -Environment $isolatedEnvironment git rm -- $missing
        & $assert $r.Outcome Failed
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 0
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rm -- missing-file.txt
        & $assert $r.Outcome Failed;& $assert $r.Data.State Failed;& $assert $r.Data.Conflicts 0
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        & $assert (Test-Path -LiteralPath (Join-Path $path 'file.txt')) $true
    }.GetNewClosure()
    $guardTest=Get-Command Test-QuietGitRepositoryInteraction
    $cases['repository PowerShell interaction properties and targeted guard mutants']={
        $path=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/src/Semantics.ps1'
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-QuietGitInteraction'},$true)
        $source=$function.Extent.Text
        & $guardTest $source
        $mutants=@(@{Name='guard-disabled';From='if($interactive -and';To='if($false -and'},@{Name='explicit-input-rejected';From='if($interactive -and !@(';To='if($interactive -and @('})
        $results=@(foreach($mutant in $mutants){
            if(([regex]::Matches($source,[regex]::Escape($mutant.From))).Count -ne 1){throw 'GuardMutationSourceMismatch'}
            $killed=$false;try{& $guardTest $source.Replace($mutant.From,$mutant.To)}catch{$killed=$true}
            if(!$killed){throw ('GuardMutationSurvived: '+$mutant.Name)}
            @{Name=$mutant.Name;State='Killed'}
        })
        $report=Join-Path $RootDirectory 'repository-guard-mutation.json'
        [void][IO.File]::WriteAllTextAsync($report,(@{SourceSHA256=(Get-FileHash -LiteralPath $path).Hash;Seed=72054;GeneratedCases=240;Selected=2;Killed=2;Results=$results}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }.GetNewClosure()
    return $cases
}
