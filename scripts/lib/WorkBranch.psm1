#Objective: Work branch policy: kinds, names, base, repository state, remote heads and shelf comparison, without effects.
#requires -Version 7.6

function Resolve-QuietWorkBranchName {
    <#
    .SYNOPSIS
    Validates a work branch given whole (feature/x) or as a kind and a name, and returns its branch, kind and name.
    .DESCRIPTION
    The kind is one of Get-QuietWorkBranchKinds, compared case-sensitively. The name has at most 100 characters
    and one or more segments separated by '/'. Each segment starts and ends with a letter or a digit, may contain
    '.', '_' and '-', never contains '..' and never ends with '.lock'. These rules are a subset of
    git check-ref-format, which the caller still runs. Invalid input throws WorkBranchKindInvalid or WorkBranchNameInvalid.
    .PARAMETER Branch
    Whole branch name, for example feature/script-tests.
    .PARAMETER Kind
    Branch kind, for example feature.
    .PARAMETER Name
    Branch name after the kind, for example script-tests.
    #>
    [CmdletBinding(DefaultParameterSetName='Branch')]
    param(
        [Parameter(Mandatory,ParameterSetName='Branch')][AllowEmptyString()][AllowNull()][string]$Branch,
        [Parameter(Mandatory,ParameterSetName='Kind')][AllowEmptyString()][AllowNull()][string]$Kind,
        [Parameter(Mandatory,ParameterSetName='Kind')][AllowEmptyString()][AllowNull()][string]$Name
    )
    if($PSCmdlet.ParameterSetName -eq 'Branch'){
        $separator=([string]$Branch).IndexOf('/')
        if($separator -lt 0){throw ('WorkBranchKindInvalid: '+$Branch+' has no kind/ prefix')}
        $Kind=$Branch.Substring(0,$separator)
        $Name=$Branch.Substring($separator+1)
    }
    if((Get-QuietWorkBranchKinds) -cnotcontains $Kind){throw ('WorkBranchKindInvalid: '+$Kind+'; expected one of '+((Get-QuietWorkBranchKinds) -join ', '))}
    if([string]::IsNullOrEmpty($Name)){throw 'WorkBranchNameInvalid: empty name'}
    if($Name.Length -gt 100){throw ('WorkBranchNameInvalid: longer than 100 characters')}
    foreach($segment in $Name.Split('/')){
        if($segment -cnotmatch '\A[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?\z'){throw ('WorkBranchNameInvalid: segment '''+$segment+''' must start and end with a letter or digit and contain only letters, digits, ., _ and -')}
        if($segment.Contains('..') -or $segment.EndsWith('.lock',[StringComparison]::Ordinal)){throw ('WorkBranchNameInvalid: segment '''+$segment+''' contains .. or ends with .lock')}
    }
    [pscustomobject]@{Branch=$Kind+'/'+$Name;Kind=$Kind;Name=$Name}
}

function Get-QuietWorkBranchKinds {
    <#
    .SYNOPSIS
    Returns the work branch kinds, each the first segment of a branch name: fix, feature and chore.
    .DESCRIPTION
    There is no release kind: releases are tags, and the transient release/* branches carrying version commits
    belong to Invoke-QuietRelease.ps1.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    [string[]]@('fix','feature','chore')
}

function Assert-QuietWorkBranchBase {
    <#
    .SYNOPSIS
    Rejects a base that is not a plain branch name, or is a work or release branch: work branches only start from a delivery branch.
    .PARAMETER BaseBranch
    Base branch, develop by default.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$BaseBranch)
    if([string]$BaseBranch -cnotmatch '\A[A-Za-z0-9](?:[A-Za-z0-9._/-]*[A-Za-z0-9])?\z' -or $BaseBranch.Contains('..') -or $BaseBranch.Contains('//')){throw ('WorkBranchBaseInvalid: '+$BaseBranch)}
    $kind=$BaseBranch.Split('/')[0]
    if($BaseBranch.Contains('/') -and (@(Get-QuietWorkBranchKinds)+'release') -ccontains $kind){throw ('WorkBranchBaseIsWorkBranch: '+$BaseBranch+'; start from the delivery branch, for example develop')}
}

function Get-QuietWorkBranchStatusProblems {
    <#
    .SYNOPSIS
    Lists why a repository status forbids starting a branch: Unavailable, Detached, Unborn, Conflicted or Operation:<kind>.
    .DESCRIPTION
    Takes the Data of quiet git status. An empty result means the checkout can be shelved and switched.
    Each in-progress operation is named by its Kind (a hashtable key or a property), or by its text.
    Pending changes are not a problem: they are shelved and restored on the new branch.
    .PARAMETER Status
    Status data with Detached, Unborn, Counts.Conflicted and Operations.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowNull()][Collections.IDictionary]$Status)
    if($null -eq $Status){return [string[]]@('Unavailable')}
    $problems=[Collections.Generic.List[string]]::new()
    if($Status['Detached']){$problems.Add('Detached')}
    if($Status['Unborn']){$problems.Add('Unborn')}
    $counts=$Status['Counts']
    if($counts -is [Collections.IDictionary] -and [long]$counts['Conflicted'] -gt 0){$problems.Add('Conflicted')}
    foreach($operation in @($Status['Operations'])){
        if($null -eq $operation){continue}
        # The Git companion reports each operation as a hashtable whose Kind is Merge, Am, Rebase, CherryPick, ...
        $label=if($operation -is [Collections.IDictionary]){[string]$operation['Kind']}elseif($operation.PSObject.Properties['Kind']){[string]$operation.Kind}else{[string]$operation}
        $problems.Add('Operation:'+$label)
    }
    [string[]]$problems
}

function ConvertFrom-QuietWorkBranchLsRemote {
    <#
    .SYNOPSIS
    Parses git ls-remote output into an ordinal dictionary from ref name to object id.
    .DESCRIPTION
    Each non-empty line is '<oid>TAB<ref>', with a 40- or 64-character lowercase hexadecimal oid. Any other line,
    or a ref listed twice with different ids, throws WorkBranchRemoteOutputInvalid.
    .PARAMETER Text
    Raw ls-remote standard output.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $heads=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach($line in ([string]$Text).Split("`n")){
        $line=$line.TrimEnd("`r")
        if($line.Length -eq 0){continue}
        if($line -cnotmatch '\A(?<oid>[0-9a-f]{40}(?:[0-9a-f]{24})?)\t(?<ref>refs/\S+)\z'){throw ('WorkBranchRemoteOutputInvalid: '+$line)}
        $previous=$null
        if($heads.TryGetValue($Matches.ref,[ref]$previous) -and $previous -cne $Matches.oid){throw ('WorkBranchRemoteOutputInvalid: '+$Matches.ref+' listed twice')}
        $heads[$Matches.ref]=$Matches.oid
    }
    ,$heads
}

function Compare-QuietWorkBranchShelf {
    <#
    .SYNOPSIS
    Returns the shelved paths whose status or content differ after the shelf is restored, sorted ordinally.
    .DESCRIPTION
    Before and After hold one {Path, Status, Hash} per pending path. A path is reported when it is missing from
    After, listed more than once, or has another status or hash. Paths only in After are not reported:
    the new branch can only add committed history, never pending changes.
    .PARAMETER Before
    Pending paths captured before shelving.
    .PARAMETER After
    Pending paths observed after restoring the shelf.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([AllowEmptyCollection()][object[]]$Before=@(),[AllowEmptyCollection()][object[]]$After=@())
    $observed=[Collections.Generic.Dictionary[string,Collections.Generic.List[object]]]::new([StringComparer]::Ordinal)
    foreach($entry in $After){
        $path=[string]$entry.Path
        if(!$observed.ContainsKey($path)){$observed[$path]=[Collections.Generic.List[object]]::new()}
        $observed[$path].Add($entry)
    }
    $changed=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach($entry in $Before){
        $path=[string]$entry.Path
        $matching=$null
        if(!$observed.TryGetValue($path,[ref]$matching) -or $matching.Count -ne 1 -or [string]$matching[0].Status -cne [string]$entry.Status -or [string]$matching[0].Hash -cne [string]$entry.Hash){[void]$changed.Add($path)}
    }
    [string[]]@($changed)
}

Export-ModuleMember -Function Get-QuietWorkBranchKinds,Resolve-QuietWorkBranchName,Assert-QuietWorkBranchBase,Get-QuietWorkBranchStatusProblems,ConvertFrom-QuietWorkBranchLsRemote,Compare-QuietWorkBranchShelf
