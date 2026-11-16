function Invoke-QuietGitBlame {
    <#
    .SYNOPSIS
    Parses blame/annotate line-porcelain bytes while preserving explicit alternate output modes.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original blame or annotate arguments.
    .PARAMETER Binding
    Bound output/range options and operands.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    if(@($flags|Where-Object {$_ -cin @('--incremental','--show-stats','--color-by-age','--color-lines','--date','--porcelain','-p')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) $Request.Name}
    Import-QuietGitParser
    $arguments=Get-QuietGitArguments $Binding @('--line-porcelain','-c','-e','--show-email','-f','-l','-n','-s','-t','--abbrev')
    $data=@{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;Lines=[Collections.Generic.List[object]]::new();Pending=$null;Scope='Requested native line attribution; original text bytes and metadata, not a causal explanation.'}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@($Request.Name,'--line-porcelain')+$arguments) $data -Parser {
        param($record,$data)
        [FrenchExDev2.QuietCli.Git.GitBlameRecords]::Receive($record,$data)
    } -Finalize {
        param($data)
        [FrenchExDev2.QuietCli.Git.GitBlameRecords]::Finish($data)
        $data
    }
    return $r.Data
}
function Invoke-QuietGitReflog {
    <#
    .SYNOPSIS
    Returns fixed-field reflog entries and explicit existence predicates without a hidden log invocation.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact reflog operation and arguments.
    .PARAMETER Binding
    Bound log/filter options; the native leading subcommand is selected explicitly.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $operation='show';$arguments=@($Request.Arguments)
    if($arguments.Count -and $arguments[0] -cin @('show','list','exists','delete','expire','drop','write')){$operation=$arguments[0];$arguments=if($arguments.Count -gt 1){@($arguments[1..($arguments.Count-1)])}else{@()}}
    if($operation -ceq 'exists'){
        $r=Invoke-QuietGitNative $Runtime ($Prefix+@('reflog','exists')+$arguments) -Data $null -SuccessExitCodes @(0,1) -Output {param($event,$runtime)} -Complete {param($runtime)}
        return @{Command='reflog';Operation='exists';GitVersion=$Runtime.State.DetectedVersion;Exists=($r.Execution.Native.ExitCode -eq 0);ExitCode=$r.Execution.Native.ExitCode}
    }
    if($operation -cne 'show'){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('reflog')+@($Request.Arguments)) reflog}
    $flags=@($Binding.Options.Name)
    if(@($flags|Where-Object {$_ -cin @('--format','--pretty','--oneline','--graph','--raw','--stat','--numstat','--name-only','--name-status','--patch','-p','-z')}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('reflog')+@($Request.Arguments)) reflog -Delimiter $(if('-z' -cin $flags){0}else{10})}
    Import-QuietGitParser
    $data=@{Command='reflog';GitVersion=$Runtime.State.DetectedVersion;Entries=[Collections.Generic.List[object]]::new();Scope='Exact requested reflog walk; no inferred old IDs, repository history or recovery actions.'}
    $format='--format=%H%x00%gD%x00%gn%x00%ge%x00%gs%x00'
    $r=Invoke-QuietGitFieldRecords $Runtime ($Prefix+@('reflog','show',$format)+$arguments) $data -FieldCount 5 -Commit {
        param($fields,$data)
        [FrenchExDev2.QuietCli.Git.GitReflogRecords]::Append($fields,$data)
    }
    return $r.Data
}
