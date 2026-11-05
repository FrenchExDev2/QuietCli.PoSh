function Get-QuietGitAttributionCases {
    <#
    .SYNOPSIS
    Creates fragmented attribution, alias, requested-format and reflog workflows.
    .PARAMETER RootDirectory
    Owned disposable fixture root.
    .PARAMETER Environment
    Isolated Git configuration.
    #>
    param([string]$RootDirectory,[hashtable]$Environment)
    $Environment=$Environment.Clone();$Environment.GIT_DEFAULT_HASH='sha1'
    $factory=Get-Command New-QuietGitRepositoryFixture;$prepare=Get-Command Invoke-GitFixture
    $success=Get-Command Assert-QuietGitSuccess;$assert=Get-Command Assert-QuietEqual
    $cases=[ordered]@{}
    $cases['attribution blame preserves quoted Unicode paths content CR and uncommitted line IDs']={
        $path=& $factory $RootDirectory $Environment
        $name='é quoted name.txt'
        [void][IO.File]::WriteAllTextAsync((Join-Path $path $name),"first`nsecond é`r`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('add','--',$name) $Environment;& $prepare $path @('commit','-m','attribution content') $Environment
        [void][IO.File]::AppendAllTextAsync((Join-Path $path $name),"local`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -ReadBlockBytes 1024 -WorkingDirectory $path -Environment $Environment git blame -- $name
        & $success $r;& $assert $r.Data.Lines.Count 3
        & $assert $r.Data.Lines[0].Path $name;& $assert $r.Data.Lines[0].Content first
        & $assert $r.Data.Lines[1].Content "second é`r";& $assert $r.Data.Lines[2].Uncommitted $true
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
    }.GetNewClosure()
    $cases['attribution annotate shares the parser while preserving selected line ranges']={
        $path=& $factory $RootDirectory $Environment
        [void][IO.File]::WriteAllTextAsync((Join-Path $path 'file.txt'),"first`nsecond`nthird`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        & $prepare $path @('commit','-am','three lines') $Environment
        $r=quiet -AsObject -ReadBlockBytes 1024 -WorkingDirectory $path -Environment $Environment git annotate -L '2,2' -- file.txt
        & $success $r;& $assert $r.Data.Command annotate;& $assert $r.Data.Lines.Count 1
        & $assert $r.Data.Lines[0].FinalLine 2;& $assert $r.Data.Lines[0].Content second
    }.GetNewClosure()
    $cases['attribution requested incremental blame output remains its native format']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git blame --incremental -- file.txt
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat
        if($r.Data.Records.Count -lt 3){throw 'Incremental blame records missing'}
    }.GetNewClosure()
    $cases['attribution reflog selectors messages predicates and explicit formats execute once']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('commit','--allow-empty','-m','second é') $Environment
        & $prepare $path @('commit','--allow-empty','-m','third') $Environment
        $r=quiet -AsObject -ReadBlockBytes 1024 -WorkingDirectory $path -Environment $Environment git reflog show -n 2
        & $success $r;& $assert $r.Data.Entries.Count 2
        & $assert $r.Data.Entries[0].Selector 'HEAD@{0}';& $assert $r.Data.Entries[0].Message 'commit: third'
        & $assert $r.Data.Entries[1].Message 'commit: second é'
        & $assert @($r.Internal.Sources.Values|Where-Object Role -EQ Business).Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git reflog exists refs/heads/main
        & $success $r;& $assert $r.Data.Exists $true
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git reflog exists refs/heads/missing
        & $success $r;& $assert $r.Data.Exists $false
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git reflog --format=%gs -n 1
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat;& $assert $r.Data.Records[0] 'commit: third'
    }.GetNewClosure()
    return $cases
}
