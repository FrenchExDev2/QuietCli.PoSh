function Get-QuietGitRevisionCases {
    <#
    .SYNOPSIS
    Builds scalar/revision identity, long description, name and summary workflows.
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
    $cases['revision rev-parse separates scalar paths exact booleans object IDs and mixed outputs']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-parse --show-toplevel
        & $success $r;& $assert $r.Data.Kind Path;& $assert ([IO.Path]::GetFullPath($r.Data.Value)) ([IO.Path]::GetFullPath($path))
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-parse --is-inside-work-tree
        & $success $r;& $assert $r.Data.Value $true
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-parse --is-bare-repository
        & $success $r;& $assert $r.Data.Value $false
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-parse --show-object-format
        & $success $r;& $assert $r.Data.Value sha1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-parse --verify HEAD
        & $success $r;& $assert $r.Data.Objects.Count 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-parse --verify --quiet no-such-revision
        & $success $r;& $assert $r.Data.Found $false;& $assert $r.Data.ExitCode 1
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git rev-parse --is-bare-repository --is-inside-work-tree
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat;& $assert $r.Data.Records.Count 2
    }.GetNewClosure()
    $cases['revision describe preserves tag suffix boundaries distances and always fallback']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git describe --always
        & $success $r;& $assert $r.Data.Descriptions[0].ObjectOnly $true
        & $prepare $path @('tag','-a','réf-1-gabc','-m','tag') $Environment
        & $prepare $path @('commit','--allow-empty','-m','after tag') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git describe
        & $success $r;& $assert $r.Data.Descriptions[0].Tag 'réf-1-gabc';& $assert $r.Data.Descriptions[0].Distance 1
        [void][IO.File]::AppendAllTextAsync((Join-Path $path 'file.txt'),'dirty',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git describe --dirty
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat
    }.GetNewClosure()
    $cases['revision name-rev distinguishes native labels from IDs and keeps name-only mode']={
        $path=& $factory $RootDirectory $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git name-rev HEAD
        & $success $r;& $assert $r.Data.Names.Count 1;& $assert $r.Data.Names[0].Input HEAD;& $assert $r.Data.Names[0].Name main
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git name-rev --name-only HEAD
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat;& $assert $r.Data.Records[0] main
    }.GetNewClosure()
    $cases['revision shortlog summaries retain counts without discarding full default subjects']={
        $path=& $factory $RootDirectory $Environment
        & $prepare $path @('commit','--allow-empty','-m','second subject') $Environment
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git shortlog --summary HEAD
        & $success $r;& $assert $r.Data.Groups.Count 1;& $assert $r.Data.Groups[0].Count 2
        $r=quiet -AsObject -WorkingDirectory $path -Environment $Environment git shortlog HEAD
        & $success $r;& $assert $r.Data.OutputMode RequestedFormat
        if(!@($r.Data.Records|Where-Object {$_ -like '*second subject*'}).Count){throw 'Default shortlog subject missing'}
    }.GetNewClosure()
    return $cases
}
