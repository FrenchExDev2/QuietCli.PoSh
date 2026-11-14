#requires -Version 7.6
<#
.SYNOPSIS
Shelves pending work, fast-forwards the base branch and restores the shelf on a new work branch.
.PARAMETER Branch
New feature or fix branch; an existing branch is never reset.
.PARAMETER WorkspaceRoot
Checkout containing the pending work and configured remote.
.PARAMETER BaseBranch
Existing local branch to update using a fast-forward-only pull.
.PARAMETER Remote
Configured remote supplying the base branch, without fetching tags.
.PARAMETER ShelfName
Optional message identifying the retained Git stash.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^(fix|feature)/[A-Za-z0-9._/-]+$')][string]$Branch,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$BaseBranch='develop',
    [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Remote='origin',
    [string]$ShelfName
)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,"Shelve pending work, pull $BaseBranch and create $Branch")){return}
$ErrorActionPreference='Stop'
$sourceRoot=Split-Path $PSScriptRoot -Parent
foreach($name in @('Core','Git')){
    $manifest=Join-Path $sourceRoot "FrenchExDev2.QuietCli.$name.PoSh/FrenchExDev2.QuietCli.$name.PoSh.psd1"
    $expected=[IO.Path]::ChangeExtension($manifest,'.psm1')
    $loaded=Get-Module "FrenchExDev2.QuietCli.$name.PoSh"
    if(!$loaded -or $loaded.Path -cne $expected){Import-Module $manifest -ErrorAction Stop}
    if((Get-Module "FrenchExDev2.QuietCli.$name.PoSh").Path -cne $expected){throw 'WorkBranchModulePathMismatch'}
}
function Invoke-QuietWorkBranchGit {
    <#
    .SYNOPSIS
    Runs one exact Git operation and rejects failed or incomplete outcomes without retrying.
    .PARAMETER Arguments
    Native arguments, never interpreted by a shell.
    #>
    param([string[]]$Arguments)
    $result=quiet -AsObject -C work-branch -WorkingDirectory $WorkspaceRoot -RecordDelimiter "`n" -Data ([Text.StringBuilder]::new()) -Output {
        param($event,$runtime)
        if($event.Stream -ne 'stdout'){return}
        if($runtime.Data.Length+$event.Text.Length -gt 65536){throw 'WorkBranchMetadataTooLarge'}
        [void]$runtime.Data.AppendLine($event.Text)
    } -Complete {param($runtime) $runtime.Data.ToString().TrimEnd()} -FilePath git -ArgumentList $Arguments
    if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count){throw ('WorkBranchGitFailed: '+$Arguments[0])}
    return [string]$result.Data
}
$null=Invoke-QuietWorkBranchGit @('check-ref-format','--branch',$Branch)
$null=Invoke-QuietWorkBranchGit @('check-ref-format','--branch',$BaseBranch)
if(Invoke-QuietWorkBranchGit @('branch','--list',$Branch)){throw 'WorkBranchAlreadyExists'}
if(!(Invoke-QuietWorkBranchGit @('branch','--list',$BaseBranch))){throw 'WorkBranchLocalBaseMissing'}
$status=quiet -AsObject -C work-branch -WorkingDirectory $WorkspaceRoot git status
if($status.Outcome -ne 'Success' -or !$status.Completeness.Source -or !$status.Completeness.Analysis -or $status.Error.Count -or $status.Data.Detached -or $status.Data.Unborn -or $status.Data.Counts.Conflicted){throw 'WorkBranchInitialStateInvalid'}
$originalBranch=$status.Data.Branch
$files=@(foreach($entry in $status.Data.Entries){
    $path=Join-Path $WorkspaceRoot $entry.Path
    [pscustomobject]@{Path=$entry.Path;Status=$entry.Status;Hash=if(Test-Path -LiteralPath $path -PathType Leaf){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}else{$null}}
})
$shelf=$null
if($files.Count){
    if(!$ShelfName){$ShelfName='quietcli-shelf-before-'+$Branch+'-'+[DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')}
    $null=Invoke-QuietWorkBranchGit @('stash','push','--include-untracked','--message',$ShelfName)
    $shelf=Invoke-QuietWorkBranchGit @('rev-parse','--verify','refs/stash')
    if($shelf -cnotmatch '\A[a-f0-9]{40}(?:[a-f0-9]{24})?\z'){throw 'WorkBranchShelfIdentityInvalid'}
    Write-Host ('Shelf retained: '+$shelf+' | '+$ShelfName)
}
$clean=quiet -AsObject -C work-branch -WorkingDirectory $WorkspaceRoot git status
if($clean.Outcome -ne 'Success' -or !$clean.Completeness.Source -or !$clean.Completeness.Analysis -or $clean.Error.Count -or !$clean.Data.Clean){throw 'WorkBranchShelfDidNotCleanCheckout'}
$null=Invoke-QuietWorkBranchGit @('switch',$BaseBranch)
$null=Invoke-QuietWorkBranchGit @('pull','--ff-only','--no-tags',$Remote,$BaseBranch)
$baseCommit=Invoke-QuietWorkBranchGit @('rev-parse','HEAD')
$remoteCommit=Invoke-QuietWorkBranchGit @('ls-remote','--heads',$Remote,('refs/heads/'+$BaseBranch))
if($remoteCommit -cne ($baseCommit+"`trefs/heads/"+$BaseBranch)){throw 'WorkBranchBaseDiffersFromRemote'}
$null=Invoke-QuietWorkBranchGit @('switch','--no-track','-c',$Branch,$BaseBranch)
if($shelf){$null=Invoke-QuietWorkBranchGit @('stash','apply','--index',$shelf)}
$restored=quiet -AsObject -C work-branch -WorkingDirectory $WorkspaceRoot git status
if($restored.Outcome -ne 'Success' -or !$restored.Completeness.Source -or !$restored.Completeness.Analysis -or $restored.Error.Count -or $restored.Data.Branch -cne $Branch -or $restored.Data.Counts.Conflicted){throw 'WorkBranchRestoreFailed'}
foreach($file in $files){
    $path=Join-Path $WorkspaceRoot $file.Path
    $actualHash=if(Test-Path -LiteralPath $path -PathType Leaf){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}else{$null}
    $entry=@($restored.Data.Entries|Where-Object Path -CEQ $file.Path)
    if($actualHash -cne $file.Hash -or $entry.Count -ne 1 -or $entry[0].Status -cne $file.Status){throw ('WorkBranchShelfContentChanged: '+$file.Path)}
}
[pscustomobject]@{Branch=$Branch;BaseBranch=$BaseBranch;BaseCommit=$baseCommit;PreviousBranch=$originalBranch;Shelf=$shelf;ShelfName=$ShelfName;RestoredFiles=$files.Count;ShelfRetained=[bool]$shelf}
