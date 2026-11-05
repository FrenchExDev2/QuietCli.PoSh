function Get-QuietGitQueryCases {
    <#
    .SYNOPSIS
    Builds independent file, reference, ancestry, object and predicate query workflows.
    .PARAMETER RootDirectory
    Owned disposable fixture root.
    .PARAMETER Environment
    Isolated Git environment.
    #>
    param([string]$RootDirectory,[hashtable]$Environment)
    $Environment=$Environment.Clone();$Environment.GIT_DEFAULT_HASH='sha1'
    $factory=Get-Command New-QuietGitRepositoryFixture;$prepare=Get-Command Invoke-GitFixture
    $success=Get-Command Assert-QuietGitSuccess;$assert=Get-Command Assert-QuietEqual
    $cases=[ordered]@{}
    $cases['queries ls-files preserves selected paths stages and requested formatting']={
        $path=& $factory $RootDirectory $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'é space.txt'),'content',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('add','--','é space.txt') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git ls-files --stage -- 'é space.txt'
        & $success $r;& $assert $r.Data.Files.Count 1;& $assert $r.Data.Files[0].Path 'é space.txt';& $assert $r.Data.Files[0].Stage 0
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git ls-files -- 'é space.txt'
        & $success $r;& $assert $r.Data.Files[0].Path 'é space.txt'
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git ls-files --format='%(path)' -- 'é space.txt'
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat
    }.GetNewClosure()
    $cases['queries refs retain local fields quiet predicates and explicit remote advertisements']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('tag','light') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git for-each-ref --count=1 refs/heads
        & $success $r;& $assert $r.Data.References.Count 1;& $assert $r.Data.References[0].Name refs/heads/main;& $assert $r.Data.References[0].Type commit
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git show-ref --verify refs/heads/main
        & $success $r;& $assert $r.Data.Found $true;& $assert $r.Data.References.Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git show-ref --quiet --verify refs/heads/missing
        & $success $r;& $assert $r.Data.Found $false
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git ls-remote --symref $path HEAD
        & $success $r;& $assert $r.Data.References.Count 2
        & $assert $r.Data.References[0].SymbolicTarget refs/heads/main
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git ls-remote --exit-code $path refs/heads/missing
        & $success $r;& $assert $r.Data.Found $false;& $assert $r.Data.ExitCode 2
    }.GetNewClosure()
    $cases['queries object IDs preserve requested input and revision parent relationships']={
        $path=& $factory $RootDirectory $Environment
        $text="hello é`n";$bytes=[Text.Encoding]::UTF8.GetBytes($text)
        $header=[Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
        $expected=[Convert]::ToHexString([Security.Cryptography.SHA1]::HashData([byte[]]($header+$bytes))).ToLowerInvariant()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment -InputText $text git hash-object --stdin
        & $success $r;& $assert $r.Data.Objects.Count 1;& $assert $r.Data.Objects[0].ObjectId $expected;& $assert $r.Data.Objects[0].Algorithm sha1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git write-tree
        & $success $r;& $assert $r.Data.Objects.Count 1
        & $prepare $path @('commit','--allow-empty','-m','second') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-list --parents -n 1 HEAD
        & $success $r;& $assert $r.Data.Objects.Count 1;& $assert $r.Data.Objects[0].Parents.Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-list --count HEAD
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat;& $assert $r.Data.Records[0] '2'
    }.GetNewClosure()
    $cases['queries merge-base distinguishes ancestor non-ancestor and native revision errors']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('commit','--allow-empty','-m','second') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git merge-base --is-ancestor 'HEAD~1' HEAD
        & $success $r;& $assert $r.Data.IsAncestor $true
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git merge-base --is-ancestor HEAD 'HEAD~1'
        & $success $r;& $assert $r.Data.IsAncestor $false
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git merge-base HEAD 'HEAD~1'
        & $success $r;& $assert $r.Data.Found $true;& $assert $r.Data.Objects.Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git merge-base --is-ancestor missing-revision HEAD
        & $assert $r.Outcome Failed
    }.GetNewClosure()
    $cases['queries counters versions ref validation and detached symbolic refs have explicit results']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git count-objects
        & $success $r
        if($r.Data.Counts.count -lt 3){throw 'Expected committed blob tree and commit objects'}
        & $assert $r.Data.SizeUnit KiB
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git version
        & $success $r
        if($r.Data.Version -notmatch '^2\.'){throw 'Native version missing'}
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git check-ref-format refs/heads/valid
        & $success $r;& $assert $r.Data.Valid $true
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git check-ref-format 'refs/heads/bad..name'
        & $success $r;& $assert $r.Data.Valid $false
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git symbolic-ref HEAD
        & $success $r;& $assert $r.Data.Reference refs/heads/main
        & $prepare $path @('checkout','--detach','HEAD') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git symbolic-ref --quiet HEAD
        & $success $r;& $assert $r.Data.Exists $false
    }.GetNewClosure()
    return $cases
}
