function New-QuietGitPatch {
    <#
.SYNOPSIS
Creates parsed patch state using format-sensitive Git routing.
    .PARAMETER Name
    Command producing the patch.
    .PARAMETER Version
    Observed Git version.
    #>
    param([string]$Name,[string]$Version)
    return @{Command=$Name;GitVersion=$Version;OutputMode='Patch';Files=[Collections.Generic.List[object]]::new();Preamble=[Collections.Generic.List[object]]::new();Commits=[Collections.Generic.List[object]]::new();CurrentFile=$null;CurrentHunk=$null;CurrentCommit=$null;Scope='Requested patch records; labels retain native Git display quoting.'}
}
function Receive-QuietGitPatchRecord {
    <#
.SYNOPSIS
Parses one patch line while preserving non-UTF8 payloads and combined diff records.
    .PARAMETER Record
    Exact bytes excluding LF.
    .PARAMETER Data
    Parsed patch state.
    #>
    param([byte[]]$Record,[hashtable]$Data)
    Import-QuietGitParser
    [FrenchExDev2.QuietCli.Git.GitRecords]::Patch($Record,$Data)
}
function Complete-QuietGitPatch {
    <#
.SYNOPSIS
Drops parser cursors from the public business object without serializing it.
    .PARAMETER Data
    Parsed patch object.
    #>
    param([hashtable]$Data)
    $Data.Remove('CurrentFile');$Data.Remove('CurrentHunk');$Data.Remove('CurrentCommit')
    return $Data
}
function Invoke-QuietGitDiff {
    <#
.SYNOPSIS
Routes patch and explicit raw formats separately, preserving exit-code semantics.
    .PARAMETER Runtime
    Parent invocation.
    .PARAMETER Request
    Git request.
    .PARAMETER Binding
    Bound options, excluding flag-looking option values.
    .PARAMETER Prefix
    Native Git globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    $flags=@($Binding.Options.Name)
    $codes=if('--check' -cin $flags){@(0,1,2)}elseif('--exit-code' -cin $flags -or '--quiet' -cin $flags){@(0,1)}else{@(0)}
    $arguments=$Prefix+@($Request.Name)+@($Request.Arguments)
    $formats=@('--name-only','--name-status','--numstat','--raw','--stat','--shortstat','--dirstat','--summary','--check','--word-diff','--color-words','--binary','--output','--format','--pretty','--graph')
    if(@($flags|Where-Object{$_ -cin $formats}).Count){$delimiter=if('-z' -cin $flags -or '--null' -cin $flags){[byte]0}else{[byte]10};return Invoke-QuietGitRequestedFormat $Runtime $arguments $Request.Name -Codes $codes -Delimiter $delimiter}
    $parser=Get-Command Receive-QuietGitPatchRecord;$finish=Get-Command Complete-QuietGitPatch
    $r=Invoke-QuietGitRecords $Runtime $arguments (New-QuietGitPatch $Request.Name $Runtime.State.DetectedVersion) -Codes $codes -Parser {param($record,$data)& $parser $record $data}.GetNewClosure() -Finalize {param($data)& $finish $data}.GetNewClosure()
    return $r.Data
}
