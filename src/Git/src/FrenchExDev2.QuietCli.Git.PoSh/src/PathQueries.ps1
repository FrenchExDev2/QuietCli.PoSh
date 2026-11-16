function Get-QuietGitGrepMode {
    <#
    .SYNOPSIS
    Selects grep output semantics from option names, never flag-looking values.
    .PARAMETER Binding
    Git-owned bound options in native order.
    #>
    param($Binding)
    $mode='NativeRecords'
    foreach($option in $Binding.Options){
        if($option.Name -cin @('-q','--quiet')){return 'Quiet'}
        if($option.Name -cin @('-l','--files-with-matches','-L','--files-without-match')){$mode=if($option.Name -cin @('-L','--files-without-match')){'FilesWithoutMatches'}else{'FilesWithMatches'}}
    }
    return $mode
}
function Invoke-QuietGitGrep {
    <#
    .SYNOPSIS
    Separates grep predicates, lossless requested file lists and exact native content formats.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Original grep pattern/options/pathspecs.
    .PARAMETER Binding
    Bound options with literal operand semantics.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $mode=Get-QuietGitGrepMode $Binding
    if($mode -ceq 'Quiet'){
        $r=Invoke-QuietGitNative $Runtime ($Prefix+@('grep')+@($Request.Arguments)) -Data $null -SuccessExitCodes @(0,1) -Output {param($event,$runtime)} -Complete {param($runtime)}
        return @{Command='grep';Mode=$mode;GitVersion=$Runtime.State.DetectedVersion;Matched=($r.Execution.Native.ExitCode -eq 0);ExitCode=$r.Execution.Native.ExitCode}
    }
    if($mode -ceq 'NativeRecords'){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('grep')+@($Request.Arguments)) grep -Codes @(0,1) -Delimiter $(if(@($Binding.Options.Name|Where-Object {$_ -cin @('-z','--null')}).Count){0}else{10})}
    Import-QuietGitParser
    $arguments=Get-QuietGitArguments $Binding @('-z','--null')
    $data=@{Command='grep';Mode=$mode;GitVersion=$Runtime.State.DetectedVersion;Files=[Collections.Generic.List[object]]::new();WithStage=$false;HasResults=$false}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('grep','-z')+$arguments) $data -Delimiter 0 -Codes @(0,1) -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitIndexRecords]::Receive($record,$data)}
    $r.Data.HasResults=$r.Data.Files.Count -gt 0;$r.Data.ExitCode=$r.Execution.Native.ExitCode
    return $r.Data
}
function Invoke-QuietGitAttributes {
    <#
    .SYNOPSIS
    Parses fixed NUL attribute records while preserving the caller's stdin delimiter.
    .PARAMETER Runtime
    Parent invocation including any explicit stdin.
    .PARAMETER Request
    Original attribute names and path operands.
    .PARAMETER Binding
    Bound stdin/framing options.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    if('--stdin' -cin $flags -and '-z' -cnotin $flags){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('check-attr')+@($Request.Arguments)) check-attr}
    Import-QuietGitParser
    $arguments=Get-QuietGitArguments $Binding @('-z')
    $data=@{Command='check-attr';Kind='Attribute';GitVersion=$Runtime.State.DetectedVersion;Entries=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('check-attr','-z')+$arguments) $data -Delimiter 0 -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitPathCheckRecords]::Receive($record,$data)} -Finalize {param($data)[FrenchExDev2.QuietCli.Git.GitPathCheckRecords]::Finish($data);$data}
    return $r.Data
}
function Invoke-QuietGitIgnore {
    <#
    .SYNOPSIS
    Returns ignore-rule evidence, preserving negation and nonmatching NUL groups.
    .PARAMETER Runtime
    Parent invocation with any explicit stdin.
    .PARAMETER Request
    Original check-ignore arguments.
    .PARAMETER Binding
    Bound path operands, quiet, stdin and verbose options.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    if(@($flags|Where-Object {$_ -cin @('-q','--quiet')}).Count){
        $r=Invoke-QuietGitNative $Runtime ($Prefix+@('check-ignore')+@($Request.Arguments)) -Data $null -SuccessExitCodes @(0,1) -Output {param($event,$runtime)} -Complete {param($runtime)}
        return @{Command='check-ignore';AnyIgnored=($r.Execution.Native.ExitCode -eq 0);ExitCode=$r.Execution.Native.ExitCode}
    }
    Import-QuietGitParser
    $childRuntime=$Runtime
    if('--stdin' -cin $flags){
        if('-z' -cnotin $flags){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('check-ignore')+@($Request.Arguments)) check-ignore -Codes @(0,1)}
        $arguments=Get-QuietGitArguments $Binding @('-v','--verbose')
        $arguments=@('-v')+$arguments
    }else{
        $inputKeys=@('InputText','InputBytes','InputPath','Interaction'|Where-Object {$Runtime.Request.ContainsKey($_)})
        if($inputKeys.Count -or !$Binding.Operands.Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@('check-ignore')+@($Request.Arguments)) check-ignore -Codes @(0,1)}
        $requestCopy=$Runtime.Request.Clone()
        $requestCopy.InputBytes=[FrenchExDev2.QuietCli.Git.GitPathCheckRecords]::EncodePaths([string[]]$Binding.Operands)
        $childRuntime=[pscustomobject]@{Request=$requestCopy;State=$Runtime.State}
        $arguments=@('--stdin','-z','-v')
        foreach($token in $Binding.Tokens){if($token.Kind -ceq 'Option' -and $token.Name -cnotin @('-z','-v','--verbose')){$arguments+=@($token.EmitArguments)}}
    }
    $data=@{Command='check-ignore';Kind='Ignore';GitVersion=$Runtime.State.DetectedVersion;Entries=[Collections.Generic.List[object]]::new();AnyIgnored=$false}
    $r=Invoke-QuietGitRecords $childRuntime ($Prefix+@('check-ignore')+$arguments) $data -Codes @(0,1) -Delimiter 0 -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitPathCheckRecords]::Receive($record,$data)} -Finalize {param($data)[FrenchExDev2.QuietCli.Git.GitPathCheckRecords]::Finish($data);$data}
    $r.Data.AnyIgnored=$r.Execution.Native.ExitCode -eq 0;$r.Data.ExitCode=$r.Execution.Native.ExitCode
    return $r.Data
}
function Invoke-QuietGitMailmap {
    <#
    .SYNOPSIS
    Parses the contacts returned by one explicit mailmap query.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact contact and stdin arguments.
    .PARAMETER Binding
    Bound query options.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    Import-QuietGitParser
    $data=@{Command='check-mailmap';GitVersion=$Runtime.State.DetectedVersion;Contacts=[Collections.Generic.List[object]]::new()}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('check-mailmap')+@($Request.Arguments)) $data -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitMailmapRecords]::Receive($record,$data)}
    return $r.Data
}
function Invoke-QuietGitRawDiff {
    <#
    .SYNOPSIS
    Parses non-combined raw plumbing diffs without changing recursion or requested patch modes.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Exact diff-files, diff-index or diff-tree request.
    .PARAMETER Binding
    Bound output and comparison options.
    .PARAMETER Prefix
    Native global context.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    $codes=if('--exit-code' -cin $flags -or '--quiet' -cin $flags){@(0,1)}else{@(0)}
    $formats=@('--check','--name-only','--name-status','--numstat','--stat','--shortstat','--dirstat','--summary','--word-diff','--color-words','--binary','--output','--format','--pretty','--graph','--abbrev','--cc','--combined-all-paths','--diff-merges','--no-patch','-s')
    if(@($flags|Where-Object {$_ -cin $formats}).Count){return Invoke-QuietGitRequestedFormat $Runtime ($Prefix+@($Request.Name)+@($Request.Arguments)) $Request.Name -Codes $codes -Delimiter $(if('-z' -cin $flags){0}else{10})}
    if(@($flags|Where-Object {$_ -cin @('--patch','-p','-u')}).Count){return Invoke-QuietGitDiff $Runtime $Request $Binding $Prefix}
    Import-QuietGitParser
    $arguments=Get-QuietGitArguments $Binding @('--raw','-z','--no-abbrev')
    $data=@{Command=$Request.Name;GitVersion=$Runtime.State.DetectedVersion;OutputMode='RawDiff';Files=[Collections.Generic.List[object]]::new();Commits=[Collections.Generic.List[object]]::new();Pending=$null;PendingPaths=0;Scope='Native comparison and recursion; full IDs and NUL path framing only.'}
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@($Request.Name,'--raw','--no-abbrev','-z')+$arguments) $data -Codes $codes -Delimiter 0 -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitRawDiffRecords]::Receive($record,$data)} -Finalize {param($data)[FrenchExDev2.QuietCli.Git.GitRawDiffRecords]::Finish($data);$data}
    $r.Data.ExitCode=$r.Execution.Native.ExitCode
    return $r.Data
}
