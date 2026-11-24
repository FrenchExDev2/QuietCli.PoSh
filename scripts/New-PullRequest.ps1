#requires -Version 7.6
<#
.SYNOPSIS
Creates a workspace pull request with the standard CI checklist and optional Markdown footer.
.PARAMETER Title
GitHub pull request title.
.PARAMETER BodyFile
UTF-8 Markdown file containing the description.
.PARAMETER FooterFile
Optional UTF-8 Markdown file appended below the checklist.
.PARAMETER CiOption
Explicit checkbox identifiers from the workspace pull request template.
.PARAMETER PreviewBody
Returns the composed body without contacting GitHub.
.PARAMETER WorkspaceRoot
Checkout containing the selected remote.
.PARAMETER Remote
GitHub remote; defaults to origin.
.PARAMETER Head
Source branch; defaults to the checked-out local branch. Push it before creating a pull request.
.PARAMETER Base
Target branch; defaults to develop.
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High',DefaultParameterSetName='Create')]
param(
    [Parameter(Mandatory,ParameterSetName='Create')][ValidateNotNullOrWhiteSpace()][string]$Title,
    [Parameter(Mandatory)][ValidateNotNullOrWhiteSpace()][string]$BodyFile,
    [ValidateNotNullOrWhiteSpace()][string]$FooterFile,
    [AllowEmptyCollection()][string[]]$CiOption,
    [Parameter(Mandatory,ParameterSetName='Preview')][switch]$PreviewBody,
    [Parameter(ParameterSetName='Create')][string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [Parameter(ParameterSetName='Create')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
    [Parameter(ParameterSetName='Create')][string]$Head,
    [Parameter(ParameterSetName='Create')][string]$Base='develop'
)
if(!$PreviewBody -and !$PSCmdlet.ShouldProcess("$Remote -> $Base",'Create the GitHub pull request')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PullRequestChecklist.psm1')) -DisableNameChecking -ErrorAction Stop
$encoding=[Text.UTF8Encoding]::new($false,$true)
$sourceRoot=Split-Path $PSScriptRoot -Parent
$parts=@{
    Body=[IO.File]::ReadAllText([IO.Path]::GetFullPath($BodyFile,$PWD.ProviderPath),$encoding)
    Template=[IO.File]::ReadAllText([IO.Path]::Combine($sourceRoot,'.github/pull_request_template.md'),$encoding)
}
if([IO.File]::Exists([IO.Path]::Combine($sourceRoot,'build/companions.yaml'))){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking -ErrorAction Stop
    $parts.Template=Expand-QuietPullRequestTemplate -Template $parts.Template -Configuration (Read-QuietCiCompanions $sourceRoot)
}
if($FooterFile){$parts.Footer=[IO.File]::ReadAllText([IO.Path]::GetFullPath($FooterFile,$PWD.ProviderPath),$encoding)}
if($PSBoundParameters.ContainsKey('CiOption')){$parts.CiOption=$CiOption}
$description=New-QuietPullRequestBody @parts
if($PreviewBody){$description;return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PullRequestUpdates.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/MergedBranches.psm1')) -DisableNameChecking -ErrorAction Stop
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.ProviderPath)
$repository=Get-QuietMergedBranchRepository (Invoke-QuietPullRequestTool $WorkspaceRoot git @('remote','get-url',$Remote))
$pushRepository=Get-QuietMergedBranchRepository (Invoke-QuietPullRequestTool $WorkspaceRoot git @('remote','get-url','--push',$Remote))
if(!$repository -or $repository -cne $pushRepository){throw 'PullRequestRemoteMismatch'}
if(!$Head){$Head=Invoke-QuietPullRequestTool $WorkspaceRoot git @('branch','--show-current')}
if(!$Head -or $Head -ceq $Base){throw 'PullRequestSourceBranchInvalid'}
$null=Invoke-QuietPullRequestTool $WorkspaceRoot git @('check-ref-format',"refs/heads/$Head")
$null=Invoke-QuietPullRequestTool $WorkspaceRoot git @('check-ref-format',"refs/heads/$Base")
$remoteRef=Invoke-QuietPullRequestTool $WorkspaceRoot git @('ls-remote','--exit-code','--heads',$Remote,"refs/heads/$Head")
if($remoteRef -cnotmatch ('\A[a-f0-9]{40}\t'+[regex]::Escape("refs/heads/$Head")+'\z')){throw 'PullRequestSourceBranchNotPushed'}
$existing=@(Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','list','--repo',$repository,'--head',$Head,'--base',$Base,'--state','open','--limit','100','--json','url,headRefName,baseRefName,isCrossRepository') |
    ConvertFrom-Json | Where-Object {$_.headRefName -ceq $Head -and $_.baseRefName -ceq $Base -and $_.isCrossRepository -eq $false})
if($existing.Count -gt 1){throw 'PullRequestCreateAmbiguous'}
if($existing.Count -eq 1){$existing[0].url;return}
$revision=$remoteRef.Substring(0,40)
$description=New-QuietPullRequestBody @parts -GuideUrl "https://github.com/$repository/blob/$revision/docs/README-pull-request-ci.md"
$temporary=[IO.Path]::GetTempFileName()
try{
    [IO.File]::WriteAllText($temporary,$description,$encoding)
    $url=Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','create','--repo',$repository,'--title',$Title,'--head',$Head,'--base',$Base,'--body-file',$temporary)
    if($url -notmatch ('\A'+[regex]::Escape("https://github.com/$repository/pull/")+'[1-9][0-9]*\z')){throw 'PullRequestCreationNotObserved'}
    $url
}finally{[IO.File]::Delete($temporary)}
