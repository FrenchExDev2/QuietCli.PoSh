#requires -Version 7.6
function Get-QuietNextPreviewNumber {
    <#
    .SYNOPSIS
    Computes the next numeric preview from exact package/version tag names, independently of lexical ordering.
    .PARAMETER Module
    Full package name.
    .PARAMETER Version
    Numeric three-part release version.
    .PARAMETER Tags
    Local tag names or ls-remote tag records; no Git or network operation occurs here.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Module,[Parameter(Mandatory)][string]$Version,[string[]]$Tags=@())
    $expression='\A'+[regex]::Escape($Module)+'/v'+[regex]::Escape($Version)+'-preview([1-9][0-9]*)\z'
    $maximum=0L
    foreach($record in $Tags){
        $tag=($record -split "`t")[-1] -creplace '\Arefs/tags/',''
        $match=[regex]::Match($tag,$expression,[Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if(!$match.Success){continue}
        $number=0L
        if(![long]::TryParse($match.Groups[1].Value,[ref]$number) -or $number -ge [int]::MaxValue){throw 'ReleasePreviewNumberOverflow'}
        $maximum=[Math]::Max($maximum,$number)
    }
    [int]($maximum+1)
}

function Get-QuietReleaseManifestText {
    <#
    .SYNOPSIS
    Produces a literal manifest version edit while preserving GUIDs, dependencies and unrelated text.
    .PARAMETER Text
    Original manifest text.
    .PARAMETER Version
    Full stable or Gallery-compatible prerelease version.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string]$Version)
    if($Version -cnotmatch '\A((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-([A-Za-z][A-Za-z0-9-]*))?\z'){throw 'ReleaseVersionInvalid'}
    $base=$Matches[1];$suffix=if($Matches.ContainsKey(2)){$Matches[2]}else{''}
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if($errors.Count -or $ast.EndBlock.Statements.Count -ne 1){throw 'ReleaseManifestInvalid'}
    $root=$ast.EndBlock.Statements[0].PipelineElements[0].Expression
    if($root -isnot [Management.Automation.Language.HashtableAst]){throw 'ReleaseManifestInvalid'}
    try{$null=$root.SafeGetValue()}catch{throw 'ReleaseManifestMustBeLiteral'}
    $versionPair=@($root.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'ModuleVersion'})
    $privatePair=@($root.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'PrivateData'})
    if($versionPair.Count -ne 1 -or $privatePair.Count -ne 1){throw 'ReleaseManifestPublicationMetadataRequired'}
    $versionExtent=$versionPair[0].Item2.Extent
    $edits=[Collections.Generic.List[object]]::new()
    $edits.Add(@{Start=$versionExtent.StartOffset;End=$versionExtent.EndOffset;Value="'$base'"})
    $private=$privatePair[0].Item2.PipelineElements[0].Expression
    $psDataPair=@($private.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'PSData'})
    if(!$psDataPair.Count){
        $position=$private.Extent.EndOffset-1
        $edits.Add(@{Start=$position;End=$position;Value=";PSData=@{Prerelease='$suffix'}"})
    }else{
        $psData=$psDataPair[0].Item2.PipelineElements[0].Expression
        $labelPair=@($psData.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'Prerelease'})
        if($labelPair.Count){$extent=$labelPair[0].Item2.Extent;$edits.Add(@{Start=$extent.StartOffset;End=$extent.EndOffset;Value="'$suffix'"})}
        else{$position=$psData.Extent.EndOffset-1;$edits.Add(@{Start=$position;End=$position;Value=";Prerelease='$suffix'"})}
    }
    foreach($edit in $edits|Sort-Object Start -Descending){$Text=$Text.Substring(0,$edit.Start)+$edit.Value+$Text.Substring($edit.End)}
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}

function Invoke-QuietModuleRelease {
    <#
    .SYNOPSIS
    Plans selected releases, commits owned version edits and pushes only the selected annotated tags.
    .PARAMETER WorkspaceRoot
    Clean Git source checkout.
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
    .PARAMETER NoCommit
    Requires versions already committed; never creates mismatching tags on an older commit.
    .PARAMETER NoPush
    Creates local tags only; remote tags are still read to reject collisions before edits.
    .PARAMETER Remote
    Configured Git remote name.
    .PARAMETER Message
    Optional release commit message.
    .PARAMETER GitCommand
    Operator's exact-argument quiet Git callback, returning Value, HasOutput and Lines.
    .PARAMETER CommitCommand
    Existing checked commit orchestration callback.
    .PARAMETER PushCommand
    Existing branch push and PR-update orchestration callback.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[string[]]$Module=@('Core'),[Parameter(Mandatory)][string]$Version,
        [Nullable[int]]$Preview,[switch]$PreviewSpecified,[switch]$NextPreview,[switch]$NoCommit,[switch]$NoPush,
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',[string]$Message,
        [Parameter(Mandatory)][scriptblock]$GitCommand,[Parameter(Mandatory)][scriptblock]$CommitCommand,[Parameter(Mandatory)][scriptblock]$PushCommand)
    Import-Module (Join-Path $PSScriptRoot 'GalleryRelease.psm1')
    $targets=@(Select-QuietGalleryReleaseTargets $WorkspaceRoot -Module $Module)
    if($Version -cnotmatch '\A((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-([A-Za-z][A-Za-z0-9-]*))?\z'){throw 'ReleaseVersionInvalid'}
    $base=$Matches[1];$hasSuffix=$Matches.ContainsKey(2)
    try{$null=[semver]$Version}catch{throw 'ReleaseVersionInvalid'}
    if(($NextPreview -or $PreviewSpecified) -and $hasSuffix){throw 'ReleasePreviewVersionConflict'}
    if($null -ne $Preview -and $Preview -lt 1){throw 'ReleasePreviewNumberInvalid'}
    if($NextPreview -and $PreviewSpecified -and $null -ne $Preview){throw 'ReleasePreviewSelectionConflict'}
    $revision=(& $GitCommand @('rev-parse','--verify','HEAD^{commit}')).Value
    $branch=(& $GitCommand @('rev-parse','--abbrev-ref','HEAD')).Value
    $dirty=(& $GitCommand @('status','--porcelain=v1','--untracked-files=normal')).HasOutput
    if(!$WhatIfPreference -and $dirty){throw 'ReleaseRequiresCleanCheckout'}
    if(!$NoPush -and $branch -ceq 'HEAD'){throw 'ReleasePushRequiresBranch'}
    $local=@((& $GitCommand @('tag','--list')).Lines)
    $remoteTags=@()
    $remoteChecked=!$WhatIfPreference
    if($remoteChecked){$remoteTags=@((& $GitCommand @('ls-remote','--tags','--refs',$Remote)).Lines)}
    $known=@($local)+@($remoteTags|ForEach-Object {($_ -split "`t")[-1] -creplace '\Arefs/tags/',''})
    $releases=[Collections.Generic.List[object]]::new()
    foreach($target in $targets){
        $number=$null;$selectedVersion=$Version
        if($NextPreview -or $PreviewSpecified){
            $number=if($null -ne $Preview){[int]$Preview}else{Get-QuietNextPreviewNumber -Module $target.Module -Version $base -Tags $known}
            $selectedVersion=$base+'-preview'+$number
        }
        $tag=$target.Module+'/v'+$selectedVersion
        if($tag -cin $known){throw ('ReleaseTagAlreadyExists: '+$tag)}
        if($NoCommit -and $target.Version -cne $selectedVersion){throw 'ReleaseNoCommitRequiresCommittedVersions'}
        $text=[IO.File]::ReadAllText($target.ManifestPath,[Text.UTF8Encoding]::new($false,$true))
        $updated=Get-QuietReleaseManifestText -Text $text -Version $selectedVersion
        $releases.Add([pscustomobject]@{Module=$target.Module;Component=$target.Component;Version=$selectedVersion;Preview=$number;Tag=$tag;ManifestPath=$target.ManifestPath;OriginalText=$text;UpdatedText=$updated;VersionChanged=($target.Version -cne $selectedVersion)})
    }
    $result=[pscustomobject]@{Revision=$revision;Branch=$branch;Remote=$Remote;RemoteChecked=$remoteChecked;Committed=$false;Created=@();Pushed=$false;BranchPushed=$false;BranchPushState='NotRequested';TagPushState='NotRequested';Releases=@($releases|Select-Object Module,Component,Version,Preview,Tag,VersionChanged);Receipt=$null}
    $description=($result.Releases|ForEach-Object {$_.Tag}) -join ', '
    if(!$PSCmdlet.ShouldProcess(($WorkspaceRoot+' @ '+$revision),('Release '+$description+'; commit='+(!$NoCommit)+'; push='+(!$NoPush)))){return $result}
    $reportDirectory=Join-Path $WorkspaceRoot ('artifacts/releases/'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($reportDirectory)
    $result.Receipt=Join-Path $reportDirectory 'release.json'
    try{
        $changed=@($releases|Where-Object VersionChanged)
        if(!$NoCommit -and $changed.Count){
            foreach($release in $changed){
                if([IO.File]::ReadAllText($release.ManifestPath,[Text.UTF8Encoding]::new($false,$true)) -cne $release.OriginalText){throw 'ReleaseManifestChangedDuringPlanning'}
                [IO.File]::WriteAllText($release.ManifestPath,$release.UpdatedText,[Text.UTF8Encoding]::new($false))
            }
            if(!$Message){$Message='Release '+(($result.Releases|ForEach-Object {$_.Module+' '+$_.Version}) -join ', ')}
            $paths=@($changed|ForEach-Object {[IO.Path]::GetRelativePath($WorkspaceRoot,$_.ManifestPath).Replace('\','/')})
            $null=& $CommitCommand $WorkspaceRoot $Message $paths
            $result.Committed=$true
            $revision=(& $GitCommand @('rev-parse','--verify','HEAD^{commit}')).Value
            if($revision -ceq $result.Revision){throw 'ReleaseCommitDidNotAdvanceHead'}
            $result.Revision=$revision
        }
        if((& $GitCommand @('status','--porcelain=v1','--untracked-files=normal')).HasOutput){throw 'ReleaseCheckoutChangedBeforeTagging'}
        foreach($release in $releases){
            $plan=Resolve-QuietGalleryReleaseTag -WorkspaceRoot $WorkspaceRoot -Tag $release.Tag
            $null=& $GitCommand @('-c','tag.gpgSign=false','tag','--annotate','--message',($plan.Module+' '+$plan.Version+' release'),'--',$release.Tag,$revision)
            $result.Created+=@($release.Tag)
        }
        if(!$NoPush){
            $result.BranchPushState='Pending'
            $null=& $PushCommand $WorkspaceRoot $Remote $branch
            $result.BranchPushed=$true
            $result.BranchPushState='Confirmed'
            $arguments=@('push','--atomic',$Remote)+@($result.Created|ForEach-Object {'refs/tags/'+$_+':refs/tags/'+$_})
            $result.TagPushState='Pending'
            $null=& $GitCommand $arguments
            $result.Pushed=$true
            $result.TagPushState='Confirmed'
        }
        $result
    }catch{
        if($result.BranchPushState -ceq 'Pending'){$result.BranchPushState='Unknown'}
        if($result.TagPushState -ceq 'Pending'){$result.TagPushState='Unknown'}
        $_.Exception.Data['ReleaseReceipt']=$result.Receipt
        Write-Warning ('Release stopped; retained local changes/tags and receipt: '+$result.Receipt)
        throw
    }finally{
        $json=$result|ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($result.Receipt,$json+"`n",[Text.UTF8Encoding]::new($false))
    }
}
Export-ModuleMember -Function Get-QuietNextPreviewNumber,Get-QuietReleaseManifestText,Invoke-QuietModuleRelease
