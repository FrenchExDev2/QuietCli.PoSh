#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PullRequestUpdates.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'MergedBranches.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkBranch.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ReleaseFlow.psm1')) -DisableNameChecking -ErrorAction Stop

function Get-QuietPullRequestRepository {
    <#
    .SYNOPSIS
    Identifies the GitHub repository shared by the remote's fetch and push URLs.
    .PARAMETER WorkspaceRoot
    Workspace containing the configured remote.
    .PARAMETER Remote
    Remote to resolve.
    #>
    param([string]$WorkspaceRoot,[string]$Remote)
    $fetch=Get-QuietMergedBranchRepository (Invoke-QuietPullRequestTool $WorkspaceRoot git @('remote','get-url',$Remote))
    $push=Get-QuietMergedBranchRepository (Invoke-QuietPullRequestTool $WorkspaceRoot git @('remote','get-url','--push',$Remote))
    if(!$fetch -or $fetch -ne $push){throw 'PullRequestRemoteMismatch: fetch and push must identify the same github.com repository.'}
    $fetch
}

function Read-QuietWorkspacePullRequest {
    <#
    .SYNOPSIS
    Loads and validates a same-repository workspace pull request snapshot.
    .PARAMETER WorkspaceRoot
    Checkout from which to run gh.
    .PARAMETER Repository
    Selected GitHub repository.
    .PARAMETER Number
    Pull request number.
    #>
    param([string]$WorkspaceRoot,[string]$Repository,[int]$Number)
    $view=Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','view',[string]$Number,'--repo',$Repository,'--json','number,url,headRefOid,headRefName,baseRefName,isCrossRepository,isDraft,state,mergeCommit,statusCheckRollup') | ConvertFrom-Json
    if($view.number -ne $Number -or $view.isCrossRepository -ne $false -or $view.baseRefName -cne 'develop' -or $view.headRefOid -cnotmatch '\A[a-f0-9]{40}\z'){
        throw 'PullRequestTargetInvalid: expected a same-repository pull request targeting develop.'
    }
    $null=Resolve-QuietWorkBranchName -Branch $view.headRefName
    $view
}

function Get-QuietPullRequestLocalRef {
    <#
    .SYNOPSIS
    Returns the exact local Git ref line for a pull request branch, if it exists.
    .PARAMETER WorkspaceRoot
    Checkout whose local refs to inspect.
    .PARAMETER Branch
    Source branch name.
    #>
    param([string]$WorkspaceRoot,[string]$Branch)
    $name='refs/heads/'+$Branch
    $lines=Invoke-QuietPullRequestTool $WorkspaceRoot git @('for-each-ref','--format=%(refname) %(objectname)',$name)
    $lines -split '\r?\n' | Where-Object {$_.StartsWith($name+' ',[StringComparison]::Ordinal)}
}

function Invoke-QuietMergePullRequest {
    <#
    .SYNOPSIS
    Merges an open workspace pull request after its required CI check has succeeded.
    .PARAMETER PullRequest
    Pull request number.
    .PARAMETER WorkspaceRoot
    Checkout whose GitHub remote owns the pull request.
    .PARAMETER Remote
    Configured GitHub remote.
    .PARAMETER ExpectedHead
    Exact head SHA, or the observed head if omitted.
    .PARAMETER NoRebase
    Use a merge commit.
    .PARAMETER NoBranchDelete
    Preserve the source branch.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$PullRequest,
        [string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..'))),
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
        [ValidatePattern('\A[a-f0-9]{40}\z')][string]$ExpectedHead,
        [switch]$NoRebase,
        [switch]$NoBranchDelete
    )
    $ErrorActionPreference='Stop'
    $method=if($NoRebase){'--merge'}else{'--rebase'}
    $action=if($NoBranchDelete){"Merge with $method and preserve the branch"}else{"Merge with $method and delete the source branch"}
    if(!$PSCmdlet.ShouldProcess("workspace pull request #$PullRequest via $Remote",$action)){return}
    $repository=Get-QuietPullRequestRepository -WorkspaceRoot $WorkspaceRoot -Remote $Remote
    $view=Read-QuietWorkspacePullRequest -WorkspaceRoot $WorkspaceRoot -Repository $repository -Number $PullRequest
    if($view.state -cne 'OPEN' -or $view.isDraft -ne $false){throw 'PullRequestNotReady: expected an open, non-draft pull request.'}
    if($ExpectedHead -and $view.headRefOid -cne $ExpectedHead){throw 'PullRequestCheckpointChanged'}
    if((Get-QuietReleaseCheckState -Rollup @($view.statusCheckRollup) -RequiredCheck 'QuietCli required CI') -cne 'Success'){
        throw 'PullRequestRequiredCiNotGreen: QuietCli required CI must succeed before merging.'
    }
    $head=$view.headRefOid
    $branch=$view.headRefName
    $arguments=@('pr','merge',[string]$PullRequest,'--repo',$repository,$method,'--match-head-commit',$head)
    if($NoBranchDelete){
        $policy=Invoke-QuietPullRequestTool $WorkspaceRoot gh @('api',"repos/$repository",'--jq','{delete_branch_on_merge}') | ConvertFrom-Json
        if($policy.delete_branch_on_merge -ne $false){throw 'PullRequestBranchPreservationUnavailable: GitHub automatic branch deletion must be disabled.'}
    }else{
        $local=Get-QuietPullRequestLocalRef $WorkspaceRoot $branch
        if($local -and $local -cne "refs/heads/$branch $head"){throw 'PullRequestLocalBranchChanged: local source branch no longer matches the pull request.'}
        $checkout=Invoke-QuietPullRequestTool $WorkspaceRoot git @('branch','--show-current')
        if($checkout -ceq $branch -and (Invoke-QuietPullRequestTool $WorkspaceRoot git @('status','--porcelain=v1','--untracked-files=normal'))){
            throw 'PullRequestLocalBranchDirty: commit or shelve the source checkout before deleting it.'
        }
        $arguments+='--delete-branch'
    }
    $mergeError=$null
    try{$null=Invoke-QuietPullRequestTool $WorkspaceRoot gh $arguments}catch{$mergeError=$_}
    $merged=Read-QuietWorkspacePullRequest -WorkspaceRoot $WorkspaceRoot -Repository $repository -Number $PullRequest
    if($merged.state -cne 'MERGED' -or $merged.headRefOid -cne $head){
        if($mergeError){throw $mergeError}
        throw 'PullRequestMergeNotConfirmed: GitHub did not report this revision merged.'
    }
    if($mergeError){Write-Warning "Pull request #$PullRequest merged, but gh reported an error: $($mergeError.Exception.Message)"}
    $branchDeleted=$null
    if(!$NoBranchDelete){
        $remoteRef=Invoke-QuietPullRequestTool $WorkspaceRoot git @('ls-remote','--heads',$Remote,"refs/heads/$branch")
        $branchDeleted=!$remoteRef -and !(Get-QuietPullRequestLocalRef $WorkspaceRoot $branch)
        if(!$branchDeleted){Write-Warning "Pull request #$PullRequest merged, but the source branch still exists."}
    }
    [pscustomobject]@{State='Merged';PullRequest=$PullRequest;Url=$merged.url;Head=$head;MergeCommit=$merged.mergeCommit.oid;Method=$method.Substring(2);BranchDeleted=$branchDeleted}
}

function Invoke-QuietPullRequestScript {
    <#
    .SYNOPSIS
    Runs the repository's push or watcher entry point.
    .PARAMETER Name
    Approved entry point filename.
    .PARAMETER Arguments
    Explicit parameters for the entry point.
    #>
    param([ValidateSet('Push-Workspace.ps1','Watch-GitHubRun.ps1')][string]$Name,[hashtable]$Arguments)
    & ([IO.Path]::Combine([IO.Path]::GetDirectoryName($PSScriptRoot),$Name)) @Arguments
}

function Find-QuietPullRequestRun {
    <#
    .SYNOPSIS
    Waits for the Companions workflow run belonging to the exact pull request and head.
    .PARAMETER WorkspaceRoot
    Checkout from which to run gh.
    .PARAMETER Repository
    Selected GitHub repository.
    .PARAMETER PullRequest
    Verified pull request number.
    .PARAMETER Branch
    Head branch.
    .PARAMETER Revision
    Head SHA pushed by this invocation.
    .PARAMETER DiscoverySeconds
    Bound on waiting for GitHub to register the workflow run.
    #>
    param([string]$WorkspaceRoot,[string]$Repository,[int]$PullRequest,[string]$Branch,[string]$Revision,[int]$DiscoverySeconds)
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($DiscoverySeconds)
    do{
        $result=Invoke-QuietPullRequestTool $WorkspaceRoot gh @('api','--method','GET',"repos/$Repository/actions/workflows/companions-ci.yml/runs",'-f','event=pull_request','-f',"head_sha=$Revision",'-f','per_page=20','--jq','.workflow_runs | map({id,head_sha,head_branch,event,pull_requests: [.pull_requests[].number]})')
        $runs=@($result | ConvertFrom-Json | Where-Object {$_.event -ceq 'pull_request' -and $_.head_sha -ceq $Revision -and $_.head_branch -ceq $Branch -and $_.id -gt 0} | Sort-Object id -Descending)
        if($runs.Count){
            $view=Read-QuietWorkspacePullRequest -WorkspaceRoot $WorkspaceRoot -Repository $Repository -Number $PullRequest
            if($view.state -cne 'OPEN' -or $view.headRefOid -cne $Revision -or $view.headRefName -cne $Branch){throw 'PullRequestCheckpointChanged'}
            $runPrefix='https://github.com/'+$Repository+'/actions/runs/'
            foreach($run in $runs){
                if($PullRequest -in $run.pull_requests){return [long]$run.id}
                # GitHub may omit pull_requests even for pull_request runs. The current PR's check links identify the run.
                if(@($run.pull_requests).Count -eq 0){
                    $runUrlPattern='\A'+[regex]::Escape($runPrefix+[string]$run.id)+'(?:/|\z)'
                    if(@($view.statusCheckRollup | Where-Object {$_.detailsUrl -match $runUrlPattern}).Count){return [long]$run.id}
                }
            }
        }
        if([DateTimeOffset]::UtcNow -ge $deadline){throw "PullRequestRunUnavailable: no Companions run found for PR #$PullRequest at $Revision."}
        Wait-QuietReleaseInterval -Seconds 5
    }while($true)
}

function Invoke-QuietCommitPullRequest {
    <#
    .SYNOPSIS
    Pushes a committed revision to its existing pull request, watches CI and optionally merges.
    .PARAMETER WorkspaceRoot
    Committed workspace checkout.
    .PARAMETER Revision
    Exact new Git commit to publish and watch.
    .PARAMETER MergePullRequest
    Merge after the watcher and required check succeed for this revision.
    .PARAMETER NoRebase
    Use a merge commit if merging.
    .PARAMETER NoBranchDelete
    Preserve the source branch if merging.
    .PARAMETER DiscoverySeconds
    Maximum number of seconds to wait for workflow registration.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
        [switch]$MergePullRequest,[switch]$NoRebase,[switch]$NoBranchDelete,
        [ValidateRange(0,600)][int]$DiscoverySeconds=120
    )
    $ErrorActionPreference='Stop'
    if(!$PSCmdlet.ShouldProcess($Revision,'Push and watch the existing pull request')){return}
    $branch=Invoke-QuietPullRequestTool $WorkspaceRoot git @('branch','--show-current')
    $null=Resolve-QuietWorkBranchName -Branch $branch
    $repository=Get-QuietPullRequestRepository -WorkspaceRoot $WorkspaceRoot -Remote origin
    $items=@(Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','list','--repo',$repository,'--head',$branch,'--state','open','--limit','2','--json','number') | ConvertFrom-Json)
    if($items.Count -ne 1){throw 'CommitWorkspacePullRequestUnavailable: expected one existing open pull request for this branch.'}
    $number=[int]$items[0].number
    $view=Read-QuietWorkspacePullRequest -WorkspaceRoot $WorkspaceRoot -Repository $repository -Number $number
    if($view.state -cne 'OPEN' -or $view.headRefName -cne $branch -or ($MergePullRequest -and $view.isDraft -ne $false)){throw 'CommitWorkspacePullRequestChanged'}
    Invoke-QuietPullRequestScript -Name 'Push-Workspace.ps1' -Arguments @{WorkspaceRoot=$WorkspaceRoot;Remote='origin';Branch=$branch;ExpectedHead=$Revision;Confirm=$false}
    $pushed=Read-QuietWorkspacePullRequest -WorkspaceRoot $WorkspaceRoot -Repository $repository -Number $number
    if($pushed.state -cne 'OPEN' -or $pushed.headRefName -cne $branch -or $pushed.headRefOid -cne $Revision){throw 'PullRequestCheckpointChanged'}
    $runId=Find-QuietPullRequestRun -WorkspaceRoot $WorkspaceRoot -Repository $repository -PullRequest $number -Branch $branch -Revision $Revision -DiscoverySeconds $DiscoverySeconds
    if($runId -le 0){throw 'PullRequestRunIdentityInvalid'}
    $completed=[Collections.Generic.List[object]]::new()
    Invoke-QuietPullRequestScript -Name 'Watch-GitHubRun.ps1' -Arguments @{WorkspaceRoot=$WorkspaceRoot;Repository=$repository;RunId=$runId;Confirm=$false} | ForEach-Object {
        $_
        if($_.RunId -eq $runId -and $_.State -ceq 'Success'){$completed.Add($_)}
    }
    if($completed.Count -ne 1){throw 'PullRequestWatchDidNotSucceed'}
    if($MergePullRequest){
        Invoke-QuietMergePullRequest -WorkspaceRoot $WorkspaceRoot -Remote origin -PullRequest $number -ExpectedHead $Revision -NoRebase:$NoRebase -NoBranchDelete:$NoBranchDelete -Confirm:$false
    }
}

Export-ModuleMember -Function Invoke-QuietMergePullRequest,Invoke-QuietCommitPullRequest
