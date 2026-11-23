#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PullRequestChecklist.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'PullRequestUpdates.psm1')) -DisableNameChecking -ErrorAction Stop

function Read-QuietPullRequestCiSnapshot {
    <#
    .SYNOPSIS
    Reads the CI-relevant state of an open GitHub pull request.
    .PARAMETER WorkspaceRoot
    Directory used to run GitHub CLI.
    .PARAMETER Repository
    GitHub owner and repository.
    .PARAMETER Number
    Pull request number.
    .PARAMETER GitHubCommand
    Optional exact-argument GitHub CLI adapter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[\w.-]+/[\w.-]+\z')][string]$Repository,
        [Parameter(Mandatory)][ValidateRange(1,[int]::MaxValue)][int]$Number,
        [scriptblock]$GitHubCommand
    )
    $projection='{number,state,draft,body,merge_commit_sha,head:{sha:.head.sha,ref:.head.ref},base:{sha:.base.sha,ref:.base.ref}}'
    $arguments=@('api',"repos/$Repository/pulls/$Number",'--jq',$projection)
    $json=if($GitHubCommand){& $GitHubCommand $arguments}else{Invoke-QuietPullRequestTool $WorkspaceRoot gh $arguments}
    $item=$json | ConvertFrom-Json -AsHashtable
    if($item.number -ne $Number -or $item.state -cne 'open' -or !$item.Contains('body') -or
        $item.head.sha -cnotmatch '\A[a-f0-9]{40}\z' -or $item.base.sha -cnotmatch '\A[a-f0-9]{40}\z' -or
        $item.merge_commit_sha -cnotmatch '\A[a-f0-9]{40}\z'){
        throw 'PullRequestCiSnapshotUnavailable'
    }
    $item
}

function Test-QuietPullRequestCiSelection {
    <#
    .SYNOPSIS
    Compares a current pull request snapshot to an exact CI identity and canonical selection.
    .PARAMETER Snapshot
    Open pull request snapshot.
    .PARAMETER Evidence
    Selection evidence from planning or from the CI receipt.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Snapshot,[Parameter(Mandatory)][Collections.IDictionary]$Evidence)

    $current=Read-QuietPullRequestChecklist $Snapshot.body
    $expected=ConvertTo-Json -InputObject $current.Selected -Compress
    $observed=ConvertTo-Json -InputObject $Evidence.Options -Compress
    $Evidence.Number -eq $Snapshot.number -and $Evidence.Head -ceq $Snapshot.head.sha -and
        $Evidence.Base -ceq $Snapshot.base.sha -and $Evidence.Revision -ceq $Snapshot.merge_commit_sha -and
        $expected -ceq $observed
}

function Assert-QuietPullRequestCiEvidence {
    <#
    .SYNOPSIS
    Requires fresh CI evidence from the latest associated workflow run before merging.
    .PARAMETER WorkspaceRoot
    Directory used to run GitHub CLI.
    .PARAMETER Repository
    GitHub owner and repository.
    .PARAMETER Number
    Pull request number.
    .PARAMETER ExpectedHead
    Source SHA to be passed to the merge operation.
    .PARAMETER CheckRollup
    Current PR check rollup used to associate runs with missing PR metadata.
    .PARAMETER GitHubCommand
    Optional exact-argument GitHub CLI adapter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][string]$ExpectedHead,
        [AllowEmptyCollection()][object[]]$CheckRollup,
        [scriptblock]$GitHubCommand
    )

    if(!$GitHubCommand){$GitHubCommand={param($arguments) Invoke-QuietPullRequestTool $WorkspaceRoot gh $arguments}}
    $snapshot=Read-QuietPullRequestCiSnapshot $WorkspaceRoot $Repository $Number -GitHubCommand $GitHubCommand
    if($snapshot.head.sha -cne $ExpectedHead -or $snapshot.draft -ne $false){throw 'PullRequestCiCheckpointChanged'}
    $projection='.workflow_runs | map({id,head_sha,head_branch,event,status,conclusion,run_attempt,pulls:[.pull_requests[].number]})'
    $runs=(& $GitHubCommand @('api','--method','GET',"repos/$Repository/actions/workflows/companions-ci.yml/runs",'-f','event=pull_request','-f',"head_sha=$ExpectedHead",'-f','per_page=30','--jq',$projection)) | ConvertFrom-Json
    $run=$runs | Where-Object {
        $_.id -gt 0 -and $_.head_sha -ceq $ExpectedHead -and $_.head_branch -ceq $snapshot.head.ref -and $_.event -ceq 'pull_request'
    } | Where-Object {
        if($_.pulls.Count){
            $Number -in $_.pulls
        }else{
            $link='\A'+[regex]::Escape("https://github.com/$Repository/actions/runs/$($_.id)")+'(?:/|\z)'
            @($CheckRollup | Where-Object {$_.detailsUrl -cmatch $link}).Count -gt 0
        }
    } | Sort-Object id -Descending | Select-Object -First 1
    if(!$run -or $run.status -cne 'completed' -or $run.conclusion -cne 'success' -or $run.run_attempt -le 0){throw 'PullRequestCiLatestRunNotSuccessful'}

    $directory=[IO.Directory]::CreateTempSubdirectory().FullName
    try{
        $null=& $GitHubCommand @('run','download',[string]$run.id,'--repo',$Repository,'--name',"quietcli-ci-plan-results-attempt-$($run.run_attempt)",'--dir',$directory)
        $path=[IO.Path]::Combine($directory,'receipt.json')
        $file=Get-Item -LiteralPath $path -ErrorAction Stop
        if($file.PSIsContainer -or $file.Length -gt 1MB -or $file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'PullRequestCiReceiptInvalid'}
        $receipt=Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        if(!$receipt.PullRequest -or $receipt.Result.Ready -ne $true -or [string]$receipt.RunId -cne [string]$run.id -or
            [string]$receipt.RunAttempt -cne [string]$run.run_attempt -or $receipt.Revision -cne $receipt.PullRequest.Revision -or
            !(Test-QuietPullRequestCiSelection $snapshot $receipt.PullRequest)){
            throw 'PullRequestCiReceiptStale'
        }
    }finally{
        [IO.Directory]::Delete($directory,$true)
    }
    $current=Read-QuietPullRequestCiSnapshot $WorkspaceRoot $Repository $Number -GitHubCommand $GitHubCommand
    if($current.draft -ne $false -or !(Test-QuietPullRequestCiSelection $current $receipt.PullRequest)){throw 'PullRequestCiCheckpointChanged'}
}

Export-ModuleMember -Function Read-QuietPullRequestCiSnapshot,Test-QuietPullRequestCiSelection,Assert-QuietPullRequestCiEvidence
