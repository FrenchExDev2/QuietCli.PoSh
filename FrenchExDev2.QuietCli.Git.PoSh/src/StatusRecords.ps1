function Receive-QuietGitStatusRecord {
    <#
.SYNOPSIS
Parses porcelain-v2 bytes, preserving raw paths and rename source boundaries.
    .PARAMETER Record
    Exact NUL-delimited bytes.
    .PARAMETER Data
    Parsed status state.
    #>
    param([byte[]]$Record,[hashtable]$Data)
    if($Data.Pending){$Data.Pending.OriginalPath=ConvertFrom-QuietGitBytes $Record;$Data.Pending=$null;return}
    if(!$Record.Length){return}
    if($Record[0] -eq 35){
        $space=[Array]::IndexOf($Record,[byte]32,2);if($space -lt 0){return}
        $key=[Text.Encoding]::ASCII.GetString($Record,2,$space-2)
        $bytes=[byte[]]::new($Record.Length-$space-1);[Array]::Copy($Record,$space+1,$bytes,0,$bytes.Length);$value=ConvertFrom-QuietGitBytes $bytes
        switch -CaseSensitive ($key){
            'branch.head' {$Data.Detached=$value -is [string] -and $value -ceq '(detached)';$Data.Branch=if($Data.Detached){$null}else{$value}}
            'branch.oid' {$Data.Unborn=$value -is [string] -and $value -ceq '(initial)';$Data.HeadOid=if($Data.Unborn){$null}else{$value}}
            'branch.upstream' {$Data.Upstream=$value}
            'branch.ab' {if($value -isnot [string] -or $value -notmatch '^\+(\d+) -(\d+)$'){throw 'MalformedBranchDivergence'};$Data.Ahead=[long]$Matches[1];$Data.Behind=[long]$Matches[2]}
            stash {$Data.StashCount=[long]$value}
        }
        return
    }
    $kind=[char]$Record[0];$entry=$null
    if($kind -cin @('?','!')){
        if($Record.Length -lt 3 -or $Record[1] -ne 32){throw 'MalformedStatusPath'}
        $bytes=[byte[]]::new($Record.Length-2);[Array]::Copy($Record,2,$bytes,0,$bytes.Length)
        $entry=@{Kind=$(if($kind -eq '?'){'Untracked'}else{'Ignored'});Status=$(if($kind -eq '?'){'??'}else{'!!'});Path=(ConvertFrom-QuietGitBytes $bytes);OriginalPath=$null;Submodule=$null}
        if($kind -eq '?'){$Data.Counts.Untracked++;$Data.Counts.Changed++}else{$Data.Counts.Ignored++}
    }elseif($kind -cin @('1','2','u')){
        $limit=switch($kind){'1' {8} '2' {9} default {10}};$fields=[Collections.Generic.List[string]]::new();$start=0
        for($index=0;$index -lt $Record.Length -and $fields.Count -lt $limit;$index++){if($Record[$index] -eq 32){$fields.Add([Text.Encoding]::ASCII.GetString($Record,$start,$index-$start));$start=$index+1}}
        if($fields.Count -ne $limit -or $start -ge $Record.Length -or $fields[1] -notmatch '^[.MADRCUT]{2}$'){throw 'MalformedPorcelainStatusRecord'}
        $bytes=[byte[]]::new($Record.Length-$start);[Array]::Copy($Record,$start,$bytes,0,$bytes.Length)
        $entry=@{Kind=$(if($kind -eq 'u'){'Conflicted'}elseif($kind -eq '2'){'RenamedOrCopied'}else{'Tracked'});Status=$fields[1];Path=(ConvertFrom-QuietGitBytes $bytes);OriginalPath=$null;Submodule=$fields[2]}
        $Data.Counts.Changed++
        if($kind -eq 'u'){$Data.Counts.Conflicted++}else{if($fields[1][0] -ne '.'){$Data.Counts.Staged++};if($fields[1][1] -ne '.'){$Data.Counts.Unstaged++}}
        if($kind -eq '2'){$Data.Pending=$entry;if($fields[8].StartsWith('R')){$Data.Counts.Renamed++}}
    }else{throw 'UnknownPorcelainStatusRecord'}
    $Data.Entries.Add($entry)
}
function Invoke-QuietGitStatus {
    <#
.SYNOPSIS
Normalizes status presentation to a streaming protocol and declares the observed scope.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git status request.
    .PARAMETER Binding
    Bound options and pathspecs.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix)
    if($Runtime.Request.Transport -ne 'Pipe'){throw 'StatusBusinessProtocolRequiresPipe: use explicit -Output for terminal rendering.'}
    $flags=@($Binding.Options.Name);$branch=$true
    foreach($option in $Binding.Options){if($option.Name -ceq '--no-branch'){$branch=$false}elseif($option.Name -cin @('--branch','-b')){$branch=$true}}
    $untracked=@($Binding.Options|Where-Object Name -In @('-u','--untracked-files')|Select-Object -Last 1)
    $ignore=@($Binding.Options|Where-Object Name -EQ '--ignore-submodules'|Select-Object -Last 1)
    $verbose=@($Binding.Options|Where-Object Name -In @('-v','--verbose')).Count
    $arguments=Get-QuietGitArguments $Binding @('--porcelain','--short','-s','--long','--branch','-b','--no-branch','--column','--no-column','-z','--null','-v','--verbose')
    $defaults=@('--porcelain=v2','-z');if($branch){$defaults+=@('--branch')};if(!$untracked.Count){$defaults+=@('--untracked-files=all')};if(!$ignore.Count){$defaults+=@('--ignore-submodules=none')}
    $data=@{Command='status';GitVersion=$Runtime.State.DetectedVersion;Branch=$null;HeadOid=$null;Unborn=$null;Detached=$null;Upstream=$null;Ahead=$null;Behind=$null;StashCount=$(if('--show-stash' -cin $flags){0L}else{$null});Clean=$false
        Counts=@{Changed=0L;Staged=0L;Unstaged=0L;Untracked=0L;Conflicted=0L;Renamed=0L;Ignored=0L};Entries=[Collections.Generic.List[object]]::new();Pending=$null;AnswerComplete=$false
        Scope=@{WorkingDirectory=$Runtime.Request.WorkingDirectory;GitGlobalArguments=@($Request.Global);Pathspec=@($Binding.Tokens|Where-Object Kind -EQ Operand|ForEach-Object{$_.Raw});UntrackedFiles=$(if($untracked.Count -and $untracked[0].HasValue){$untracked[0].Value}else{'all'});IgnoreSubmodules=$(if($ignore.Count -and $ignore[0].HasValue){$ignore[0].Value}elseif($ignore.Count){'all'}else{'none'});RemoteState='local refs only';BranchObserved=$branch;PathRepresentation='NUL-delimited UTF-8 or explicit raw bytes';Verbose=$verbose}}
    $parser=Get-Command Receive-QuietGitStatusRecord
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('--no-optional-locks','status')+$defaults+$arguments) $data -Delimiter 0 -Parser {param($record,$data)& $parser $record $data}.GetNewClosure() -Finalize {param($data)if($data.Pending){throw 'IncompleteRenameSource'};$data.Remove('Pending');$data.Clean=$data.Counts.Changed -eq 0;$data}
    $result=$r.Data;$result.AnswerComplete=$r.Completeness.Source -and $r.Completeness.Analysis
    if($verbose -gt 0){$patch=@{Name='diff';Arguments=@('--cached');Original=@('diff','--cached')};$bound=Get-GitArgumentToken -Request $patch -Version $Runtime.State.DetectedVersion;$result.StagedPatch=Invoke-QuietGitDiff $Runtime $patch $bound $Prefix}
    if($verbose -gt 1){$patch=@{Name='diff';Arguments=@();Original=@('diff')};$bound=Get-GitArgumentToken -Request $patch -Version $Runtime.State.DetectedVersion;$result.UnstagedPatch=Invoke-QuietGitDiff $Runtime $patch $bound $Prefix}
    return $result
}
