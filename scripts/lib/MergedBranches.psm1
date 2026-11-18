#requires -Version 7.6
# Merged branch policy: parses Git and GitHub metadata and decides which local branches to delete, without effects.

function Get-QuietMergedBranchRepository {
    <#
    .SYNOPSIS
    Returns the owner/repository of a github.com remote URL, or $null for any other URL.
    .DESCRIPTION
    Accepts the https://github.com/, git@github.com: and ssh://git@github.com/ forms, with or without .git and
    a trailing slash. The host is compared case-insensitively, the owner and repository are returned as written.
    .PARAMETER RemoteUrl
    URL printed by git remote get-url.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][AllowNull()][string]$RemoteUrl)
    $match=[regex]::Match([string]$RemoteUrl,'\A(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?<repository>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?\z',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($match.Success){$match.Groups['repository'].Value}
}

function ConvertFrom-QuietMergedBranchRefs {
    <#
    .SYNOPSIS
    Parses git for-each-ref output into one {Name, Tip, WorktreePath} per local branch.
    .DESCRIPTION
    Each non-empty line is 'refs/heads/<name>TAB<oid>TAB<worktree path>', as printed by the format
    %(refname)%09%(objectname)%09%(worktreepath). The oid is a lowercase SHA-1 or SHA-256 id. The worktree path is
    empty unless the branch is checked out in a worktree of the repository. A CR before the LF is dropped. Any
    other line, or a branch listed twice, throws MergedBranchRefsInvalid.
    .PARAMETER Text
    Raw for-each-ref standard output.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($line in ([string]$Text).Split("`n")){
        $line=$line.TrimEnd("`r")
        if($line.Length -eq 0){continue}
        $match=[regex]::Match($line,'\Arefs/heads/(?<name>[^\t\s]+)\t(?<oid>[0-9a-f]{40}(?:[0-9a-f]{24})?)\t(?<worktree>[^\t]*)\z')
        if(!$match.Success){throw ('MergedBranchRefsInvalid: '+$line)}
        $name=$match.Groups['name'].Value
        if(!$seen.Add($name)){throw ('MergedBranchRefsInvalid: '+$name+' listed twice')}
        [pscustomobject]@{Name=$name;Tip=$match.Groups['oid'].Value;WorktreePath=$match.Groups['worktree'].Value}
    }
}

function ConvertFrom-QuietMergedBranchPullRequests {
    <#
    .SYNOPSIS
    Parses gh pr list JSON and returns an ordinal dictionary from head branch to its latest merged pull request.
    .DESCRIPTION
    The JSON is an array of objects with number, headRefName, headRefOid, baseRefName, mergedAt and
    isCrossRepository, as printed by gh pr list --json. Only pull requests merged (non-empty mergedAt) into
    BaseBranch from the repository itself (isCrossRepository false) are kept: a fork's branch of the same name is
    another branch. When a head branch was merged several times, the highest number wins. Anything that is not
    such an array, a missing or mistyped field, or a number listed twice throws MergedBranchPullRequestsInvalid.
    .PARAMETER Json
    Raw gh pr list standard output.
    .PARAMETER BaseBranch
    Branch the pull requests were merged into, develop by default.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Json,[string]$BaseBranch='develop')
    try{$items=ConvertFrom-Json -InputObject ([string]$Json) -DateKind String -NoEnumerate -ErrorAction Stop}catch{throw 'MergedBranchPullRequestsInvalid: not JSON'}
    if($items -isnot [object[]]){throw 'MergedBranchPullRequestsInvalid: expected an array'}
    $latest=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $numbers=[Collections.Generic.HashSet[long]]::new()
    foreach($item in $items){
        if($item -isnot [Management.Automation.PSCustomObject]){throw 'MergedBranchPullRequestsInvalid: expected objects'}
        $properties=$item.PSObject.Properties
        foreach($field in 'number','headRefName','headRefOid','baseRefName','mergedAt','isCrossRepository'){
            if($null -eq $properties[$field]){throw ('MergedBranchPullRequestsInvalid: missing '+$field)}
        }
        if($item.number -isnot [long] -and $item.number -isnot [int] -or $item.number -le 0){throw 'MergedBranchPullRequestsInvalid: number'}
        $number=[long]$item.number
        if(!$numbers.Add($number)){throw ('MergedBranchPullRequestsInvalid: #'+$number+' listed twice')}
        if($item.headRefName -isnot [string] -or $item.headRefName.Length -eq 0){throw ('MergedBranchPullRequestsInvalid: headRefName of #'+$number)}
        if($item.headRefOid -isnot [string] -or $item.headRefOid -cnotmatch '\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z'){throw ('MergedBranchPullRequestsInvalid: headRefOid of #'+$number)}
        if($item.baseRefName -isnot [string]){throw ('MergedBranchPullRequestsInvalid: baseRefName of #'+$number)}
        if($null -ne $item.mergedAt -and $item.mergedAt -isnot [string]){throw ('MergedBranchPullRequestsInvalid: mergedAt of #'+$number)}
        if($item.isCrossRepository -isnot [bool]){throw ('MergedBranchPullRequestsInvalid: isCrossRepository of #'+$number)}
        if([string]::IsNullOrEmpty($item.mergedAt) -or $item.baseRefName -cne $BaseBranch -or $item.isCrossRepository){continue}
        $previous=$null
        if($latest.TryGetValue($item.headRefName,[ref]$previous) -and $previous.Number -gt $number){continue}
        $latest[$item.headRefName]=[pscustomobject]@{Number=$number;HeadRefName=$item.headRefName;HeadRefOid=$item.headRefOid;MergedAt=$item.mergedAt}
    }
    ,$latest
}

function ConvertTo-QuietMergedBranchRelation {
    <#
    .SYNOPSIS
    Names how a local branch tip relates to the head its pull request was merged with: Same, Contained, Diverged or Unknown.
    .DESCRIPTION
    Same when both ids are equal, whatever the exit code. Otherwise the exit code of
    git merge-base --is-ancestor <tip> <head> decides: 0 Contained (every local commit is in the pull request),
    1 Diverged (the branch has commits the pull request never had), anything else Unknown (for example 128 when the
    head commit is not in the local repository).
    .PARAMETER Tip
    Local branch tip.
    .PARAMETER Head
    Head commit of the merged pull request.
    .PARAMETER AncestorExitCode
    Exit code of git merge-base --is-ancestor, ignored when the ids are equal.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Tip,[AllowEmptyString()][string]$Head,[int]$AncestorExitCode=-1)
    if($Tip.Length -and $Tip -ceq $Head){return 'Same'}
    switch($AncestorExitCode){0{'Contained'}1{'Diverged'}default{'Unknown'}}
}

function Get-QuietMergedBranchDecision {
    <#
    .SYNOPSIS
    Decides whether one local branch is deleted, and why: returns {Branch, Tip, Action, Reason, PullRequest}.
    .DESCRIPTION
    The first matching rule wins:
    CheckedOut (Keep): the branch is checked out in a worktree, the current one included.
    Protected (Keep): the branch is the base or one of the protected names (compared case-insensitively).
    MergedPullRequest (Delete): its latest merged pull request contains the tip (relation Same or Contained).
    AheadOfPullRequest (Keep): the branch has commits its merged pull request never had (Diverged).
    PullRequestHeadUnknown (Keep): the pull request head is not available locally (Unknown).
    ContainedInBase (Delete): no merged pull request, but the tip is in the base and IncludeContainedInBase is set.
    ContainedInBaseOnly (Keep): the same without IncludeContainedInBase; a branch just started from the base looks like this.
    NoMergedPullRequest (Keep): everything else.
    .PARAMETER Branch
    One {Name, Tip, WorktreePath} from ConvertFrom-QuietMergedBranchRefs.
    .PARAMETER BaseBranch
    Branch the pull requests were merged into, always protected.
    .PARAMETER Protected
    Other branch names that are never deleted.
    .PARAMETER PullRequest
    Latest merged pull request of the branch, or $null.
    .PARAMETER Relation
    ConvertTo-QuietMergedBranchRelation result for that pull request; ignored without one, and Unknown when omitted.
    .PARAMETER ContainedInBase
    Whether the tip is an ancestor of the base; only read when there is no merged pull request.
    .PARAMETER IncludeContainedInBase
    Also deletes branches without a merged pull request whose tip is in the base.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Branch,
        [Parameter(Mandatory)][string]$BaseBranch,
        [AllowEmptyCollection()][string[]]$Protected=@(),
        [AllowNull()][object]$PullRequest,
        # Omitted, the relation is empty and handled as Unknown: a pull request alone never deletes.
        [ValidateSet('Same','Contained','Diverged','Unknown')][string]$Relation,
        [switch]$ContainedInBase,
        [switch]$IncludeContainedInBase
    )
    $name=[string]$Branch.Name
    $decide={param($action,$reason)[pscustomobject]@{Branch=$name;Tip=[string]$Branch.Tip;Action=$action;Reason=$reason;PullRequest=${PullRequest}?.Number}}
    if(![string]::IsNullOrEmpty([string]$Branch.WorktreePath)){return & $decide 'Keep' 'CheckedOut'}
    if((@($BaseBranch)+@($Protected)) -contains $name){return & $decide 'Keep' 'Protected'}
    if($PullRequest){
        switch($Relation){
            {$_ -in 'Same','Contained'}{return & $decide 'Delete' 'MergedPullRequest'}
            'Diverged'{return & $decide 'Keep' 'AheadOfPullRequest'}
            default{return & $decide 'Keep' 'PullRequestHeadUnknown'}
        }
    }
    if($ContainedInBase){return & $decide $(if($IncludeContainedInBase){'Delete'}else{'Keep'}) $(if($IncludeContainedInBase){'ContainedInBase'}else{'ContainedInBaseOnly'})}
    & $decide 'Keep' 'NoMergedPullRequest'
}

function Get-QuietMergedBranchConfigSections {
    <#
    .SYNOPSIS
    Returns the branch names that own a branch.<name>.* key in git config --name-only --get-regexp output.
    .DESCRIPTION
    Keys are 'branch.<name>.<variable>': the section is compared case-insensitively, the name ordinally, and the
    variable is the part after the last dot. Other keys and empty lines are ignored. The result is sorted ordinally,
    without duplicates.
    .PARAMETER Text
    Raw git config --local --name-only --get-regexp '^branch\.' output.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $names=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach($line in ([string]$Text -split '\r?\n')){
        $match=[regex]::Match($line,'\Abranch\.(?<name>.+)\.[A-Za-z][A-Za-z0-9-]*\z',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if($match.Success){[void]$names.Add($match.Groups['name'].Value)}
    }
    [string[]]@($names)
}

Export-ModuleMember -Function Get-QuietMergedBranchRepository,ConvertFrom-QuietMergedBranchRefs,ConvertFrom-QuietMergedBranchPullRequests,ConvertTo-QuietMergedBranchRelation,Get-QuietMergedBranchDecision,Get-QuietMergedBranchConfigSections
