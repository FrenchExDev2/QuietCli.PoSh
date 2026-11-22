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
Classifies the repository, observes status in porcelain v2, then adds in-progress operations, a cheap repository
profile and an adaptive digest (full list or hot paths) published to -Listeners and -UI.
    .DESCRIPTION
    Outside a work tree (not a repository, bare, inside the git directory) the answer is classified with
    Outcome Success and Data.Repository.Kind; status itself is not run. Fatal discovery or status errors throw
    'Code: detail' with a GitDiagnostics code. Data keeps every entry; Digest only selects what to present.
    .PARAMETER Runtime
    Parent runtime.
    .PARAMETER Request
    Git status request.
    .PARAMETER Binding
    Bound options and pathspecs.
    .PARAMETER Prefix
    Native globals.
    #>
    param($Runtime,$Request,$Binding,[string[]]$Prefix,[switch]$Prepare)
    if($Runtime.Request.Transport -ne 'Pipe'){throw 'StatusBusinessProtocolRequiresPipe: use explicit -Output for terminal rendering.'}
    Import-QuietGitParser
    $branch=$true
    foreach($option in $Binding.Options){if($option.Name -ceq '--no-branch'){$branch=$false}elseif($option.Name -cin @('--branch','-b')){$branch=$true}}
    $untracked=@($Binding.Options|Where-Object Name -In @('-u','--untracked-files')|Select-Object -Last 1)
    $ignore=@($Binding.Options|Where-Object Name -EQ '--ignore-submodules'|Select-Object -Last 1)
    $verbose=@($Binding.Options|Where-Object Name -In @('-v','--verbose')).Count
    $stash=@($Binding.Options|Where-Object Name -In @('--show-stash','--no-show-stash')|Select-Object -Last 1)
    $showStash=!$stash.Count -or $stash[0].Name -ceq '--show-stash'
    $arguments=Get-QuietGitArguments $Binding @('--porcelain','--short','-s','--long','--branch','-b','--no-branch','--column','--no-column','-z','--null','-v','--verbose')
    $defaults=@('--porcelain=v2','-z');if($branch){$defaults+=@('--branch')};if(!$untracked.Count){$defaults+=@('--untracked-files=all')};if(!$ignore.Count){$defaults+=@('--ignore-submodules=none')};if(!$stash.Count){$defaults+=@('--show-stash')}
    $scope=@{WorkingDirectory=$Runtime.Request.WorkingDirectory;GitGlobalArguments=@($Request.Global);Pathspec=@($Binding.Tokens|Where-Object Kind -EQ Operand|ForEach-Object{$_.Raw});UntrackedFiles=$(if($untracked.Count -and $untracked[0].HasValue){$untracked[0].Value}else{'all'});IgnoreSubmodules=$(if($ignore.Count -and $ignore[0].HasValue){$ignore[0].Value}elseif($ignore.Count){'all'}else{'none'});RemoteState='local refs only';BranchObserved=$branch;PathRepresentation='NUL-delimited UTF-8 or explicit raw bytes';Verbose=$verbose}
    $data=@{Command='status';GitVersion=$Runtime.State.DetectedVersion;Repository=$null;Operations=@();Profile=$null;Digest=$null;Diagnostics=@();ElapsedMilliseconds=$null
        Branch=$null;HeadOid=$null;Unborn=$null;Detached=$null;Upstream=$null;UpstreamGone=$false;AheadBehindComputed=$null;Ahead=$null;Behind=$null;StashCount=$(if($showStash){0L}else{$null});Clean=$false
        Counts=@{Changed=0L;Staged=0L;Unstaged=0L;Untracked=0L;Conflicted=0L;Renamed=0L;Ignored=0L;Submodules=0L};Entries=[Collections.Generic.List[object]]::new();Pending=$null;AnswerComplete=$false;Scope=$scope}
    $probe=Read-QuietGitRepositoryProbe $Runtime $Prefix
    $data.Repository=$probe.Repository
    if($probe.Repository.Kind -cne 'WorkTree'){
        # Classified answer: there is no work tree to compare, so status is not run and no counter is claimed.
        $data.Remove('Pending');$data.Clean=$null;$data.Counts=$null;$data.StashCount=$null;$data.AnswerComplete=$true
        $data.Branch=$probe.Repository.HeadBranch;$data.Digest=@{Mode='Classified';Changed=$null;HotPaths=@();Listed=@();Omitted=0L}
        Write-QuietGitStatusPresentation $Runtime $data
        if($Prepare){return @{Data=$data}}
        return $data
    }
    $parser=Get-Command Receive-QuietGitStatusRecord
    $collector=New-QuietGitDiagnosticCollector
    $watch=[Diagnostics.Stopwatch]::StartNew()
    # 128/129 stay successful at the child level so the handler can classify stderr and throw a typed code.
    $r=Invoke-QuietGitRecords $Runtime ($Prefix+@('--no-optional-locks','status')+$defaults+$arguments) $data -Delimiter 0 -Diagnostics $collector -Codes @(0,128,129) -Parser {param($record,$data)& $parser $record $data}.GetNewClosure() -Finalize {param($data)[FrenchExDev2.QuietCli.Git.GitRecords]::FinalizeStatus($data);$data} -Prepare:$Prepare
    if($Prepare){
        $finish=Get-Command Complete-QuietGitStatus
        $cleanup=$r.Cleanup
        $r.Finish={param($result)& $finish $Runtime $Prefix $probe $scope $verbose $collector $watch $result}.GetNewClosure()
        $r.Cleanup={try{& $cleanup}finally{$collector.Stream.Dispose()}}.GetNewClosure()
        return $r
    }
    try{Complete-QuietGitStatus $Runtime $Prefix $probe $scope $verbose $collector $watch $r}
    finally{$collector.Stream.Dispose()}
}

function Complete-QuietGitStatus {
    <#
    .SYNOPSIS
    Classifies the observed status and enriches its caller-local business object.
    #>
    param($Runtime,[string[]]$Prefix,$probe,$scope,[int]$verbose,$collector,$watch,$r)
    $watch.Stop()
    $stderr=Read-QuietGitDiagnosticText $collector
    if($r.Execution.Native.ExitCode -ne 0){
        $diagnostic=[FrenchExDev2.QuietCli.Git.GitDiagnostics]::Classify($stderr,$r.Execution.Native.ExitCode)
        $detail=$diagnostic.Excerpt;if($diagnostic.Hint){$detail+=' Hint: '+$diagnostic.Hint}
        throw ($diagnostic.Code+': '+$detail)
    }
    if($r.Outcome -ne 'Success'){throw ('GitStatusObservationFailed: '+$r.Outcome)}
    $result=$r.Data;$result.ElapsedMilliseconds=[long]$watch.ElapsedMilliseconds
    $warnings=@([FrenchExDev2.QuietCli.Git.GitDiagnostics]::Warnings($stderr))
    if($collector.Truncated){$warnings+=@(@{Code='GitDiagnosticsTruncated';Severity='Warning';Path=$null;Hint='Only the first 8 KiB of native diagnostics were classified.';Excerpt=$null})}
    $result.Diagnostics=$warnings
    $incomplete=@($warnings|Where-Object {[FrenchExDev2.QuietCli.Git.GitDiagnostics]::MakesAnswerIncomplete($_.Code)}).Count -gt 0
    $result.AnswerComplete=$r.Completeness.Source -and $r.Completeness.Analysis -and !$incomplete
    $result.Operations=Read-QuietGitOperationState $Runtime $Prefix $probe $result.Counts.Conflicted
    $result.Profile=Read-QuietGitRepositoryProfile $Runtime $Prefix $probe $result.Counts.Changed $result.ElapsedMilliseconds $scope.UntrackedFiles ($null -ne $result.Upstream -and !$result.UpstreamGone)
    $result.Digest=[FrenchExDev2.QuietCli.Git.GitStatusDigest]::Build($result.Entries)
    if($verbose -gt 0){$patch=@{Name='diff';Arguments=@('--cached');Original=@('diff','--cached')};$bound=Get-GitArgumentToken -Request $patch -Version $Runtime.State.DetectedVersion;$result.StagedPatch=Invoke-QuietGitDiff $Runtime $patch $bound $Prefix}
    if($verbose -gt 1){$patch=@{Name='diff';Arguments=@();Original=@('diff')};$bound=Get-GitArgumentToken -Request $patch -Version $Runtime.State.DetectedVersion;$result.UnstagedPatch=Invoke-QuietGitDiff $Runtime $patch $bound $Prefix}
    Write-QuietGitStatusPresentation $Runtime $result
    return $result
}
