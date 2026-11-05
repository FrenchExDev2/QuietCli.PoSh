# Objectif : Vérifier les handlers sémantiques et les cas de régression dans le seul module compagnon.
function Assert-QuietGitSuccess {
    <#
.SYNOPSIS
Reports only structured execution errors when a semantic handler fails.
    .PARAMETER Result
    Caller-local result; business Data is not serialized for diagnostics.
    #>
    param($Result)
    if($Result.Outcome -ne 'Success'){throw ('SemanticHandlerFailed: '+($Result.Error|ConvertTo-Json -Depth 8 -Compress)+' '+($Result.Execution.Issues|ConvertTo-Json -Depth 8 -Compress))}
}
function Read-QuietPatchFixture {
    <#
.SYNOPSIS
Feeds independently supplied fixture bytes through the actual streaming parser in fragmented blocks.
    .PARAMETER Module
    Loaded Git business module.
    .PARAMETER Path
    Explicit fixture file.
    #>
    param($Module,[string]$Path)
    & $Module {
        param($path)
        $parse=Get-Command Receive-QuietGitPatchRecord;$finish=Get-Command Complete-QuietGitPatch
        $state=New-QuietGitRecordState (New-QuietGitPatch diff fixture) 10 {param($record,$data)& $parse $record $data}.GetNewClosure() {param($data)& $finish $data}.GetNewClosure()
        $runtime=[pscustomobject]@{Data=$state}
        $stream=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read,4096,$true)
        try{
            $buffer=[byte[]]::new(7)
            while(($count=$stream.ReadAsync($buffer,0,$buffer.Length).GetAwaiter().GetResult()) -gt 0){$block=[byte[]]::new($count);[Array]::Copy($buffer,$block,$count);Receive-QuietGitRecord ([pscustomobject]@{Stream='stdout';Bytes=$block}) $runtime}
            Complete-QuietGitRecord $runtime
        }finally{$stream.Dispose()}
    } $Path
}
function Get-QuietGitSemanticCases {
    <#
.SYNOPSIS
Builds independent awkward-path, patch, history, blob and repository scenarios.
    .PARAMETER RootDirectory
    Owned disposable fixture root.
    .PARAMETER Environment
    Isolated Git identity and configuration.
    #>
    param([string]$RootDirectory,[hashtable]$Environment)
    $prepare=Get-Command Invoke-GitFixture;$assert=Get-Command Assert-QuietEqual;$success=Get-Command Assert-QuietGitSuccess
    $parseFixture=Get-Command Read-QuietPatchFixture;$gitModule=Get-Module FrenchExDev2.QuietCli.Git.PoSh
    $fixtureDirectory=Join-Path $PSScriptRoot 'fixtures/patch'
    $repo=Join-Path $RootDirectory 'semantic';[void][IO.Directory]::CreateDirectory($repo)
    & $prepare $repo @('init','--initial-branch=main') $Environment
    & $prepare $repo @('config','commit.gpgsign','false') $Environment
    [void][IO.File]::WriteAllTextAsync((Join-Path $repo 'file.txt'),"alpha`nbeta`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    & $prepare $repo @('add','--','file.txt') $Environment
    & $prepare $repo @('commit','-m','Semantic baseline','-m','Body details') $Environment
    $cases=[ordered]@{}
    $cases['fragmented patch preserves hunk lines that look like file headers']={
        $data=& $parseFixture $gitModule (Join-Path $fixtureDirectory 'multifile.txt')
        & $assert $data.Files.Count 3
        & $assert $data.Files[1].NewLabel 'b/notes.md'
        & $assert $data.Files[1].Hunks[0].Lines[-1].Kind Addition
        & $assert $data.Files[1].Hunks[0].Lines[-1].Text '+++ can also start a line'
        & $assert $data.Files[2].Hunks[0].Lines[0].Kind Deletion
    }.GetNewClosure()
    $cases['patch no-final-newline markers are retained as business facts']={
        $data=& $parseFixture $gitModule (Join-Path $fixtureDirectory 'no-final-newline.txt')
        $markers=@(foreach($file in $data.Files){foreach($hunk in $file.Hunks){$hunk.Lines|Where-Object Kind -EQ NoFinalNewline}})
        & $assert $data.Files.Count 2
        & $assert $markers.Count 2
    }.GetNewClosure()
    $cases['combined patch keeps all parent ranges']={
        $data=& $parseFixture $gitModule (Join-Path $fixtureDirectory 'combined.txt')
        & $assert $data.Commits[0].ObjectId '5654fed456e06c2bdf277ad4bdd76a62650e542e'
        & $assert $data.Files.Count 1
        & $assert $data.Files[0].Combined $true
        & $assert $data.Files[0].Hunks[0].Ranges.Count 3
        & $assert $data.Files[0].Hunks[0].Combined $true
    }.GetNewClosure()
    $cases['octal-quoted patch labels remain distinct instead of lossy decoding']={
        $data=& $parseFixture $gitModule (Join-Path $fixtureDirectory 'latin1.txt')
        & $assert $data.Files.Count 2
        if($data.Files[0].OldLabel -ceq $data.Files[1].OldLabel){throw 'Distinct byte paths collapsed into one display label'}
        if(!$data.Files[0].OldLabel.Contains('\350') -or !$data.Files[1].OldLabel.Contains('\351')){throw 'Git display quoting was altered'}
    }.GetNewClosure()
    $cases['non-UTF8 patch payload is represented without replacement characters']={
        $path=Join-Path $RootDirectory 'non-utf8.patch'
        $header=[Text.Encoding]::ASCII.GetBytes("diff --git a/f b/f`n--- a/f`n+++ b/f`n@@ -1 +1 @@`n-a`n+")
        $bytes=[byte[]]::new($header.Length+2);$header.CopyTo($bytes,0);$bytes[$header.Length]=233;$bytes[$header.Length+1]=10
        [void][IO.File]::WriteAllBytesAsync($path,$bytes).GetAwaiter().GetResult()
        $data=& $parseFixture $gitModule $path
        $content=@(foreach($file in $data.Files){foreach($hunk in $file.Hunks){$hunk.Lines|Where-Object Kind -EQ ByteContent}})
        if(!$content.Count){throw 'Expected explicit raw-byte business content'}
        & $assert $content[0].Content.Encoding RawBytes
        & $assert ([Convert]::ToHexString([Convert]::FromBase64String($content[0].Content.Base64))) '2BE9'
    }.GetNewClosure()
    $cases['live diff has typed hunks and one business subprocess']={
        [void][IO.File]::WriteAllTextAsync((Join-Path $repo 'file.txt'),"alpha`nbeta updated`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git diff --exit-code
        & $success $r
        & $assert $r.Data.OutputMode Patch
        & $assert $r.Data.Files.Count 1
        & $assert @($r.Data.Files[0].Hunks[0].Lines|Where-Object Kind -EQ Addition).Count 1
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
    }.GetNewClosure()
    $cases['explicit word-diff format is not silently treated as ordinary patch']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git diff --word-diff=porcelain
        & $success $r
        & $assert $r.Data.OutputMode RequestedFormat
        if(!$r.Data.Records.Count){throw 'Requested diff records missing'}
    }.GetNewClosure()
    $cases['default log returns full identity subject and body without a hidden cap']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git log -n 1
        & $success $r
        & $assert $r.Data.OutputMode Commits
        & $assert $r.Data.Commits.Count 1
        & $assert $r.Data.Commits[0].Subject 'Semantic baseline'
        & $assert $r.Data.Commits[0].Body "Body details`n"
        & $assert $r.Data.Scope.ImplicitLimit $false
    }.GetNewClosure()
    $cases['explicit log format and flag-looking values preserve their meaning']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git log --format=%s -n 1
        & $success $r
        & $assert $r.Data.OutputMode RequestedFormat
        & $assert $r.Data.Records[0] 'Semantic baseline'
        $filtered=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git log --grep=--oneline
        & $success $filtered
        & $assert $filtered.Data.OutputMode Commits
        & $assert $filtered.Data.Commits.Count 0
    }.GetNewClosure()
    $cases['ls-tree preserves awkward Unicode quote space and newline index paths']={
        $treeRepo=Join-Path $RootDirectory 'tree';[void][IO.Directory]::CreateDirectory($treeRepo)
        & $prepare $treeRepo @('init','--initial-branch=main') $Environment
        $blob=quiet -AsObject -InputBytes ([byte[]]@()) -WorkingDirectory $treeRepo -Environment $Environment git hash-object -w --stdin
        & $success $blob
        $oid=$blob.Data.Objects[0].ObjectId
        & $assert $oid 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391'
        $names=@('Cargo.toml','README.md','my file.txt','dir with space/a.rs','quote"name.txt','src/é.rs','src/lib.rs','src/main.rs','src/cmds/alpha.rs','src/cmds/beta.rs','src/cmds/gamma.rs','tests/one.rs','tests/two.rs',"line`nbreak.txt")
        foreach($name in $names){& $prepare $treeRepo @('-c','core.protectNTFS=false','update-index','--add','--cacheinfo','100644',$oid,$name) $Environment}
        $tree=quiet -AsObject -WorkingDirectory $treeRepo -Environment $Environment git write-tree
        & $success $tree
        $r=quiet -AsObject -WorkingDirectory $treeRepo -Environment $Environment git ls-tree -r --name-only $tree.Data.Objects[0].ObjectId
        & $success $r
        & $assert $r.Data.Entries.Count $names.Count
        foreach($name in $names){& $assert ($name -cin @($r.Data.Entries.Path)) $true}
    }.GetNewClosure()
    $cases['show classifies binary blobs through Git and produces exact owned business content']={
        $bytes=[byte[]]@(0,255,254,13,10,42)
        $blob=quiet -AsObject -InputBytes $bytes -WorkingDirectory $repo -Environment $Environment git hash-object -w --stdin
        & $success $blob
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git show $blob.Data.Objects[0].ObjectId
        & $success $r
        & $assert $r.Data.ObjectType blob
        & $assert $r.Data.Artifact.Bytes 6
        & $assert $r.Data.Artifact.SHA256 ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))
        $actual=[IO.File]::ReadAllBytes($r.Data.Artifact.Path)
        & $assert ([Convert]::ToHexString($actual)) ([Convert]::ToHexString($bytes))
        Remove-QuietGitArtifact -Artifact $r.Data.Artifact
    }.GetNewClosure()
    $cases['show does not classify a colon inside an option value as a blob']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git show --format=%B --grep=x:y HEAD
        & $success $r
        & $assert $r.Data.OutputMode RequestedFormat
    }.GetNewClosure()
    $cases['branch mutation and listing expose independently observed reference changes']={
        $create=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git branch topic
        & $success $create
        & $assert @($create.Data.ReferenceChanges|Where-Object Kind -EQ Added).Count 1
        $list=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git branch --list
        & $success $list
        & $assert $list.Data.Branches.Count 2
        & $assert @($list.Data.Branches|Where-Object Current).Count 1
    }.GetNewClosure()
    $cases['stash mutation and listing have typed reference and subject fields']={
        $push=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git stash push -m 'Semantic stash'
        & $success $push
        $list=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git stash list
        & $success $list
        & $assert $list.Data.Stashes.Count 1
        & $assert $list.Data.Stashes[0].Reference 'stash@{0}'
        if($list.Data.Stashes[0].Subject -notlike '*Semantic stash'){throw 'Stash subject lost'}
    }.GetNewClosure()
    $cases['worktree list preserves porcelain identity and path']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git worktree list
        & $success $r
        & $assert $r.Data.Worktrees.Count 1
        & $assert ([IO.Path]::GetFullPath($r.Data.Worktrees[0].Path)) ([IO.Path]::GetFullPath($repo))
        & $assert $r.Data.Worktrees[0].Branch 'refs/heads/main'
    }.GetNewClosure()
    $cases['checkout executes once and observes symbolic HEAD without replay']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git checkout -b picked
        & $success $r
        & $assert $r.Data.BranchBefore 'refs/heads/main'
        & $assert $r.Data.BranchAfter 'refs/heads/picked'
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
    }.GetNewClosure()
    $cases['add executes once and an independent status observes staged content']={
        [void][IO.File]::WriteAllTextAsync((Join-Path $repo 'file.txt'),"stage change`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git add -- file.txt
        & $success $r
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        $status=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git status
        & $success $status
        & $assert $status.Data.Counts.Staged 1
    }.GetNewClosure()
    $cases['status short branch and untracked modes retain their declared scope']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git status -sb --untracked-files=no
        & $success $r
        & $assert $r.Data.Branch picked
        & $assert $r.Data.Scope.UntrackedFiles no
        & $assert $r.Data.Counts.Staged 1
    }.GetNewClosure()
    $cases['verbose status contains staged and unstaged business patches']={
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git status -vv
        & $success $r
        & $assert $r.Data.StagedPatch.Files.Count 1
        & $assert $r.Data.UnstagedPatch.Files.Count 0
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 3
    }.GetNewClosure()
    $cases['status rename consumes a distinct original-path NUL record']={
        $renameRepo=Join-Path $RootDirectory 'renames'
        & $prepare $RootDirectory @('clone',$repo,$renameRepo) $Environment
        & $prepare $renameRepo @('mv','--','file.txt','renamed é.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $renameRepo -Environment $Environment git status --find-renames=50%
        & $success $r
        & $assert $r.Data.Counts.Renamed 1
        & $assert $r.Data.Entries[0].Path 'renamed é.txt'
        & $assert $r.Data.Entries[0].OriginalPath file.txt
    }.GetNewClosure()
    $cases['status parser preserves an invalid UTF8 native path as bytes']={
        $data=& $gitModule {
            $data=@{Pending=$null;Entries=[Collections.Generic.List[object]]::new();Counts=@{Untracked=0L;Changed=0L}}
            Receive-QuietGitStatusRecord ([byte[]]@(63,32,233)) $data
            $data
        }
        & $assert $data.Entries[0].Path.Encoding RawBytes
        & $assert ([Convert]::ToHexString([Convert]::FromBase64String($data.Entries[0].Path.Base64))) E9
        & $assert $data.Counts.Untracked 1
    }.GetNewClosure()
    $cases['machine-format handler refuses a merged terminal rather than reporting empty success']={
        $r=quiet -AsObject -Transport Pty -WorkingDirectory $repo -Environment $Environment git status
        & $assert $r.Outcome Failed
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 0
    }.GetNewClosure()
    $cases['fetch and pull use a local remote and one business execution each']={
        $remote=Join-Path $RootDirectory 'semantic-remote.git'
        & $prepare $RootDirectory @('init','--bare',$remote) $Environment
        & $prepare $repo @('remote','add','origin',$remote) $Environment
        & $prepare $repo @('push','origin','main') $Environment
        $fetch=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git fetch origin
        & $success $fetch
        & $assert @($fetch.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        $pull=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git pull --ff-only origin main
        & $success $pull
        & $assert @($pull.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        & $assert $pull.Data.HeadBefore $pull.Data.HeadAfter
    }.GetNewClosure()
    $cases['worktree mutation executes once and exposes independent before-after lists']={
        $path=Join-Path $RootDirectory 'linked-worktree'
        $r=quiet -AsObject -WorkingDirectory $repo -Environment $Environment git worktree add -b linked $path
        & $success $r
        & $assert @($r.Data.Before).Count 1
        & $assert @($r.Data.After).Count 2
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
    }.GetNewClosure()
    $cases['gain filters select the business module without serializing its objects']={
        $gain=Get-QuietCliGain -ModuleId 'FrenchExDev2.QuietCli.Git.PoSh' -GroupBy Module -AsObject
        if($gain.Invocations -lt 1){throw 'Module-filtered invocation metadata missing'}
        & $assert $gain.Groups.Count 1
        & $assert $gain.Groups[0].Key 'FrenchExDev2.QuietCli.Git.PoSh'
        & $assert $gain.RootDeliveryBytes $null
    }.GetNewClosure()
    return $cases
}
