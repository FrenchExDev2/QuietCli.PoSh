#requires -Version 7.6
<#
.SYNOPSIS
Removes all local and GitHub tags from one verified checkout, preserving a metadata receipt.
.PARAMETER WorkspaceRoot
QuietCli checkout whose local tag references are selected.
.PARAMETER Repository
GitHub owner/repository required to match the configured remote.
.PARAMETER Remote
Configured remote used only to verify the repository identity.
.PARAMETER PlanOnly
Lists tag metadata without deleting references or writing a receipt.
.PARAMETER ReportPath
New UTF-8 JSON receipt containing the original reference identities and deletion progress.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository='FrenchExDev2/QuietCli.PoSh',
    [ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$Remote='origin',
    [switch]$PlanOnly,
    [string]$ReportPath
)
$operation=if($PlanOnly){'Inspect all local and GitHub tag references'}else{'Delete all local and GitHub tag references'}
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,$operation)){return}
$ErrorActionPreference='Stop'
$WorkspaceRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path))
$sourceRoot=Split-Path $PSScriptRoot -Parent
foreach($name in @('Core','Git')){
    $manifest=Join-Path $sourceRoot "FrenchExDev2.QuietCli.$name.PoSh/FrenchExDev2.QuietCli.$name.PoSh.psd1"
    $expected=[IO.Path]::ChangeExtension($manifest,'.psm1')
    $loaded=Get-Module "FrenchExDev2.QuietCli.$name.PoSh"
    if(!$loaded -or $loaded.Path -cne $expected){Import-Module $manifest -ErrorAction Stop}
    if((Get-Module "FrenchExDev2.QuietCli.$name.PoSh").Path -cne $expected){throw 'TagRemovalModulePathMismatch'}
}
function Invoke-QuietTagCommand {
    <#
    .SYNOPSIS
    Executes a bounded administrative metadata request through the local QuietCli facade.
    .PARAMETER Executable
    Git or GitHub CLI executable.
    .PARAMETER Arguments
    Exact native argument vector without shell evaluation.
    #>
    param([ValidateSet('git','gh')][string]$Executable,[string[]]$Arguments)
    $result=quiet -AsObject -C tag-removal -WorkingDirectory $WorkspaceRoot -RecordDelimiter "`n" -Data ([Text.StringBuilder]::new()) -Output {
        param($event,$runtime)
        if($event.Stream -ne 'stdout'){return}
        if($runtime.Data.Length+$event.Text.Length -gt 2097152){throw 'TagMetadataTooLarge'}
        [void]$runtime.Data.AppendLine($event.Text)
    } -Complete {param($runtime) $runtime.Data.ToString().TrimEnd()} -FilePath $Executable -ArgumentList $Arguments
    if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Error.Count){throw ('TagCommandFailed: '+$Executable+' '+$Arguments[0])}
    return [string]$result.Data
}
function Read-QuietTagReferences {
    <#
    .SYNOPSIS
    Parses complete tag names and object identities while rejecting non-tag references.
    .PARAMETER Text
    Tab-separated reference/object metadata returned by Git or GitHub CLI.
    #>
    param([AllowEmptyString()][string]$Text)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($line in ($Text -split '\r?\n')){
        if(!$line){continue}
        if($line -cnotmatch '\A(refs/tags/[^\s]+)\t([a-f0-9]{40}|[a-f0-9]{64})\z' -or !$seen.Add($Matches[1])){throw 'TagReferenceMetadataInvalid'}
        [pscustomobject]@{Ref=$Matches[1];ObjectId=$Matches[2]}
    }
}
$actualRoot=Invoke-QuietTagCommand git @('rev-parse','--show-toplevel')
if(![StringComparer]::OrdinalIgnoreCase.Equals($WorkspaceRoot,[IO.Path]::GetFullPath($actualRoot))){throw 'TagRemovalCheckoutMismatch'}
$remoteUrl=Invoke-QuietTagCommand git @('remote','get-url',$Remote)
if($remoteUrl -notmatch '\A(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?<repository>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?\z' -or $Matches.repository -cne $Repository){throw 'TagRemovalRemoteMismatch'}
$local=@(Read-QuietTagReferences (Invoke-QuietTagCommand git @('for-each-ref','--format=%(refname)%09%(objectname)','refs/tags/')))
$endpoint="repos/$Repository/git/matching-refs/tags/"
$remoteTags=@(Read-QuietTagReferences (Invoke-QuietTagCommand gh @('api','--hostname','github.com','--paginate',$endpoint,'--jq','.[] | [.ref, .object.sha] | @tsv')))
if($PlanOnly){return [pscustomobject]@{Repository=$Repository;Local=$local;GitHub=$remoteTags;PlanOnly=$true}}
if(!$ReportPath){$ReportPath=Join-Path ([IO.Path]::GetTempPath()) ('quietcli-tag-removal-'+[guid]::NewGuid().ToString('N')+'.json')}
$ReportPath=[IO.Path]::GetFullPath($ReportPath,$PWD.Path)
if(Test-Path -LiteralPath $ReportPath){throw 'TagRemovalReceiptAlreadyExists'}
if(!(Test-Path -LiteralPath (Split-Path $ReportPath -Parent) -PathType Container)){throw 'TagRemovalReceiptParentMissing'}
$receipt=@{Repository=$Repository;Workspace=$WorkspaceRoot;StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');Local=$local;GitHub=$remoteTags;DeletedLocal=@();DeletedGitHub=@();State='Running';Error=$null}
[IO.File]::WriteAllText($ReportPath,($receipt|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
try{
    foreach($tag in $remoteTags){
        $name=$tag.Ref.Substring('refs/tags/'.Length)
        $null=Invoke-QuietTagCommand gh @('api','--hostname','github.com','--method','DELETE',"repos/$Repository/git/refs/tags/$([Uri]::EscapeDataString($name))")
        $receipt.DeletedGitHub+=@($tag.Ref)
        [IO.File]::WriteAllText($ReportPath,($receipt|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    }
    foreach($tag in $local){
        $null=Invoke-QuietTagCommand git @('update-ref','-d',$tag.Ref,$tag.ObjectId)
        $receipt.DeletedLocal+=@($tag.Ref)
        [IO.File]::WriteAllText($ReportPath,($receipt|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    }
    $remainingLocal=@(Read-QuietTagReferences (Invoke-QuietTagCommand git @('for-each-ref','--format=%(refname)%09%(objectname)','refs/tags/')))
    $remainingRemote=@(Read-QuietTagReferences (Invoke-QuietTagCommand gh @('api','--hostname','github.com','--paginate',$endpoint,'--jq','.[] | [.ref, .object.sha] | @tsv')))
    if($remainingLocal.Count -or $remainingRemote.Count){throw 'TagRemovalReferencesRemain'}
    $receipt.State='Success'
}catch{$receipt.State='Failed';$receipt.Error=$_.Exception.Message;throw}
finally{[IO.File]::WriteAllText($ReportPath,($receipt|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
[pscustomobject]@{Repository=$Repository;State=$receipt.State;DeletedLocal=$receipt.DeletedLocal.Count;DeletedGitHub=$receipt.DeletedGitHub.Count;RemainingLocal=0;RemainingGitHub=0;ReportPath=$ReportPath}
