function Test-QuietGitVersionAtLeast {
    <#
    .SYNOPSIS
    Compares the observed Git version (including .windows.N variants) with a minimum major.minor release.
    .PARAMETER Version
    Detected version text, for example 2.50.1.windows.1.
    .PARAMETER Major
    Minimum major version.
    .PARAMETER Minor
    Minimum minor version.
    #>
    param([string]$Version,[int]$Major,[int]$Minor)
    if($Version -notmatch '^(\d+)\.(\d+)'){return $false}
    $observedMajor=[int]$Matches[1];$observedMinor=[int]$Matches[2]
    return $observedMajor -gt $Major -or ($observedMajor -eq $Major -and $observedMinor -ge $Minor)
}
function Invoke-QuietGitProbeLines {
    <#
    .SYNOPSIS
    Runs one read-only Git observation and returns its bounded stdout lines, exit code and bounded stderr.
    .DESCRIPTION
    Stdout is limited to 64 KiB and stderr to 8 KiB. Exit codes listed in Codes keep the child invocation
    successful, so an expected discovery failure (exit 128 outside a repository) is classified instead of
    failing the parent handler.
    .PARAMETER Runtime
    Parent handler runtime.
    .PARAMETER Arguments
    Exact Git argument vector, including the native global prefix.
    .PARAMETER Codes
    Documented non-error exit codes.
    #>
    param($Runtime,[string[]]$Arguments,[int[]]$Codes=@(0))
    $data=@{Out=(New-QuietGitDiagnosticCollector -Limit 65536);Err=(New-QuietGitDiagnosticCollector)}
    $add=Get-Command Add-QuietGitDiagnosticBytes
    $r=Invoke-QuietGitNative $Runtime $Arguments -Role Observation -SuccessExitCodes $Codes -StdoutMode Bytes -StderrMode Bytes -Data $data -Output {
        param($e,$r)
        if($e.Stream -eq 'stdout'){& $add $r.Data.Out $e.Bytes}elseif($e.Stream -eq 'stderr'){& $add $r.Data.Err $e.Bytes}
    }.GetNewClosure() -Complete {param($r)$r.Data}
    if($r.Outcome -ne 'Success'){throw ('GitObservationFailed: '+$Arguments[$Arguments.Count-1]+' '+$r.Outcome)}
    if($data.Out.Truncated){throw 'GitObservationTooLarge'}
    $lines=@((Read-QuietGitDiagnosticText $data.Out) -split "`n"|ForEach-Object {$_.TrimEnd("`r")})
    if($lines.Count -and $lines[$lines.Count-1] -ceq ''){$lines=@($lines|Select-Object -First ($lines.Count-1))}
    return @{ExitCode=$r.Execution.Native.ExitCode;Lines=$lines;Stderr=(Read-QuietGitDiagnosticText $data.Err)}
}
function Read-QuietGitRepositoryProbe {
    <#
    .SYNOPSIS
    Classifies the working directory (not a repository, bare, inside the git directory, outside the work tree, or
    work tree) with one rev-parse process, and resolves the per-worktree state paths used for operations.
    .DESCRIPTION
    Every requested rev-parse option prints exactly one line, so the answer is parsed by position. The work-tree
    root and superproject are requested optimistically in the same process; only when Git answers 'must be run in a
    work tree' (bare, inside the git directory, outside the work tree) is the probe repeated without them. Discovery
    failures are classified from stderr: NotARepository becomes a classified answer, any other fatal discovery
    error (dubious ownership, broken gitfile, unsupported format...) throws 'Code: detail'.
    .PARAMETER Runtime
    Parent handler runtime.
    .PARAMETER Prefix
    Native global arguments (pager, color and user globals such as -C).
    #>
    param($Runtime,[string[]]$Prefix)
    $showRefFormat=Test-QuietGitVersionAtLeast ([string]$Runtime.State.DetectedVersion) 2 45
    $names=@('index','objects','MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','rebase-merge','rebase-apply','BISECT_LOG','BISECT_START','sequencer')
    $arguments=$Prefix+@('rev-parse','--path-format=absolute','--is-inside-work-tree','--is-bare-repository','--is-inside-git-dir','--is-shallow-repository','--absolute-git-dir','--git-common-dir','--show-object-format')
    if($showRefFormat){$arguments+=@('--show-ref-format')}
    foreach($name in $names){$arguments+=@('--git-path',$name)}
    $withTop=$true
    $probe=Invoke-QuietGitProbeLines $Runtime ($arguments+@('--show-toplevel','--show-superproject-working-tree')) @(0,128)
    if($probe.ExitCode -eq 128 -and [string]$probe.Stderr -match 'must be run in a work tree'){
        $withTop=$false
        $probe=Invoke-QuietGitProbeLines $Runtime $arguments @(0,128)
    }
    $repository=@{Kind=$null;WorkTree=$null;GitDirectory=$null;CommonDirectory=$null;LinkedWorktree=$false;Submodule=$false;Superproject=$null;Shallow=$false;ObjectFormat=$null;RefFormat=$null;HeadBranch=$null;SearchBoundary=$null;Sparse=$null;PartialClone=$false}
    if($probe.ExitCode -ne 0){
        $diagnostic=[FrenchExDev2.QuietCli.Git.GitDiagnostics]::Classify($probe.Stderr,$probe.ExitCode)
        if($diagnostic.Code -cne 'NotARepository'){
            $detail=$diagnostic.Excerpt;if($diagnostic.Hint){$detail+=' Hint: '+$diagnostic.Hint}
            throw ($diagnostic.Code+': '+$detail)
        }
        $repository.Kind='NotARepository';$repository.SearchBoundary=$diagnostic.Path
        return @{Repository=$repository;Paths=@{};Diagnostics=@($diagnostic)}
    }
    $expected=7+[int]$showRefFormat+$names.Count+[int]$withTop
    $received=$probe.Lines.Count
    if($received -ne $expected -and -not ($withTop -and $received -eq $expected+1)){throw ('GitProbeProtocolMismatch: expected '+$expected+' lines, received '+$received)}
    $line=$probe.Lines;$position=7
    $insideWorkTree=$line[0] -ceq 'true';$bare=$line[1] -ceq 'true';$insideGitDir=$line[2] -ceq 'true'
    $repository.Shallow=$line[3] -ceq 'true';$repository.GitDirectory=$line[4];$repository.CommonDirectory=$line[5];$repository.ObjectFormat=$line[6]
    $repository.RefFormat=if($showRefFormat){$line[$position];$position++}else{'files'}
    $paths=@{};foreach($name in $names){$paths[$name]=$line[$position];$position++}
    $repository.LinkedWorktree=[IO.Path]::GetFullPath($repository.GitDirectory).TrimEnd('/','\') -ne [IO.Path]::GetFullPath($repository.CommonDirectory).TrimEnd('/','\')
    $repository.Kind=if($insideWorkTree){'WorkTree'}elseif($bare){'Bare'}elseif($insideGitDir){'InsideGitDir'}else{'OutsideWorkTree'}
    if($withTop){
        $repository.WorkTree=$line[$position];$position++
        if($position -lt $received -and $line[$position]){$repository.Submodule=$true;$repository.Superproject=$line[$position]}
    }
    if($repository.Kind -ceq 'WorkTree'){
        if(-not $repository.WorkTree){throw 'GitProbeProtocolMismatch: missing work tree root'}
    }elseif($repository.Kind -ceq 'Bare'){
        $head=Read-QuietGitScalar $Runtime ($Prefix+@('symbolic-ref','-q','--short','HEAD')) @(0,1)
        if($head.Execution.Native.ExitCode -eq 0 -and $head.Data){$repository.HeadBranch=$head.Data}
    }
    return @{Repository=$repository;Paths=$paths;Diagnostics=@()}
}
function Read-QuietGitOperationState {
    <#
    .SYNOPSIS
    Detects in-progress merge, am, rebase, cherry-pick, revert, sequencer and bisect operations.
    .DESCRIPTION
    Porcelain v2 never reports these states. Detection reads the bounded state files resolved by the probe; with
    the reftable backend, CHERRY_PICK_HEAD and REVERT_HEAD are refs rather than files and are verified through
    rev-parse.
    .PARAMETER Runtime
    Parent handler runtime.
    .PARAMETER Prefix
    Native global arguments.
    .PARAMETER Probe
    Result of Read-QuietGitRepositoryProbe.
    .PARAMETER Conflicted
    Unmerged entries reported by status.
    #>
    param($Runtime,[string[]]$Prefix,$Probe,[long]$Conflicted)
    $pseudo=$null
    if($Probe.Repository.RefFormat -ceq 'reftable'){
        $pseudo=@{}
        foreach($name in @('CHERRY_PICK_HEAD','REVERT_HEAD')){
            $ref=Read-QuietGitScalar $Runtime ($Prefix+@('rev-parse','-q','--verify',$name)) @(0,1)
            $pseudo[$name]=if($ref.Execution.Native.ExitCode -eq 0){$ref.Data}else{$null}
        }
    }
    return ,@([FrenchExDev2.QuietCli.Git.GitRepositoryProfile]::Operations($Probe.Paths,$pseudo,$Conflicted))
}
function Read-QuietGitRepositoryProfile {
    <#
    .SYNOPSIS
    Measures the repository shape cheaply: index header, object counts and the few settings that change status cost.
    .DESCRIPTION
    Uses the index header (12 bytes), the pack index fan-out headers and loose object names (read in process, no
    count-objects child) and one config --get-regexp process. It never walks history and never fetches. Sparse-checkout and partial-clone facts are written back into Probe.Repository.
    .PARAMETER Runtime
    Parent handler runtime.
    .PARAMETER Prefix
    Native global arguments.
    .PARAMETER Probe
    Result of Read-QuietGitRepositoryProbe.
    .PARAMETER Changed
    Changed entries reported by status.
    .PARAMETER ElapsedMilliseconds
    Measured status duration.
    .PARAMETER UntrackedFiles
    Effective untracked-files mode.
    .PARAMETER HasUpstream
    True when the current branch has an upstream.
    #>
    param($Runtime,[string[]]$Prefix,$Probe,[long]$Changed,[long]$ElapsedMilliseconds,[string]$UntrackedFiles,[bool]$HasUpstream)
    $pattern='^(core\.(sparsecheckout|sparsecheckoutcone|fsmonitor|untrackedcache)|index\.sparse|feature\.manyfiles|extensions\.partialclone|remote\..*\.promisor)$'
    $config=@{Entries=[Collections.Generic.List[object]]::new()}
    $null=Invoke-QuietGitRecords $Runtime ($Prefix+@('config','-z','--get-regexp',$pattern)) $config -Role Observation -Delimiter 0 -Codes @(0,1) -Parser {param($record,$data)[FrenchExDev2.QuietCli.Git.GitConfigRecords]::Config($record,$data)}
    $settings=@{};$promisor=$false
    foreach($entry in $config.Entries){
        $name=([string]$entry.Name).ToLowerInvariant();$value=if($entry.HasValue){[string]$entry.Value}else{'true'}
        if($name -like 'remote.*.promisor'){if(Test-QuietGitConfigTrue $value){$promisor=$true}}else{$settings[$name]=$value}
    }
    $hexLength=if($Probe.Repository.ObjectFormat -ceq 'sha256'){64}else{40}
    $objects=[FrenchExDev2.QuietCli.Git.GitRepositoryProfile]::CountObjects($Probe.Paths['objects'],$hexLength,[FrenchExDev2.QuietCli.Git.GitRepositoryProfile]::DefaultLooseObjectLimit)
    $objectCount=$null;$packBytes=$null
    if($objects.Available){$objectCount=[long]$objects.Loose+[long]$objects.Packed;$packBytes=[long]$objects.PackBytes}
    $sparseIndex=Test-QuietGitConfigTrue $settings['index.sparse']
    $Probe.Repository.Sparse=@{Enabled=(Test-QuietGitConfigTrue $settings['core.sparsecheckout']);Cone=(Test-QuietGitConfigTrue $settings['core.sparsecheckoutcone']);SparseIndex=$sparseIndex}
    $Probe.Repository.PartialClone=$promisor -or [bool]$settings['extensions.partialclone']
    $index=[FrenchExDev2.QuietCli.Git.GitRepositoryProfile]::ReadIndexHeader($Probe.Paths['index'])
    $entries=if($index.Available){[long]$index.Entries}elseif($index.Reason -ceq 'NoIndex'){0L}else{$null}
    $profile=[FrenchExDev2.QuietCli.Git.GitRepositoryProfile]::Build($entries,$objectCount,$packBytes,$Changed,$sparseIndex)
    $profile.Index=$index;$profile.Objects=$objects;$profile.Alternates=[long]$objects.Alternates
    $manyFiles=Test-QuietGitConfigTrue $settings['feature.manyfiles']
    $untrackedCache=if($settings.ContainsKey('core.untrackedcache')){$settings['core.untrackedcache']}elseif($manyFiles){'true'}else{$null}
    $hintSettings=@{Fsmonitor=$settings['core.fsmonitor'];UntrackedCache=$untrackedCache;Shallow=$Probe.Repository.Shallow;HasUpstream=$HasUpstream;UntrackedFiles=$UntrackedFiles}
    $profile.Settings=@{Fsmonitor=$settings['core.fsmonitor'];UntrackedCache=$untrackedCache;ManyFiles=$manyFiles}
    $profile.Hints=@([FrenchExDev2.QuietCli.Git.GitRepositoryProfile]::Hints($profile,$hintSettings,$ElapsedMilliseconds))
    return $profile
}
function Test-QuietGitConfigTrue {
    <#
    .SYNOPSIS
    Interprets a Git boolean configuration value; unset is false.
    .PARAMETER Value
    Raw configuration value or null.
    #>
    param([AllowNull()][string]$Value)
    if([string]::IsNullOrEmpty($Value)){return $false}
    return $Value.ToLowerInvariant() -notin @('false','no','off','0')
}
function Format-QuietGitInvariant {
    <#
    .SYNOPSIS
    Formats display text with the invariant culture so rendered numbers do not depend on the session locale.
    .PARAMETER Format
    Composite format string.
    .PARAMETER Values
    Format arguments.
    #>
    param([string]$Format,[Parameter(ValueFromRemainingArguments)][object[]]$Values)
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture,$Format,[object[]]$Values)
}
function Format-QuietGitStatusPath {
    <#
    .SYNOPSIS
    Renders a business path for display; raw non-UTF-8 paths keep their explicit Base64 form.
    .PARAMETER Path
    String path or raw-bytes map.
    #>
    param($Path)
    if($Path -is [string]){return $Path}
    if($Path -is [Collections.IDictionary]){return '<bytes:'+$Path['Base64']+'>'}
    return [string]$Path
}
function Format-QuietGitStatusLines {
    <#
    .SYNOPSIS
    Builds the presentation of a status answer: header lines and ordered (lane, text, event) items.
    .DESCRIPTION
    Pure formatting, shared by the UI renderer and the listener events, so both channels show the same facts.
    .PARAMETER Data
    Complete status business data.
    #>
    param($Data)
    $repository=$Data.Repository;$items=[Collections.Generic.List[object]]::new();$header=[Collections.Generic.List[string]]::new()
    switch -CaseSensitive ($repository.Kind){
        'NotARepository' {
            $header.Add('Repo: not a git repository')
            $items.Add(@{Lane='summary';Text=$(if($repository.SearchBoundary){'Not a git repository (search stopped at mount point '+$repository.SearchBoundary+')'}else{'Not a git repository (no .git in this directory or its parents)'})})
        }
        'Bare' {
            $header.Add('Repo: bare repository '+$repository.GitDirectory)
            $items.Add(@{Lane='summary';Text='Bare repository: no work tree to compare'+$(if($repository.HeadBranch){', HEAD -> '+$repository.HeadBranch}else{''})})
        }
        'InsideGitDir' {
            $header.Add('Repo: inside git directory '+$repository.GitDirectory)
            $items.Add(@{Lane='summary';Text='Inside the git directory: run status from the work tree'})
        }
        'OutsideWorkTree' {
            $header.Add('Repo: git directory '+$repository.GitDirectory)
            $items.Add(@{Lane='summary';Text='Outside the work tree of '+$repository.GitDirectory})
        }
    }
    if($repository.Kind -cne 'WorkTree'){return @{Header=$header.ToArray();Items=$items.ToArray()}}
    $flags=@()
    if($repository.LinkedWorktree){$flags+='linked worktree'}
    if($repository.Submodule){$flags+='submodule of '+$repository.Superproject}
    if($repository.Shallow){$flags+='shallow'}
    if($repository.PartialClone){$flags+='partial clone'}
    if($repository.Sparse -and $repository.Sparse.Enabled){$flags+=$(if($repository.Sparse.Cone){'sparse (cone)'}else{'sparse'})}
    if($repository.RefFormat -ceq 'reftable'){$flags+='reftable'}
    if($repository.ObjectFormat -ceq 'sha256'){$flags+='sha256'}
    $header.Add('Repo: '+$repository.WorkTree+$(if($flags.Count){' ['+($flags -join ', ')+']'}else{''}))
    $branch=if($Data.Detached){'HEAD detached at '+$(if($Data.HeadOid){$Data.HeadOid.Substring(0,[Math]::Min(12,$Data.HeadOid.Length))}else{'?'})}elseif($Data.Unborn){'No commits yet on '+$Data.Branch}elseif($Data.Branch){'Branch: '+$Data.Branch}else{'Branch: (not observed)'}
    if($Data.Upstream){
        $branch+=' -> '+$Data.Upstream
        if($Data.UpstreamGone){$branch+=' (gone)'}elseif($Data.AheadBehindComputed -eq $false){$branch+=' (divergence not computed)'}elseif($null -ne $Data.Ahead){$branch+=$(if($Data.Ahead -eq 0 -and $Data.Behind -eq 0){' (up to date)'}else{' (+'+$Data.Ahead+' -'+$Data.Behind+')'})}
    }
    if($Data.StashCount){$branch+=' | stash '+$Data.StashCount}
    $header.Add($branch)
    if($Data.Profile){
        $p=$Data.Profile
        $checkout=if($null -ne $p.Checkout.IndexEntries){(Format-QuietGitInvariant '{0:N0} entries' $p.Checkout.IndexEntries)}else{'unknown entries'}
        $history=if($null -ne $p.History.Objects){(Format-QuietGitInvariant '{0:N0} objects' $p.History.Objects)}else{'unknown objects'}
        $header.Add('Profile: '+$p.Archetype+' | checkout '+$checkout+' ('+$p.Checkout.Class+') | history '+$history+' ('+$p.History.Class+') | changes '+$p.Changes.Class)
    }
    $index=0
    foreach($operation in @($Data.Operations)){
        $index++;$text=switch -CaseSensitive ($operation.Kind){
            'Merge' {'Merging '+$operation.Head.Substring(0,[Math]::Min(12,$operation.Head.Length))+$(if($operation.ReadyToCommit){': all conflicts fixed, run git commit'}else{': '+$operation.Conflicts+' conflict(s)'})}
            'Am' {'Applying mailbox patches '+$operation.Step+'/'+$operation.Total+$(if($operation.EmptyPatch){' (current patch is empty)'}else{''})}
            {$_ -cin @('Rebase','RebaseApply')} {'Rebasing'+$(if($operation.Interactive){' (interactive)'}else{''})+$(if($operation.Branch){' '+$operation.Branch}else{''})+$(if($operation.Onto){' onto '+$operation.Onto.Substring(0,[Math]::Min(12,$operation.Onto.Length))}else{''})+$(if($null -ne $operation.Step){' '+$operation.Step+'/'+$operation.Total}else{''})}
            'CherryPick' {'Cherry-picking '+$operation.Head.Substring(0,[Math]::Min(12,$operation.Head.Length))}
            'Revert' {'Reverting '+$operation.Head.Substring(0,[Math]::Min(12,$operation.Head.Length))}
            'Sequence' {'Sequencer in progress'+$(if($null -ne $operation.Remaining){', '+$operation.Remaining+' remaining'}else{''})}
            'Bisect' {'Bisecting'+$(if($operation.From){' (started from '+$operation.From+')'}else{''})}
            default {[string]$operation.Kind}
        }
        if($operation.Kind -cnotin @('Merge','Bisect') -and $operation.Conflicts){$text+=' | '+$operation.Conflicts+' conflict(s)'}
        $items.Add(@{Lane=('op:{0:D2}' -f $index);Text=$text})
    }
    $c=$Data.Counts
    $summary=if($Data.Clean){'Clean working tree'}else{Format-QuietGitInvariant '{0:N0} change(s): {1:N0} staged, {2:N0} unstaged, {3:N0} untracked, {4:N0} conflicted' $c.Changed $c.Staged $c.Unstaged $c.Untracked $c.Conflicted}
    if($c.Submodules){$summary+=(Format-QuietGitInvariant ', {0:N0} submodule(s)' $c.Submodules)}
    if(!$Data.AnswerComplete){$summary+=' (incomplete)'}
    $items.Add(@{Lane='summary';Text=$summary})
    $digest=$Data.Digest
    if($digest.Mode -ceq 'HotPaths'){
        $index=0
        foreach($hot in @($digest.HotPaths)){
            $index++
            $detail=@();foreach($pair in @(@('Staged','staged'),@('Unstaged','unstaged'),@('Untracked','untracked'),@('Conflicted','conflicted'))){if($hot[$pair[0]]){$detail+=(Format-QuietGitInvariant '{0:N0} {1}' $hot[$pair[0]] $pair[1])}}
            $label=if($hot.Kind -ceq 'Rest'){$hot.Path+' (rest: '+$hot.Groups+' smaller subpaths)'}else{$hot.Path}
            $items.Add(@{Lane=('hot:{0:D2}' -f $index);Text=(Format-QuietGitInvariant '{0,5:N1}% {1,7:N0}  {2}  [{3}]' $hot.Share $hot.Changed $label ($detail -join ', '));Event=$hot})
        }
        $index=0
        foreach($entry in @($digest.Listed|Select-Object -First 10)){$index++;$items.Add(@{Lane=('conflict:{0:D2}' -f $index);Text=($entry.Status+' '+(Format-QuietGitStatusPath $entry.Path))})}
        $hidden=[long]$Data.Counts.Changed-$index
        if($hidden -gt 0){$items.Add(@{Lane='more';Text=(Format-QuietGitInvariant '{0:N0} entries summarized by the hot paths above; the full list is in Data.Entries' $hidden)})}
    }elseif($digest.Mode -ceq 'List'){
        $index=0
        foreach($entry in @($digest.Listed)){
            $index++;$path=Format-QuietGitStatusPath $entry.Path
            if($null -ne $entry.OriginalPath){$path=(Format-QuietGitStatusPath $entry.OriginalPath)+' -> '+$path}
            $items.Add(@{Lane=('entry:{0:D2}' -f $index);Text=($entry.Status+' '+$path)})
        }
    }
    $index=0
    foreach($diagnostic in @($Data.Diagnostics)+@($(if($Data.Profile){$Data.Profile.Hints}))){
        if($null -eq $diagnostic){continue}
        $index++;$items.Add(@{Lane=('diag:{0:D2}' -f $index);Text=($diagnostic.Severity+' '+$diagnostic.Code+': '+$(if($diagnostic.Message){$diagnostic.Message}else{$diagnostic.Excerpt}))})
    }
    return @{Header=$header.ToArray();Items=$items.ToArray()}
}
function Write-QuietGitStatusPresentation {
    <#
    .SYNOPSIS
    Publishes the status answer to -Listeners (structured events) and to -UI (header plus one lane per line).
    .DESCRIPTION
    Business Data stays complete; this only presents it. Events: GitStatusRepository, GitStatusOperation,
    GitStatusSummary, GitStatusHotPath or GitStatusEntry, and GitStatusDiagnostic.
    .PARAMETER Runtime
    Outer handler runtime owning the caller's listeners and UI.
    .PARAMETER Data
    Complete status business data.
    #>
    param($Runtime,$Data)
    $view=Format-QuietGitStatusLines $Data
    $Runtime.Emit('GitStatusRepository',[pscustomobject]@{Repository=$Data.Repository})
    foreach($operation in @($Data.Operations)){$Runtime.Emit('GitStatusOperation',[pscustomobject]@{Operation=$operation})}
    $Runtime.Emit('GitStatusSummary',[pscustomobject]@{Branch=$Data.Branch;Upstream=$Data.Upstream;Ahead=$Data.Ahead;Behind=$Data.Behind;UpstreamGone=$Data.UpstreamGone;Counts=$Data.Counts;Mode=$Data.Digest.Mode;Profile=$Data.Profile;AnswerComplete=$Data.AnswerComplete})
    if($Data.Digest.Mode -ceq 'HotPaths'){foreach($hot in @($Data.Digest.HotPaths)){$Runtime.Emit('GitStatusHotPath',[pscustomobject]@{HotPath=$hot})}}
    foreach($entry in @($Data.Digest.Listed)){if($null -ne $entry){$Runtime.Emit('GitStatusEntry',[pscustomobject]@{Entry=$entry})}}
    foreach($diagnostic in @($Data.Diagnostics)+@($(if($Data.Profile){$Data.Profile.Hints}))){if($null -ne $diagnostic){$Runtime.Emit('GitStatusDiagnostic',[pscustomobject]@{Diagnostic=$diagnostic})}}
    if($Runtime.Ui){
        $Runtime.Ui.SetHeader([string[]]$view.Header)
        foreach($item in $view.Items){$Runtime.Ui.Write($item.Text,$item.Lane)}
    }
}
