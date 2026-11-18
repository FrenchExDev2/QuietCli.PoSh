#requires -Version 7.6
# Deletes the local branches whose pull request GitHub merged into the base branch, keeping every unmerged commit.
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Ci.Process.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkBranch.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'MergedBranches.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietScriptRemoveQuietMergedBranches {
    <#
    .SYNOPSIS
    Deletes the local branches whose pull request was merged into develop on GitHub, and lists the branches it keeps.
    .DESCRIPTION
    Reads the local branches with git for-each-ref and the merged pull requests with gh pr list (or a saved copy of
    that JSON), then applies Get-QuietMergedBranchDecision to each branch. A branch is deleted only when its latest
    merged pull request contains its tip, so squash merges are recognized and unpushed commits are never lost.
    Each deletion is a compare-and-delete of the observed tip (git update-ref -d), followed by the removal of the
    branch's config section. Remote branches, tags, stashes and the working tree are never touched.
    The base, the protected names, the limit and the repository are validated before anything runs, including under
    WhatIf, which then returns before any Git or GitHub call. PlanOnly reads everything and deletes nothing.
    .PARAMETER WorkspaceRoot
    Checkout whose local branches are cleaned.
    .PARAMETER BaseBranch
    Branch the pull requests were merged into, develop by default; never deleted.
    .PARAMETER Remote
    Configured remote whose github.com URL names the repository; <Remote>/<BaseBranch> tells which branches are already in the base.
    .PARAMETER Repository
    Expected GitHub owner/repository; the remote must point to it. Defaults to the remote's own repository.
    .PARAMETER PullRequestsPath
    JSON file saved from gh pr list --state merged --json number,headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository,
    read instead of calling gh. The remote is then not checked.
    .PARAMETER Limit
    Maximum number of merged pull requests requested from gh, 1000 by default.
    .PARAMETER Protected
    Other branch names that are never deleted, develop, main and master by default.
    .PARAMETER IncludeContainedInBase
    Also deletes branches without a merged pull request whose tip is already in <Remote>/<BaseBranch>.
    .PARAMETER PlanOnly
    Returns the decisions without deleting anything.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$WorkspaceRoot=([IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..'))),
        [string]$BaseBranch='develop',
        [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',
        [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
        [string]$PullRequestsPath,
        [ValidateRange(1,10000)][int]$Limit=1000,
        [AllowEmptyCollection()][string[]]$Protected=@('develop','main','master'),
        [switch]$IncludeContainedInBase,
        [switch]$PlanOnly
    )
    $ErrorActionPreference='Stop'
    Assert-QuietWorkBranchBase -BaseBranch $BaseBranch
    foreach($name in $Protected){if([string]::IsNullOrWhiteSpace($name)){throw 'MergedBranchProtectedInvalid: empty name'}}
    $WorkspaceRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path))
    if($PullRequestsPath){$PullRequestsPath=[IO.Path]::GetFullPath($PullRequestsPath,$PWD.Path)}
    $operation=if($PlanOnly){"Plan the deletion of local branches merged into $BaseBranch"}else{"Delete local branches merged into $BaseBranch"}
    if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,$operation)){return}

    function Invoke-QuietMergedBranchTool {
        <#
        .SYNOPSIS
        Runs one exact Git or GitHub CLI command and returns {ExitCode, Text}; throws when the exit code is not allowed.
        .PARAMETER FilePath
        git or gh.
        .PARAMETER ArgumentList
        Exact native argument vector; no shell evaluation.
        .PARAMETER AllowedExitCodes
        Exit codes that carry an answer rather than a failure.
        #>
        param([ValidateSet('git','gh')][string]$FilePath,[string[]]$ArgumentList,[int[]]$AllowedExitCodes=@(0))
        $state=@{Text=[Text.StringBuilder]::new();Overflow=$false}
        $result=Invoke-CiProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 120 -State $state -OnOutput {
            param($record,$state)
            if($record.Stream -ne 'stdout'){return}
            if($state.Text.Length+$record.Text.Length -gt 8388608){$state.Overflow=$true;return}
            [void]$state.Text.Append($record.Text).Append("`n")
        }
        if($state.Overflow){throw ('MergedBranchMetadataTooLarge: '+$FilePath+' '+$ArgumentList[0])}
        if($result.Outcome -eq 'Timeout' -or $AllowedExitCodes -notcontains $result.ExitCode){throw ('MergedBranchToolFailed: '+$FilePath+' '+($ArgumentList[0..([Math]::Min(1,$ArgumentList.Count-1))] -join ' ')+' exited '+$result.ExitCode)}
        # Only line ends are trimmed: the last for-each-ref line ends with a tab when its worktree path is empty.
        [pscustomobject]@{ExitCode=$result.ExitCode;Text=$state.Text.ToString().TrimEnd("`n")}
    }

    $root=(Invoke-QuietMergedBranchTool git @('rev-parse','--show-toplevel')).Text
    if(![StringComparer]::OrdinalIgnoreCase.Equals($WorkspaceRoot,[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($root)))){throw ('MergedBranchCheckoutMismatch: '+$WorkspaceRoot+' is inside '+$root)}
    if($PullRequestsPath){
        if(!(Test-Path -LiteralPath $PullRequestsPath -PathType Leaf)){throw ('MergedBranchPullRequestsMissing: '+$PullRequestsPath)}
        $json=[IO.File]::ReadAllText($PullRequestsPath,[Text.Encoding]::UTF8)
        $source=$PullRequestsPath
    }else{
        $observed=Get-QuietMergedBranchRepository -RemoteUrl (Invoke-QuietMergedBranchTool git @('remote','get-url',$Remote)).Text
        if(!$observed){throw ('MergedBranchRemoteNotGitHub: '+$Remote)}
        if($Repository -and $observed -ine $Repository){throw ('MergedBranchRemoteMismatch: '+$Remote+' is '+$observed+', not '+$Repository)}
        $Repository=$observed
        $json=(Invoke-QuietMergedBranchTool gh @('pr','list','--repo',$Repository,'--state','merged','--base',$BaseBranch,'--limit',[string]$Limit,'--json','number,headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository')).Text
        $source='gh pr list --repo '+$Repository
    }
    $pullRequests=ConvertFrom-QuietMergedBranchPullRequests -Json $json -BaseBranch $BaseBranch
    $listed=@(ConvertFrom-Json -InputObject $json -NoEnumerate).Count
    if(!$PullRequestsPath -and $listed -ge $Limit){Write-Warning ("MergedBranchLimitReached: $listed merged pull requests listed; older ones are ignored, raise -Limit to see them.")}
    $baseRef='refs/remotes/'+$Remote+'/'+$BaseBranch
    # Without IncludeContainedInBase the base only explains a kept branch (ContainedInBaseOnly), so it may be missing.
    $baseKnown=(Invoke-QuietMergedBranchTool git @('rev-parse','--verify','--quiet',($baseRef+'^{commit}')) -AllowedExitCodes @(0,1)).ExitCode -eq 0
    if($IncludeContainedInBase -and !$baseKnown){throw ('MergedBranchBaseMissing: '+$baseRef)}
    $branches=@(ConvertFrom-QuietMergedBranchRefs -Text (Invoke-QuietMergedBranchTool git @('for-each-ref','--format=%(refname)%09%(objectname)%09%(worktreepath)','refs/heads/')).Text)

    $decisions=foreach($branch in $branches){
        $pullRequest=$null
        $relation='Unknown'
        $contained=$false
        $guarded=$branch.WorktreePath -or ((@($BaseBranch)+@($Protected)) -contains $branch.Name)
        if(!$guarded -and $pullRequests.TryGetValue($branch.Name,[ref]$pullRequest)){
            $exit=if($branch.Tip -ceq $pullRequest.HeadRefOid){0}else{(Invoke-QuietMergedBranchTool git @('merge-base','--is-ancestor',$branch.Tip,$pullRequest.HeadRefOid) -AllowedExitCodes @(0,1,128)).ExitCode}
            $relation=ConvertTo-QuietMergedBranchRelation -Tip $branch.Tip -Head $pullRequest.HeadRefOid -AncestorExitCode $exit
        }elseif(!$guarded -and $baseKnown){
            $contained=(Invoke-QuietMergedBranchTool git @('merge-base','--is-ancestor',$branch.Tip,$baseRef) -AllowedExitCodes @(0,1)).ExitCode -eq 0
        }
        Get-QuietMergedBranchDecision -Branch $branch -BaseBranch $BaseBranch -Protected $Protected -PullRequest $pullRequest -Relation $relation -ContainedInBase:$contained -IncludeContainedInBase:$IncludeContainedInBase
    }
    $decisions=@($decisions)
    $doomed=@($decisions|Where-Object Action -eq 'Delete')
    if(!$PlanOnly -and $doomed.Count){
        $config=Invoke-QuietMergedBranchTool git @('config','--local','--name-only','--get-regexp','^branch\.') -AllowedExitCodes @(0,1)
        $configured=Get-QuietMergedBranchConfigSections -Text $config.Text
        foreach($decision in $doomed){
            # Compare-and-delete: a branch that moved since it was read is refused, never lost.
            $null=Invoke-QuietMergedBranchTool git @('update-ref','-m','Remove-QuietMergedBranches','-d',('refs/heads/'+$decision.Branch),$decision.Tip)
            if($configured -ccontains $decision.Branch){$null=Invoke-QuietMergedBranchTool git @('config','--local','--remove-section',('branch.'+$decision.Branch))}
            $why=if($decision.PullRequest){'PR #'+$decision.PullRequest}else{'in '+$baseRef}
            Write-Host ('Deleted '+$decision.Branch+' (was '+$decision.Tip.Substring(0,12)+', '+$why+'); restore with git branch '+$decision.Branch+' '+$decision.Tip)
        }
    }
    $state=if($PlanOnly){'Planned'}else{'Deleted'}
    foreach($decision in $decisions){
        $decision|Add-Member -NotePropertyName State -NotePropertyValue $(if($decision.Action -eq 'Delete'){$state}else{'Kept'})
    }
    [pscustomobject]@{
        BaseBranch=$BaseBranch
        Repository=$Repository
        Source=$source
        PlanOnly=[bool]$PlanOnly
        MergedPullRequests=$pullRequests.Count
        Deleted=@(if(!$PlanOnly){$doomed|ForEach-Object Branch})
        Planned=@(if($PlanOnly){$doomed|ForEach-Object Branch})
        Kept=@($decisions|Where-Object Action -eq 'Keep'|ForEach-Object Branch)
        Branches=$decisions
    }
}

Export-ModuleMember -Function 'Invoke-QuietScriptRemoveQuietMergedBranches'
