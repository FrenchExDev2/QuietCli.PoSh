#requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module ([IO.Path]::Combine($PSScriptRoot,'GitHubActionReferences.psm1')) -DisableNameChecking -ErrorAction Stop

function ConvertTo-QuietGitHubActionVersion {
    <#
    .SYNOPSIS
    Reads a release tag such as v4, v4.3 or 4.3.0 as a [version] with missing parts set to 0, or returns null.
    .PARAMETER Text
    Tag or comment token.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param([AllowEmptyString()][AllowNull()][string]$Text)
    $match=[regex]::Match([string]$Text,'\Av?(?<major>\d{1,9})(?:\.(?<minor>\d{1,9}))?(?:\.(?<patch>\d{1,9}))?\z')
    if(!$match.Success){return $null}
    [version]::new([int]$match.Groups['major'].Value,[int]$match.Groups['minor'].Value,[int]$match.Groups['patch'].Value)
}

function Get-QuietGitHubActionComment {
    <#
    .SYNOPSIS
    Returns the comment of a commit-pinned reference after an update: its leading version replaced by the new tag.
    .DESCRIPTION
    A comment that starts with a version token (v4, v4.3.0, optionally followed by text such as ', reviewed')
    keeps that text after the new tag. A comment without a leading version is kept after the tag, separated by
    ', '. An empty comment becomes the tag alone. The tag is what a reader needs next to a commit id.
    .PARAMETER Comment
    Current comment without '#', or null.
    .PARAMETER Tag
    New release tag.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][AllowNull()][string]$Comment,[Parameter(Mandatory)][string]$Tag)
    $current=([string]$Comment).Trim()
    if(!$current){return $Tag}
    $match=[regex]::Match($current,'\Av?\d{1,9}(?:\.\d{1,9}){0,2}(?<rest>(?![\w.]).*)\z')
    if($match.Success){return $Tag+$match.Groups['rest'].Value}
    $Tag+', '+$current
}

function Get-QuietGitHubActionCurrentVersion {
    <#
    .SYNOPSIS
    Returns the version a reference is pinned to: its Version ref, else the leading version of its comment, else null.
    .PARAMETER Reference
    Remote reference returned by ConvertFrom-QuietGitHubActionUses.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param([Parameter(Mandatory)][object]$Reference)
    if($Reference.RefKind -ceq 'Version'){return ConvertTo-QuietGitHubActionVersion -Text $Reference.Ref}
    $token=[regex]::Match(([string]$Reference.Comment).Trim(),'\Av?\d{1,9}(?:\.\d{1,9}){0,2}(?![\w.])')
    ConvertTo-QuietGitHubActionVersion -Text $token.Value
}

function Get-QuietGitHubActionUpdate {
    <#
    .SYNOPSIS
    Decides how one Remote reference follows the latest release, without reading or writing anything.
    .DESCRIPTION
    Returns {Reference, Release, Status, Reason, Ref, Comment, NewLine}. Status is:
    - Update: NewLine differs from the current line. A Sha ref moves to the release commit and its comment to
      the release tag (Get-QuietGitHubActionComment); a Version ref moves to the release tag and keeps its comment.
    - UpToDate: the rendered line is already the current line.
    - Skipped, with Reason NoRelease (the repository publishes no release), NotReleasePinned (a branch or other
      ref, which is left to its owner) or NewerThanLatest (the pinned version is above the latest release, for
      example a prerelease; never downgraded).
    .PARAMETER Reference
    Remote reference returned by ConvertFrom-QuietGitHubActionUses.
    .PARAMETER Release
    Release object of its action (Get-QuietGitHubActionLatestRelease or the catalog).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Reference,[Parameter(Mandatory)][object]$Release)
    if($Reference.Kind -cne 'Remote'){throw ('GitHubActionReferenceInvalid: '+$Reference.Kind+' references have no release')}
    if($Release.Action -cne $Reference.Action){throw ('GitHubActionReleaseMismatch: '+$Release.Action+' for '+$Reference.Action)}
    $skip={param($reason)[pscustomobject]@{Reference=$Reference;Release=$Release;Status='Skipped';Reason=$reason;Ref=$Reference.Ref;Comment=$Reference.Comment;NewLine=$Reference.Line}}
    if($Release.Status -ceq 'NoRelease'){return & $skip 'NoRelease'}
    if($Reference.RefKind -ceq 'Other'){return & $skip 'NotReleasePinned'}
    $current=Get-QuietGitHubActionCurrentVersion -Reference $Reference
    $latest=ConvertTo-QuietGitHubActionVersion -Text $Release.Tag
    if($null -ne $current -and $null -ne $latest -and $current -gt $latest){return & $skip 'NewerThanLatest'}
    if($Reference.RefKind -ceq 'Sha'){
        $ref=$Release.Sha
        $comment=Get-QuietGitHubActionComment -Comment $Reference.Comment -Tag $Release.Tag
    }else{
        $ref=$Release.Tag
        $comment=$Reference.Comment
    }
    $line=Format-QuietGitHubActionUses -Reference $Reference -Ref $ref -Comment $comment
    $status=if($line -ceq $Reference.Line){'UpToDate'}else{'Update'}
    [pscustomobject]@{Reference=$Reference;Release=$Release;Status=$status;Reason=$null;Ref=$ref;Comment=$comment;NewLine=$line}
}

function Get-QuietGitHubActionWorkflowDocumentPath {
    <#
    .SYNOPSIS
    Returns the reviewed documentation path of a workflow file (docs/ci/github/script-<basename>.md), or null for any other file.
    .DESCRIPTION
    Mirrors the RAC-WF-001 convention that Sync-GitHubWorkflowsReadme.ps1 checks. Composite actions under
    .github/actions have no such document.
    .PARAMETER RelativePath
    File path relative to the checkout, with '/'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$RelativePath)
    $match=[regex]::Match($RelativePath,'\A\.github/workflows/(?<name>[^/]+)\.(?:yml|yaml)\z')
    if(!$match.Success){return $null}
    'docs/ci/github/script-'+$match.Groups['name'].Value+'.md'
}

function Get-QuietGitHubActionReceiptText {
    <#
    .SYNOPSIS
    Moves a workflow document's source receipt from the previous file hash to the new one, only when it was current.
    .DESCRIPTION
    A pin-only edit leaves the documented behavior unchanged, so the review recorded by a current receipt still
    holds. A receipt that is missing, duplicated or not equal to PreviousSha256 throws GitHubActionReceiptNotCurrent:
    that document needs a human review, which this function never replaces.
    .PARAMETER Text
    Document text.
    .PARAMETER PreviousSha256
    Uppercase SHA-256 of the workflow before the edit.
    .PARAMETER NewSha256
    Uppercase SHA-256 of the workflow after the edit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,[Parameter(Mandatory)][string]$PreviousSha256,[Parameter(Mandatory)][string]$NewSha256)
    # Case-sensitive on purpose: Sync-GitHubWorkflowsReadme.ps1 only accepts uppercase receipts.
    foreach($hash in @($PreviousSha256,$NewSha256)){if($hash -cnotmatch '\A[A-F0-9]{64}\z'){throw ('GitHubActionReceiptHashInvalid: '+$hash)}}
    $pattern='(?m)^<!-- workflow-source-sha256: (?<hash>[A-F0-9]{64}) -->\r?$'
    $receipts=[regex]::Matches($Text,$pattern)
    if($receipts.Count -ne 1 -or $receipts[0].Groups['hash'].Value -cne $PreviousSha256){throw 'GitHubActionReceiptNotCurrent'}
    $group=$receipts[0].Groups['hash']
    $Text.Substring(0,$group.Index)+$NewSha256+$Text.Substring($group.Index+$group.Length)
}

Export-ModuleMember -Function 'ConvertTo-QuietGitHubActionVersion','Get-QuietGitHubActionComment','Get-QuietGitHubActionCurrentVersion','Get-QuietGitHubActionUpdate','Get-QuietGitHubActionWorkflowDocumentPath','Get-QuietGitHubActionReceiptText'
