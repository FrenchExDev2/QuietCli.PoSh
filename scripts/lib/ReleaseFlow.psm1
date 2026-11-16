#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReleaseTags.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GalleryRelease.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietReleaseCheckState {
    <#
    .SYNOPSIS
    Reduces a pull request status rollup to Success, Failure or Pending for one exact required check name.
    .PARAMETER Rollup
    statusCheckRollup entries returned by gh pr view (CheckRun and StatusContext objects).
    .PARAMETER RequiredCheck
    Exact check run name or status context; absent entries are Pending, never green.
    #>
    [CmdletBinding()]
    param([AllowNull()][object[]]$Rollup,[Parameter(Mandatory)][string]$RequiredCheck)
    $entries=@($Rollup|Where-Object {$null -ne $_ -and (([string]$_.name -ceq $RequiredCheck) -or ([string]$_.context -ceq $RequiredCheck))})
    if(!$entries.Count){return 'Pending'}
    $pending=$false
    foreach($entry in $entries){
        if([string]$entry.__typename -ceq 'StatusContext'){
            $value=[string]$entry.state
            if($value -cin @('PENDING','EXPECTED')){$pending=$true}elseif($value -cne 'SUCCESS'){return 'Failure'}
        }else{
            if([string]$entry.status -cne 'COMPLETED'){$pending=$true}elseif([string]$entry.conclusion -cne 'SUCCESS'){return 'Failure'}
        }
    }
    if($pending){'Pending'}else{'Success'}
}

function Get-QuietReleasePullRequestDecision {
    <#
    .SYNOPSIS
    Decides the next release action from one observed pull request state; performs no effect.
    .PARAMETER View
    Parsed gh pr view JSON carrying state, headRefOid, mergeCommit and statusCheckRollup.
    .PARAMETER CommitRevision
    Release commit the pull request head must still designate, open or merged.
    .PARAMETER RequiredCheck
    Exact required check name.
    .PARAMETER Merge
    Operator authorization to merge once the required check succeeds.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$View,[Parameter(Mandatory)][string]$CommitRevision,[Parameter(Mandatory)][string]$RequiredCheck,[switch]$Merge)
    $state=[string]$View.state
    if($state -cnotin @('OPEN','MERGED','CLOSED')){throw ('ReleasePullRequestStateInvalid: '+$state)}
    if($state -ceq 'CLOSED'){return [pscustomobject]@{Action='Fail';Reason='ReleasePullRequestClosed';Check=$null;MergeCommit=$null}}
    if([string]$View.headRefOid -cne $CommitRevision){return [pscustomobject]@{Action='Fail';Reason='ReleasePullRequestHeadChanged';Check=$null;MergeCommit=$null}}
    if($state -ceq 'MERGED'){
        $oid=[string]$View.mergeCommit.oid
        if($oid -cnotmatch '\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z'){return [pscustomobject]@{Action='Wait';Reason='MergeCommitPending';Check='Merged';MergeCommit=$null}}
        return [pscustomobject]@{Action='Tag';Reason='Merged';Check='Merged';MergeCommit=$oid}
    }
    $check=Get-QuietReleaseCheckState -Rollup @($View.statusCheckRollup) -RequiredCheck $RequiredCheck
    if($check -ceq 'Failure'){return [pscustomobject]@{Action='Fail';Reason='ReleasePullRequestChecksFailed';Check=$check;MergeCommit=$null}}
    if($check -ceq 'Success' -and $Merge){return [pscustomobject]@{Action='Merge';Reason='RequiredCheckSucceeded';Check=$check;MergeCommit=$null}}
    [pscustomobject]@{Action='Wait';Reason=$(if($check -ceq 'Success'){'AwaitingManualMerge'}else{'RequiredCheckPending'});Check=$check;MergeCommit=$null}
}

function Wait-QuietReleaseInterval {
    <#
    .SYNOPSIS
    Waits in one-second slices so a pipeline stop (Ctrl+C) is observed within about one second.
    .PARAMETER Seconds
    Whole seconds to wait; zero returns immediately.
    #>
    [CmdletBinding()]
    param([ValidateRange(0,3600)][int]$Seconds)
    for($slice=0;$slice -lt $Seconds;$slice++){[Threading.Tasks.Task]::Delay(1000).GetAwaiter().GetResult()}
}

function Write-QuietReleaseFlowState {
    <#
    .SYNOPSIS
    Atomically replaces the release flow receipt through a sibling temporary file.
    .PARAMETER State
    Ordered release flow state.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$State)
    $State.UpdatedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    $temporary=$State.Receipt+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,($State|ConvertTo-Json -Depth 8)+"`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary,$State.Receipt,$true)
}

function Read-QuietReleaseFlowState {
    <#
    .SYNOPSIS
    Reads and structurally validates a release flow receipt written by Write-QuietReleaseFlowState.
    .PARAMETER Path
    Receipt path, normally artifacts/releases/<id>/release-flow.json.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if(![IO.File]::Exists($Path)){throw ('ReleaseResumeReceiptMissing: '+$Path)}
    $state=[IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -AsHashtable
    if($state -isnot [Collections.IDictionary] -or $state.SchemaVersion -ne 1 -or $state.Phases -isnot [Collections.IDictionary] -or [string]$state.Branch -cnotmatch '\Arelease/[A-Za-z0-9._/-]+\z'){throw 'ReleaseResumeReceiptInvalid'}
    foreach($name in Get-QuietReleaseFlowPhaseNames){if([string]$state.Phases[$name] -cnotin @('NotStarted','Pending','Confirmed','Unknown','Skipped')){throw ('ReleaseResumeReceiptInvalid: '+$name)}}
    $state.Receipt=[IO.Path]::GetFullPath($Path)
    $state
}

function Get-QuietReleaseFlowPhaseNames {
    <#
    .SYNOPSIS
    Returns the ordered release flow phases.
    #>
    @('Prepare','Commit','Push','PullRequest','Merge','Tag','Restore')
}

function Invoke-QuietReleaseFlow {
    <#
    .SYNOPSIS
    Releases modules end to end: version commit on release/*, pull request, required check, merge commit, then tags only.
    .DESCRIPTION
    Every phase is recorded in artifacts/releases/<id>/release-flow.json before and after its effect. A stopped,
    failed, timed-out or killed run leaves Pending effects as Unknown and is continued with -Resume, which first
    reconciles Unknown effects against the local repository, the remote and GitHub. Merging uses only
    gh pr merge --merge --match-head-commit once the required check succeeds; it never forces, bypasses
    protection or pushes the delivery branch.
    .PARAMETER WorkspaceRoot
    Clean Git checkout of the repository to release.
    .PARAMETER Module
    Discovered component aliases, full package names or All.
    .PARAMETER Version
    Common requested base or full version; preview counters remain independent per package.
    .PARAMETER Preview
    Explicit positive preview number, or null for the next available number.
    .PARAMETER PreviewSpecified
    Distinguishes omitted Preview from an explicitly supplied null.
    .PARAMETER NextPreview
    Requests automatic numeric preview selection.
    .PARAMETER Message
    Optional release commit message.
    .PARAMETER Remote
    Configured Git remote name.
    .PARAMETER DeliveryBranch
    Protected branch receiving the release pull request; tags require their commit on it.
    .PARAMETER Repository
    GitHub owner/name; resolved from the remote URL when omitted.
    .PARAMETER Resume
    Receipt of an unfinished run; the request recorded there is reused.
    .PARAMETER Merge
    Merges the pull request with a merge commit once the required check succeeds; otherwise waits for a manual merge.
    .PARAMETER PollSeconds
    Interval between pull request observations.
    .PARAMETER TimeoutMinutes
    Bound on waiting for the check and merge; zero observes once. A timeout is resumable.
    .PARAMETER RequiredCheck
    Exact required check name.
    .PARAMETER GitCommand
    Exact-argument quiet Git callback returning Value, HasOutput and Lines.
    .PARAMETER CommitCommand
    Checked commit callback receiving root, message and paths.
    .PARAMETER PushBranchCommand
    Branch push callback receiving root, remote and branch; only release/* branches are pushed.
    .PARAMETER GitHubCommand
    GitHub CLI callback receiving exact arguments and returning standard output text.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High',DefaultParameterSetName='Start')]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(ParameterSetName='Start')][string[]]$Module=@('Core'),
        [Parameter(Mandatory,ParameterSetName='Start')][string]$Version,
        [Parameter(ParameterSetName='Start')][Nullable[int]]$Preview,
        [Parameter(ParameterSetName='Start')][switch]$PreviewSpecified,
        [Parameter(ParameterSetName='Start')][switch]$NextPreview,
        [Parameter(ParameterSetName='Start')][string]$Message,
        [Parameter(ParameterSetName='Start')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
        [Parameter(ParameterSetName='Start')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._/-]*\z')][string]$DeliveryBranch='develop',
        [Parameter(ParameterSetName='Start')][ValidatePattern('\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z')][string]$Repository,
        [Parameter(Mandatory,ParameterSetName='Resume')][string]$Resume,
        [switch]$Merge,[ValidateRange(0,3600)][int]$PollSeconds=30,[ValidateRange(0,1440)][double]$TimeoutMinutes=120,
        [ValidateNotNullOrEmpty()][string]$RequiredCheck='QuietCli required CI',
        [Parameter(Mandatory)][scriptblock]$GitCommand,[Parameter(Mandatory)][scriptblock]$CommitCommand,
        [Parameter(Mandatory)][scriptblock]$PushBranchCommand,[Parameter(Mandatory)][scriptblock]$GitHubCommand)
    $ErrorActionPreference='Stop'
    $WorkspaceRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path))
    $phaseNames=Get-QuietReleaseFlowPhaseNames
    if($PSCmdlet.ParameterSetName -ceq 'Resume'){
        $state=Read-QuietReleaseFlowState -Path ([IO.Path]::GetFullPath($Resume,$PWD.Path))
        $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
        if(![string]::Equals([string]$state.WorkspaceRoot,$WorkspaceRoot,$comparison)){throw 'ReleaseResumeWorkspaceMismatch'}
        if($state.Completed){throw ('ReleaseResumeAlreadyCompleted: '+$state.Receipt)}
        if($Merge){$state.Request.Merge=$true}
        $next=@($phaseNames|Where-Object {$state.Phases[$_] -cnotin @('Confirmed','Skipped')})[0]
        if(!$PSCmdlet.ShouldProcess(($WorkspaceRoot+' @ '+$state.Branch),('Resume release from phase '+$next+'; merge='+[bool]$state.Request.Merge))){return [pscustomobject]$state}
    }else{
        $originalBranch=(& $GitCommand @('rev-parse','--abbrev-ref','HEAD')).Value
        $originalRevision=(& $GitCommand @('rev-parse','--verify','HEAD^{commit}')).Value
        $selection=@{WorkspaceRoot=$WorkspaceRoot;Module=$Module;Version=$Version;Preview=$Preview;PreviewSpecified=$PreviewSpecified;NextPreview=$NextPreview;KnownTags=@((& $GitCommand @('tag','--list')).Lines)}
        $provisional=@(Get-QuietModuleReleaseSelection @selection)
        if(!$Repository){
            $url=(& $GitCommand @('remote','get-url',$Remote)).Value
            if($url -notmatch '\A(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?\z'){throw 'ReleaseFlowRemoteNotGitHub: pass -Repository owner/name.'}
            $Repository=$Matches.repo
        }
        $id=[guid]::NewGuid().ToString('N')
        $stamp=[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
        $branch='release/'+((@($provisional|ForEach-Object {$_.Component.ToLowerInvariant()}) -join '-'))+'-'+$Version+'-'+$stamp+'-'+$id.Substring(0,6)
        $null=& $GitCommand @('check-ref-format','--branch',$branch)
        $state=[ordered]@{SchemaVersion=1;Id=$id;Receipt=$null;WorkspaceRoot=$WorkspaceRoot
            Request=[ordered]@{Module=@($Module);Version=$Version;Preview=$Preview;PreviewSpecified=[bool]$PreviewSpecified;NextPreview=[bool]$NextPreview;Message=$Message;Merge=[bool]$Merge}
            Remote=$Remote;DeliveryBranch=$DeliveryBranch;Repository=$Repository;RequiredCheck=$RequiredCheck
            OriginalBranch=$originalBranch;OriginalRevision=$originalRevision;Branch=$branch;BaseRevision=$null;CommitRevision=$null
            Releases=@($provisional|ForEach-Object {[ordered]@{Module=$_.Module;Component=$_.Component;Version=$_.Version;Tag=$_.Tag}})
            Provisional=$true;PullRequest=[ordered]@{Number=$null;Url=$null};MergeRequested=$false;MergeCommit=$null;Tags=@();TagReceipt=$null
            Phases=[ordered]@{};Phase=$null;LastCheck=$null;Interrupted=$false;Failure=$null;Completed=$false;UpdatedUtc=$null}
        foreach($name in $phaseNames){$state.Phases[$name]='NotStarted'}
        $description=(@($provisional|ForEach-Object {$_.Module+' '+$_.Version}) -join ', ')
        if(!$PSCmdlet.ShouldProcess(($WorkspaceRoot+' @ '+$originalRevision),('Release '+$description+' (provisional) through '+$branch+' and a pull request into '+$Remote+'/'+$DeliveryBranch+' on '+$Repository+'; merge='+[bool]$Merge+'; tags follow the merge'))){return [pscustomobject]$state}
        if((& $GitCommand @('status','--porcelain=v1','--untracked-files=normal')).HasOutput){throw 'ReleaseFlowRequiresCleanCheckout'}
        $directory=[IO.Path]::Combine($WorkspaceRoot,'artifacts','releases',$state.Id)
        [void][IO.Directory]::CreateDirectory($directory)
        $state.Receipt=[IO.Path]::Combine($directory,'release-flow.json')
        Write-QuietReleaseFlowState $state
    }
    $request=$state.Request
    $releaseOptions=@{WorkspaceRoot=$WorkspaceRoot;Module=@($request.Module);Version=[string]$request.Version;Preview=$request.Preview;PreviewSpecified=[bool]$request.PreviewSpecified;NextPreview=[bool]$request.NextPreview;Remote=$state.Remote;DeliveryBranch=$state.DeliveryBranch;GitCommand=$GitCommand}
    $repositoryArguments=@('--repo',[string]$state.Repository)
    $flight=@{Active=$false}
    $sequence={param([string[]]$a,[object[]]$b) (@($a) -join "`n") -ceq (@($b) -join "`n")}
    $readBranch={(& $GitCommand @('for-each-ref','--format=%(objectname)',('refs/heads/'+$state.Branch))).Value}
    $remoteTagCommits={
        $found=@{}
        foreach($tag in @($state.Releases|ForEach-Object {$_.Tag})){
            $line=(& $GitCommand @('ls-remote',$state.Remote,('refs/tags/'+$tag+'^{}'))).Value
            if($line){$found[$tag]=($line -split "`t")[0]}
        }
        $found
    }
    $viewPullRequest={(& $GitHubCommand (@('pr','view',[string]$state.PullRequest.Number)+$repositoryArguments+@('--json','state,headRefOid,mergeCommit,statusCheckRollup,url')))|ConvertFrom-Json}
    $listPullRequests={@((& $GitHubCommand (@('pr','list')+$repositoryArguments+@('--head',$state.Branch,'--state','all','--limit','5','--json','number,state,headRefName,url')))|ConvertFrom-Json|Where-Object {$_.headRefName -ceq $state.Branch})}
    $switchTo={
        param([string[]]$arguments)
        $flight.Active=$true
        $null=& $GitCommand (@('switch')+$arguments)
        $flight.Active=$false
    }
    try{
        if($PSCmdlet.ParameterSetName -ceq 'Resume'){
            if((& $GitCommand @('status','--porcelain=v1','--untracked-files=normal')).HasOutput){throw 'ReleaseFlowRequiresCleanCheckout: inspect and discard or commit the interrupted edits first.'}
            $state.Interrupted=$false;$state.Failure=$null
            foreach($name in $phaseNames){
                if($state.Phases[$name] -cnotin @('Pending','Unknown')){continue}
                switch($name){
                    'Prepare'{
                        $tip=& $readBranch
                        if(!$tip){$state.Phases.Prepare='NotStarted'}elseif($tip -ceq $state.BaseRevision){$state.Phases.Prepare='Confirmed'}else{throw 'ReleaseResumeStateConflict: Prepare'}
                    }
                    'Commit'{
                        $tip=& $readBranch
                        if($tip -ceq $state.BaseRevision){$state.Phases.Commit='NotStarted'}
                        elseif($tip -and (& $GitCommand @('rev-parse','--verify',($tip+'^1'))).Value -ceq $state.BaseRevision){
                            & $switchTo @($state.Branch)
                            $current=@(Select-QuietGalleryReleaseTargets $WorkspaceRoot -Module @($request.Module))
                            foreach($release in $state.Releases){if(@($current|Where-Object {$_.Module -ceq $release.Module -and $_.Version -ceq $release.Version}).Count -ne 1){throw ('ReleaseResumeStateConflict: Commit '+$release.Module)}}
                            $state.CommitRevision=$tip;$state.Provisional=$false;$state.Phases.Commit='Confirmed'
                        }else{throw 'ReleaseResumeStateConflict: Commit'}
                    }
                    'Push'{
                        $line=(& $GitCommand @('ls-remote','--heads',$state.Remote,('refs/heads/'+$state.Branch))).Value
                        if(!$line){$state.Phases.Push='NotStarted'}elseif(($line -split "`t")[0] -ceq $state.CommitRevision){$state.Phases.Push='Confirmed'}else{throw 'ReleaseResumeStateConflict: Push'}
                    }
                    'PullRequest'{
                        $items=@(& $listPullRequests)
                        if(!$items.Count){$state.Phases.PullRequest='NotStarted'}elseif($items.Count -eq 1){$state.PullRequest.Number=[int]$items[0].number;$state.PullRequest.Url=[string]$items[0].url;$state.Phases.PullRequest='Confirmed'}else{throw 'ReleaseResumeStateConflict: PullRequest'}
                    }
                    # The merge loop observes GitHub before acting, so a sent merge is never repeated.
                    'Merge'{$state.Phases.Merge='NotStarted'}
                    'Tag'{
                        $found=& $remoteTagCommits
                        $expected=@($state.Releases|ForEach-Object {$_.Tag})
                        if($found.Count -eq $expected.Count -and @($found.Values|Where-Object {$_ -cne $state.MergeCommit}).Count -eq 0){$state.Tags=$expected;$state.Phases.Tag='Confirmed'}
                        elseif(!$found.Count){$state.Phases.Tag='NotStarted'}
                        else{throw 'ReleaseResumeStateConflict: Tag'}
                    }
                    'Restore'{$state.Phases.Restore='NotStarted'}
                }
            }
            Write-QuietReleaseFlowState $state
        }
        foreach($name in $phaseNames){
            if($state.Phases[$name] -cin @('Confirmed','Skipped')){continue}
            $state.Phase=$name
            switch($name){
                'Prepare'{
                    if(& $readBranch){throw ('ReleaseBranchAlreadyExists: '+$state.Branch)}
                    if((& $GitCommand @('ls-remote','--heads',$state.Remote,('refs/heads/'+$state.Branch))).HasOutput){throw ('ReleaseBranchAlreadyExists: '+$state.Remote+'/'+$state.Branch)}
                    $null=& $GitCommand @('fetch','--no-tags','--quiet',$state.Remote,('refs/heads/'+$state.DeliveryBranch))
                    $state.BaseRevision=(& $GitCommand @('rev-parse','--verify','FETCH_HEAD^{commit}')).Value
                    $state.Phases.Prepare='Pending';Write-QuietReleaseFlowState $state
                    & $switchTo @('--no-track','-c',$state.Branch,$state.BaseRevision)
                    $state.Phases.Prepare='Confirmed';Write-QuietReleaseFlowState $state
                }
                'Commit'{
                    if((& $GitCommand @('rev-parse','--abbrev-ref','HEAD')).Value -cne $state.Branch){& $switchTo @($state.Branch)}
                    if((& $GitCommand @('rev-parse','--verify','HEAD^{commit}')).Value -cne $state.BaseRevision){throw 'ReleaseResumeStateConflict: release branch moved before its commit'}
                    $known=@((& $GitCommand @('tag','--list')).Lines)+@((& $GitCommand @('ls-remote','--tags','--refs',$state.Remote)).Lines)
                    $selection=@{WorkspaceRoot=$WorkspaceRoot;Module=@($request.Module);Version=[string]$request.Version;Preview=$request.Preview;PreviewSpecified=[bool]$request.PreviewSpecified;NextPreview=[bool]$request.NextPreview;KnownTags=$known}
                    $selected=@(Get-QuietModuleReleaseSelection @selection)
                    $state.Releases=@($selected|ForEach-Object {[ordered]@{Module=$_.Module;Component=$_.Component;Version=$_.Version;Tag=$_.Tag}})
                    $state.Provisional=$false
                    if(!@($selected|Where-Object VersionChanged).Count){
                        # The delivery branch already carries these versions: tag its observed tip without a pull request.
                        foreach($skipped in @('Commit','Push','PullRequest','Merge')){$state.Phases[$skipped]='Skipped'}
                        $state.CommitRevision=$state.BaseRevision;$state.MergeCommit=$state.BaseRevision
                        Write-QuietReleaseFlowState $state
                        break
                    }
                    $state.Phases.Commit='Pending';Write-QuietReleaseFlowState $state
                    $flight.Active=$true
                    $options=$releaseOptions.Clone();$options.CommitCommand=$CommitCommand;if($request.Message){$options.Message=[string]$request.Message}
                    $result=Invoke-QuietModuleRelease @options -WarningAction SilentlyContinue -WhatIf:$false -Confirm:$false
                    $flight.Active=$false
                    if($result.Mode -cne 'Commit' -or !$result.Committed -or !(& $sequence @($result.Releases.Tag) @($state.Releases|ForEach-Object {$_.Tag}))){throw 'ReleaseVersionsDivergedSinceCommit: the committed selection differs from the planned one.'}
                    $state.CommitRevision=$result.Revision;$state.Phases.Commit='Confirmed';Write-QuietReleaseFlowState $state
                }
                'Push'{
                    $state.Phases.Push='Pending';Write-QuietReleaseFlowState $state
                    $flight.Active=$true
                    $null=& $PushBranchCommand $WorkspaceRoot $state.Remote $state.Branch
                    $flight.Active=$false
                    $line=(& $GitCommand @('ls-remote','--heads',$state.Remote,('refs/heads/'+$state.Branch))).Value
                    if(($line -split "`t")[0] -cne $state.CommitRevision){throw 'ReleaseBranchPushNotObserved'}
                    $state.Phases.Push='Confirmed';Write-QuietReleaseFlowState $state
                }
                'PullRequest'{
                    $existing=@(& $listPullRequests)
                    if($existing.Count -gt 1){throw 'ReleasePullRequestAmbiguous'}
                    if(!$existing.Count){
                        $rows=@($state.Releases|ForEach-Object {'| '+$_.Module+' | '+$_.Version+' | `'+$_.Tag+'` |'})
                        $title='Release '+(@($state.Releases|ForEach-Object {$_.Component+' '+$_.Version}) -join ', ')
                        $body=@('Release pull request opened by `scripts/Invoke-QuietRelease.ps1`.','','| Package | Version | Tag after merge |','|---|---|---|')+$rows+@('',
                            ('- Base: `'+$state.DeliveryBranch+'` at `'+$state.BaseRevision+'`; release commit `'+$state.CommitRevision+'`.'),
                            ('- Merge requested from the facade: '+$(if($request.Merge){'yes, with a merge commit once `'+$state.RequiredCheck+'` succeeds.'}else{'no; merge manually, the facade then tags the merge commit.'})),
                            '- Tags are created on the merge commit only, then pushed atomically; no branch other than this one is pushed.')
                        $bodyPath=[IO.Path]::Combine([IO.Path]::GetDirectoryName($state.Receipt),'pull-request.md')
                        [IO.File]::WriteAllText($bodyPath,($body -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
                        $state.Phases.PullRequest='Pending';Write-QuietReleaseFlowState $state
                        $created=[string](& $GitHubCommand (@('pr','create')+$repositoryArguments+@('--base',$state.DeliveryBranch,'--head',$state.Branch,'--title',$title,'--body-file',$bodyPath)))
                        $match=[regex]::Match($created,'/pull/([1-9][0-9]*)\s*\z')
                        if(!$match.Success){throw 'ReleasePullRequestCreationNotObserved'}
                        $state.PullRequest.Number=[int]$match.Groups[1].Value;$state.PullRequest.Url=$created.Trim()
                    }else{$state.PullRequest.Number=[int]$existing[0].number;$state.PullRequest.Url=[string]$existing[0].url}
                    $state.Phases.PullRequest='Confirmed';Write-QuietReleaseFlowState $state
                    Write-Host ('Release pull request: '+$state.PullRequest.Url)
                }
                'Merge'{
                    $deadline=[DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)
                    $reported=$null
                    while($true){
                        $view=& $viewPullRequest
                        $decision=Get-QuietReleasePullRequestDecision -View $view -CommitRevision $state.CommitRevision -RequiredCheck $state.RequiredCheck -Merge:([bool]$request.Merge)
                        $state.LastCheck=$decision.Reason
                        if($decision.Action -ceq 'Fail'){throw ($decision.Reason+': '+$state.PullRequest.Url)}
                        if($decision.Action -ceq 'Tag'){$state.MergeCommit=$decision.MergeCommit;$state.Phases.Merge='Confirmed';Write-QuietReleaseFlowState $state;break}
                        if($decision.Action -ceq 'Merge' -and $state.Phases.Merge -cne 'Pending'){
                            $state.Phases.Merge='Pending';$state.MergeRequested=$true;Write-QuietReleaseFlowState $state
                            $null=& $GitHubCommand (@('pr','merge',[string]$state.PullRequest.Number)+$repositoryArguments+@('--merge','--match-head-commit',$state.CommitRevision))
                            continue
                        }
                        if($decision.Reason -cne $reported){Write-Host ('Progress: '+$state.PullRequest.Url+' '+$decision.Reason+'; polling every '+$PollSeconds+' s until '+$deadline.ToString('u'));$reported=$decision.Reason}
                        if([DateTimeOffset]::UtcNow -ge $deadline){throw ('ReleasePullRequestTimeout: '+$decision.Reason+' after '+$TimeoutMinutes+' min')}
                        Write-QuietReleaseFlowState $state
                        Wait-QuietReleaseInterval -Seconds $PollSeconds
                    }
                }
                'Tag'{
                    $null=& $GitCommand @('fetch','--no-tags','--quiet',$state.Remote,('refs/heads/'+$state.DeliveryBranch))
                    $tip=(& $GitCommand @('rev-parse','--verify','FETCH_HEAD^{commit}')).Value
                    if((& $GitCommand @('rev-list','--max-count=1',$state.MergeCommit,('^'+$tip),'--')).HasOutput){throw ('ReleaseRevisionNotOnDeliveryBranch: '+$state.MergeCommit)}
                    & $switchTo @('--detach',$state.MergeCommit)
                    $expected=@($state.Releases|ForEach-Object {$_.Tag})
                    $local=@((& $GitCommand @('tag','--list')).Lines)
                    $remoteTags=@((& $GitCommand @('ls-remote','--tags','--refs',$state.Remote)).Lines|ForEach-Object {($_ -split "`t")[-1] -creplace '\Arefs/tags/',''})
                    # Tags created locally by an interrupted attempt are delivered as they are, after the same checks.
                    $reuse=@($expected|Where-Object {$_ -cin $local}).Count -eq $expected.Count -and !@($expected|Where-Object {$_ -cin $remoteTags}).Count
                    if(!$reuse){
                        foreach($tag in $expected){if($tag -cin $local -or $tag -cin $remoteTags){throw ('ReleaseVersionsDivergedSinceCommit: '+$tag+' was created after the release commit.')}}
                        $selection=@{WorkspaceRoot=$WorkspaceRoot;Module=@($request.Module);Version=[string]$request.Version;Preview=$request.Preview;PreviewSpecified=[bool]$request.PreviewSpecified;NextPreview=[bool]$request.NextPreview;NoCommit=$true;KnownTags=(@($local)+@($remoteTags))}
                        if(!(& $sequence @((Get-QuietModuleReleaseSelection @selection).Tag) $expected)){throw 'ReleaseVersionsDivergedSinceCommit: the merged manifests select other tags.'}
                    }
                    $state.Phases.Tag='Pending';Write-QuietReleaseFlowState $state
                    if($reuse){
                        $flight.Active=$true
                        $pushed=Push-QuietReleaseTags -Tag $expected -Remote $state.Remote -DeliveryBranch $state.DeliveryBranch -GitCommand $GitCommand -WhatIf:$false -Confirm:$false
                        $flight.Active=$false
                        if($pushed.Revision -cne $state.MergeCommit -or !$pushed.Pushed){throw 'ReleaseVersionsDivergedSinceCommit: existing local tags designate another commit.'}
                    }else{
                        $flight.Active=$true
                        $result=Invoke-QuietModuleRelease @releaseOptions -NoCommit -CommitCommand $CommitCommand -WhatIf:$false -Confirm:$false
                        $flight.Active=$false
                        if($result.Revision -cne $state.MergeCommit -or !$result.Pushed -or !(& $sequence @($result.Created) $expected)){throw 'ReleaseVersionsDivergedSinceCommit: the created tags differ from the planned ones.'}
                        $state.TagReceipt=$result.Receipt
                    }
                    $state.Tags=$expected;$state.Phases.Tag='Confirmed';Write-QuietReleaseFlowState $state
                }
                'Restore'{
                    if($state.OriginalBranch -ceq 'HEAD'){& $switchTo @('--detach',$state.OriginalRevision)}else{& $switchTo @($state.OriginalBranch)}
                    $state.Phases.Restore='Confirmed'
                }
            }
        }
        $state.Phase=$null;$state.Completed=$true
        Write-QuietReleaseFlowState $state
        Write-Host ('Summary: released '+(@($state.Tags) -join ', ')+' on '+$state.MergeCommit)
        [pscustomobject]$state
    }catch{
        if($_.Exception -isnot [Management.Automation.PipelineStoppedException]){
            $state.Failure=$_.Exception.Message
            $_.Exception.Data['ReleaseFlowReceipt']=$state.Receipt
        }
        throw
    }finally{
        # Ctrl+C skips catch but runs this block: record the stop, then restore the original branch when no Git effect is in flight.
        if(!$state.Completed){
            foreach($name in $phaseNames){if($state.Phases[$name] -ceq 'Pending'){$state.Phases[$name]='Unknown'}}
            if(!$state.Failure){$state.Interrupted=$true}
            Write-QuietReleaseFlowState $state
            $restored=$false
            if((!$flight.Active -or $state.Failure) -and $state.OriginalBranch){
                try{
                    if(!(& $GitCommand @('status','--porcelain=v1','--untracked-files=normal')).HasOutput -and (& $GitCommand @('rev-parse','--abbrev-ref','HEAD')).Value -cne $state.OriginalBranch){
                        $target=if($state.OriginalBranch -ceq 'HEAD'){@('--detach',$state.OriginalRevision)}else{@($state.OriginalBranch)}
                        $null=& $GitCommand (@('switch')+$target)
                    }
                    $restored=$true
                }catch{$restored=$false}
            }
            $reason=if($state.Interrupted){'interrupted'}else{'stopped: '+$state.Failure}
            Write-Host ('Release flow '+$reason+' during phase '+$state.Phase+'; original branch restored='+$restored+'. Resume with: ./scripts/Invoke-QuietRelease.ps1 -Resume '''+$state.Receipt+'''')
        }
    }
}

Export-ModuleMember -Function Get-QuietReleaseCheckState,Get-QuietReleasePullRequestDecision,Wait-QuietReleaseInterval,Write-QuietReleaseFlowState,Read-QuietReleaseFlowState,Get-QuietReleaseFlowPhaseNames,Invoke-QuietReleaseFlow
