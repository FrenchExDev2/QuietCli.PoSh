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
    Import-QuietGitParser
    [FrenchExDev2.QuietCli.Git.GitRecords]::Status($Record,$Data)
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
