function Invoke-QuietGitStatusFixtureStep {
    <#
    .SYNOPSIS
    Runs one native preparation step whose non-zero exit is expected (a conflict that stops an operation).
    .DESCRIPTION
    Unlike Invoke-GitFixture, the exit code is returned instead of thrown so a scenario can stop Git mid-operation.
    .PARAMETER Directory
    Disposable working directory.
    .PARAMETER Arguments
    Native fixture preparation vector.
    .PARAMETER Environment
    Isolated test Git configuration.
    #>
    param([string]$Directory,[string[]]$Arguments,[hashtable]$Environment)
    $r=quiet -AsObject -Role Infrastructure -WorkingDirectory $Directory -Environment $Environment -Output {param($e,$r)} -FilePath git -ArgumentList $Arguments
    return $r.Execution.Native.ExitCode
}
function Write-QuietGitStatusFixtureFile {
    <#
    .SYNOPSIS
    Writes one UTF-8 fixture file asynchronously, creating its parent directory.
    .PARAMETER Path
    Absolute file path.
    .PARAMETER Content
    File content.
    #>
    param([string]$Path,[string]$Content)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllTextAsync($Path,$Content,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
}
function Get-QuietGitStatusCases {
    <#
    .SYNOPSIS
    Builds the git status scenarios: repository kinds, tracking state, HEAD states, in-progress operations,
    repository structure, typed failures, the hot-path digest and the published presentation events.
    .PARAMETER RootDirectory
    Owned disposable fixture root.
    .PARAMETER Environment
    Isolated Git environment.
    #>
    param([string]$RootDirectory,[hashtable]$Environment)
    $Environment=$Environment.Clone();$Environment.GIT_DEFAULT_HASH='sha1'
    $factory=Get-Command New-QuietGitRepositoryFixture;$prepare=Get-Command Invoke-GitFixture;$step=Get-Command Invoke-QuietGitStatusFixtureStep
    $write=Get-Command Write-QuietGitStatusFixtureFile;$success=Get-Command Assert-QuietGitSuccess;$assert=Get-Command Assert-QuietEqual
    $cases=[ordered]@{}
    $cases['status classifies non-repository bare and git-directory locations without running status']={
        $outside=Join-Path ([IO.Path]::GetTempPath()) ('qgit-status-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($outside)
        try{
            $isolated=$Environment.Clone();$isolated.GIT_CEILING_DIRECTORIES=Split-Path $outside -Parent
            $r=quiet -AsObject -WorkingDirectory $outside -Environment $isolated git status
            & $success $r;& $assert $r.Data.Repository.Kind NotARepository;& $assert $r.Data.Digest.Mode Classified
            & $assert $r.Data.Counts $null;& $assert $r.Data.Clean $null;& $assert $r.Data.AnswerComplete $true
            & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 0
        }finally{Remove-Item -LiteralPath $outside -Recurse -Force}
        $bare=Join-Path $RootDirectory ('status-bare-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        & $prepare $RootDirectory @('init','--bare','--initial-branch=trunk',$bare) $Environment
        $r=quiet -AsObject -WorkingDirectory $bare -Environment $Environment git status
        & $success $r;& $assert $r.Data.Repository.Kind Bare;& $assert $r.Data.Branch trunk;& $assert $r.Data.Digest.Mode Classified
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory (Join-Path $path '.git') -Environment $Environment git status
        & $success $r;& $assert $r.Data.Repository.Kind InsideGitDir;& $assert $r.Data.Digest.Mode Classified
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Repository.Kind WorkTree;& $assert $r.Data.Clean $true;& $assert $r.Data.Digest.Mode Clean
        & $assert $r.Data.Branch main;& $assert $r.Data.Upstream $null;& $assert $r.Data.AheadBehindComputed $null;& $assert $r.Data.StashCount 0
        & $assert @($r.Data.Operations).Count 0;& $assert $r.Data.Profile.Archetype Small;& $assert $r.Data.Profile.Checkout.IndexEntries 1
    }.GetNewClosure()
    $cases['status reports tracking state ahead behind gone and uncomputed divergence']={
        $path=& $factory $RootDirectory $Environment
        $remote=Join-Path $RootDirectory ('status-remote-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.git')
        & $prepare $RootDirectory @('init','--bare','--initial-branch=main',$remote) $Environment
        & $prepare $path @('remote','add','origin',$remote) $Environment
        & $prepare $path @('push','-u','origin','main') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Upstream origin/main;& $assert $r.Data.AheadBehindComputed $true;& $assert $r.Data.Ahead 0;& $assert $r.Data.Behind 0;& $assert $r.Data.UpstreamGone $false
        & $prepare $path @('commit','--allow-empty','-m','ahead') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Ahead 1;& $assert $r.Data.Behind 0
        & $prepare $path @('push','origin','main') $Environment
        & $prepare $path @('reset','--hard','HEAD~1') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Ahead 0;& $assert $r.Data.Behind 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status --no-ahead-behind
        & $success $r;& $assert $r.Data.AheadBehindComputed $false;& $assert $r.Data.Ahead $null;& $assert $r.Data.Behind $null;& $assert $r.Data.UpstreamGone $false
        & $prepare $path @('update-ref','-d','refs/remotes/origin/main') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Upstream origin/main;& $assert $r.Data.UpstreamGone $true;& $assert $r.Data.AheadBehindComputed $null;& $assert $r.Data.Ahead $null
    }.GetNewClosure()
    $cases['status exposes unborn staged and detached HEAD states']={
        $path=Join-Path $RootDirectory ('status-unborn-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        [void][IO.Directory]::CreateDirectory($path)
        & $prepare $path @('init','--initial-branch=main') $Environment
        & $write (Join-Path $path 'first.txt') 'first'
        & $prepare $path @('add','first.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Unborn $true;& $assert $r.Data.Branch main;& $assert $r.Data.Counts.Staged 1;& $assert $r.Data.Digest.Mode List
        & $assert $r.Data.Digest.Listed[0].Path first.txt
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('checkout','--detach') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Detached $true;& $assert $r.Data.Branch $null;& $assert $r.Data.Clean $true
        if($r.Data.HeadOid -notmatch '^[0-9a-f]{40}$'){throw 'Detached HEAD object ID missing'}
    }.GetNewClosure()
    $cases['status reports merge conflicts and a merge ready to commit as in-progress operations']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('switch','-c','feature') $Environment
        & $write (Join-Path $path 'file.txt') "feature`n";& $prepare $path @('commit','-am','feature') $Environment
        & $prepare $path @('switch','main') $Environment
        & $write (Join-Path $path 'file.txt') "main`n";& $prepare $path @('commit','-am','main') $Environment
        if((& $step $path @('merge','feature') $Environment) -eq 0){throw 'Merge fixture did not conflict'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Counts.Conflicted 1;& $assert @($r.Data.Operations).Count 1
        & $assert $r.Data.Operations[0].Kind Merge;& $assert $r.Data.Operations[0].Conflicts 1;& $assert $r.Data.Operations[0].ReadyToCommit $false
        & $write (Join-Path $path 'file.txt') "resolved`n";& $prepare $path @('add','file.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Counts.Conflicted 0;& $assert $r.Data.Operations[0].Kind Merge;& $assert $r.Data.Operations[0].ReadyToCommit $true
    }.GetNewClosure()
    $cases['status reports rebase cherry-pick revert bisect and am operations']={
        # Interactive rebase stopped on an edit step.
        $path=& $factory $RootDirectory $Environment
        foreach($n in 1..2){& $write (Join-Path $path ('step'+$n+'.txt')) "$n";& $prepare $path @('add','.') $Environment;& $prepare $path @('commit','-m',('step '+$n)) $Environment}
        $editing=$Environment.Clone();$editing.GIT_SEQUENCE_EDITOR="sed -i -e 's/^pick/edit/'"
        & $prepare $path @('rebase','-i','HEAD~2') $editing
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Operations[0].Kind Rebase;& $assert $r.Data.Operations[0].Interactive $true
        & $assert $r.Data.Operations[0].Branch main;& $assert $r.Data.Operations[0].Step 1;& $assert $r.Data.Operations[0].Total 2
        & $prepare $path @('rebase','--abort') $Environment
        # Cherry-pick and revert stopped on a conflict.
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('switch','-c','other') $Environment
        & $write (Join-Path $path 'file.txt') "other`n";& $prepare $path @('commit','-am','other') $Environment
        & $prepare $path @('switch','main') $Environment
        & $write (Join-Path $path 'file.txt') "main`n";& $prepare $path @('commit','-am','main one') $Environment
        if((& $step $path @('cherry-pick','other') $Environment) -eq 0){throw 'Cherry-pick fixture did not conflict'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert @($r.Data.Operations|Where-Object Kind -CEQ CherryPick).Count 1;& $assert $r.Data.Counts.Conflicted 1
        & $prepare $path @('cherry-pick','--abort') $Environment
        & $write (Join-Path $path 'file.txt') "main two`n";& $prepare $path @('commit','-am','main two') $Environment
        if((& $step $path @('revert','--no-edit','HEAD~1') $Environment) -eq 0){throw 'Revert fixture did not conflict'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert @($r.Data.Operations|Where-Object Kind -CEQ Revert).Count 1
        & $prepare $path @('revert','--abort') $Environment
        # Bisect session.
        & $prepare $path @('bisect','start','HEAD','HEAD~2') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;$bisect=@($r.Data.Operations|Where-Object Kind -CEQ Bisect);& $assert $bisect.Count 1;& $assert $bisect[0].From main
        & $prepare $path @('bisect','reset') $Environment
        # Mailbox application stopped on a patch that does not apply.
        $path=& $factory $RootDirectory $Environment
        & $write (Join-Path $path 'file.txt') "patched`n";& $prepare $path @('commit','-am','patched') $Environment
        $patches=Join-Path $RootDirectory ('status-patches-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        & $prepare $path @('format-patch','-1','HEAD','-o',$patches) $Environment
        & $prepare $path @('reset','--hard','HEAD~1') $Environment
        & $write (Join-Path $path 'file.txt') "diverged`n";& $prepare $path @('commit','-am','diverged') $Environment
        $patch=@(Get-ChildItem -LiteralPath $patches -Filter '*.patch')[0].FullName
        if((& $step $path @('am',$patch) $Environment) -eq 0){throw 'Am fixture applied cleanly'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;$am=@($r.Data.Operations|Where-Object Kind -CEQ Am);& $assert $am.Count 1;& $assert $am[0].Step 1;& $assert $am[0].Total 1
        & $prepare $path @('am','--abort') $Environment
    }.GetNewClosure()
    $cases['status reports stash sparse linked worktree submodule and shallow structure']={
        $path=& $factory $RootDirectory $Environment
        & $write (Join-Path $path 'file.txt') "stashed`n";& $prepare $path @('stash','push') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.StashCount 1;& $assert $r.Data.Clean $true
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status --no-show-stash
        & $success $r;& $assert $r.Data.StashCount $null
        # Sparse cone checkout.
        & $write (Join-Path $path 'kept/a.txt') 'a';& $write (Join-Path $path 'dropped/b.txt') 'b'
        & $prepare $path @('add','.') $Environment;& $prepare $path @('commit','-m','layout') $Environment
        & $prepare $path @('sparse-checkout','set','--cone','kept') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Repository.Sparse.Enabled $true;& $assert $r.Data.Repository.Sparse.Cone $true
        & $prepare $path @('sparse-checkout','disable') $Environment
        # Linked worktree.
        $linked=Join-Path $RootDirectory ('status-linked-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        & $prepare $path @('worktree','add','-b','linked',$linked) $Environment
        $r=quiet -AsObject -WorkingDirectory $linked -Environment $Environment git status
        & $success $r;& $assert $r.Data.Repository.LinkedWorktree $true;& $assert $r.Data.Branch linked
        # Modified submodule, observed from the superproject and from inside.
        $super=& $factory $RootDirectory $Environment
        & $prepare $super @('-c','protocol.file.allow=always','submodule','add',$path,'sub') $Environment
        & $prepare $super @('commit','-m','submodule') $Environment
        & $write (Join-Path $super 'sub/file.txt') "dirty`n"
        $r=quiet -AsObject -WorkingDirectory $super -Environment $Environment git status
        & $success $r;& $assert $r.Data.Counts.Submodules 1
        $entry=@($r.Data.Entries|Where-Object Path -CEQ sub)[0]
        & $assert $entry.Submodule.TrackedChanges $true;& $assert $entry.Submodule.CommitChanged $false
        $r=quiet -AsObject -WorkingDirectory (Join-Path $super 'sub') -Environment $Environment git status
        & $success $r;& $assert $r.Data.Repository.Submodule $true
        if(!$r.Data.Repository.Superproject){throw 'Submodule superproject not observed'}
        # Shallow clone over file:// (local path clones ignore --depth).
        & $prepare $path @('commit','--allow-empty','-m','second') $Environment
        $shallow=Join-Path $RootDirectory ('status-shallow-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        & $prepare $RootDirectory @('clone','--depth','1',[Uri]::new($path,[UriKind]::Absolute).AbsoluteUri,$shallow) $Environment
        $r=quiet -AsObject -WorkingDirectory $shallow -Environment $Environment git status
        & $success $r;& $assert $r.Data.Repository.Shallow $true;& $assert $r.Data.Upstream origin/main
        if(@($r.Data.Profile.Hints|Where-Object Code -CEQ ShallowDivergence).Count -ne 1){throw ('Shallow hint missing: '+($r.Data.Profile.Hints|ConvertTo-Json -Compress))}
    }.GetNewClosure()
    $cases['status classifies a broken gitfile and an unsupported repository format as typed failures']={
        $path=Join-Path $RootDirectory ('status-gitfile-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        & $write (Join-Path $path '.git') "gitdir: ./missing`n"
        $isolated=$Environment.Clone();$isolated.GIT_CEILING_DIRECTORIES=$RootDirectory
        $r=quiet -AsObject -WorkingDirectory $path -Environment $isolated git status
        & $assert $r.Outcome Failed
        if($r.Error[0].Message -notlike 'GitBrokenGitFile:*'){throw ('Unexpected broken gitfile classification: '+$r.Error[0].Message)}
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('config','core.repositoryformatversion','99') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $assert $r.Outcome Failed
        if($r.Error[0].Message -notlike 'GitUnsupportedRepositoryFormat:*'){throw ('Unexpected format classification: '+$r.Error[0].Message)}
    }.GetNewClosure()
    $cases['status digests a massive change set into ten disjoint hot paths covering every change']={
        $path=& $factory $RootDirectory $Environment
        $layout=[ordered]@{'apps/pkg1/src'=300;'apps/pkg2/src'=300;'apps/pkg3/src'=300;'apps/pkg4/src'=300;'apps/pkg5/src'=300;'libs/core/src'=200;'libs/io/src'=200;'libs/net/src'=200;'libs/ui/src'=200;'tools/build'=150;'docs'=49}
        $writes=[Collections.Generic.List[Threading.Tasks.Task]]::new()
        foreach($directory in $layout.Keys){
            $full=Join-Path $path $directory;[void][IO.Directory]::CreateDirectory($full)
            foreach($i in 1..$layout[$directory]){$writes.Add([IO.File]::WriteAllTextAsync((Join-Path $full ('f'+$i+'.txt')),'x'))}
        }
        [Threading.Tasks.Task]::WhenAll($writes).GetAwaiter().GetResult()
        & $write (Join-Path $path 'file.txt') "changed`n"
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $r;& $assert $r.Data.Counts.Changed 2500;& $assert $r.Data.Entries.Count 2500
        & $assert $r.Data.Digest.Mode HotPaths;& $assert $r.Data.Profile.Changes.Class Massive
        $hot=@($r.Data.Digest.HotPaths);& $assert $hot.Count 10
        & $assert ([long](($hot|Measure-Object Changed -Sum).Sum)) 2500
        # apps/ splits into its five packages; libs/ cannot split within the budget, so its largest child is kept
        # and the three others fold into one remainder that now ranks first.
        & $assert $hot[0].Path 'libs/';& $assert $hot[0].Kind Rest;& $assert $hot[0].Changed 600;& $assert $hot[0].Groups 3
        & $assert @($hot|Where-Object {$_.Path -like 'apps/pkg*/src/' -and $_.Changed -eq 300}).Count 5
        & $assert @($hot|Where-Object Path -CEQ 'file.txt').Count 1
        $plain=@($hot|Where-Object Kind -CNE Rest|ForEach-Object Path)
        foreach($a in $plain){foreach($b in $plain){if($a -cne $b -and $b.StartsWith($a,[StringComparison]::Ordinal) -and $a.EndsWith('/')){throw ('Hot paths overlap: '+$a+' '+$b)}}}
        $again=quiet -AsObject -WorkingDirectory $path -Environment $Environment git status
        & $success $again;& $assert (@($again.Data.Digest.HotPaths|ForEach-Object Path) -join '|') (@($hot|ForEach-Object Path) -join '|')
    }.GetNewClosure()
    $cases['status publishes repository summary and entry events to listeners']={
        $path=& $factory $RootDirectory $Environment
        & $write (Join-Path $path 'file.txt') "changed`n"
        $events=[Collections.Generic.List[object]]::new()
        $listener={param($e)if("$($e.Type)" -like 'GitStatus*'){$events.Add($e)}}.GetNewClosure()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -Listeners $listener git status
        & $success $r
        & $assert (@($events|ForEach-Object Type) -join ',') 'GitStatusRepository,GitStatusSummary,GitStatusEntry'
        & $assert $events[1].Data.Mode List;& $assert $events[1].Data.Counts.Unstaged 1;& $assert $events[2].Data.Entry.Path file.txt
    }.GetNewClosure()
    return $cases
}
