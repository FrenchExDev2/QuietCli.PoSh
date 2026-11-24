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
    try{$null=[semver]$Version}catch{throw 'ReleaseVersionInvalid'}
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if($errors.Count -or $ast.EndBlock.Statements.Count -ne 1 -or
        $ast.EndBlock.Statements[0] -isnot [Management.Automation.Language.PipelineAst] -or
        $ast.EndBlock.Statements[0].PipelineElements.Count -ne 1){throw 'ReleaseManifestInvalid'}
    $root=$ast.EndBlock.Statements[0].PipelineElements[0].Expression
    if($root -isnot [Management.Automation.Language.HashtableAst]){throw 'ReleaseManifestInvalid'}
    try{$manifest=$root.SafeGetValue()}catch{throw 'ReleaseManifestMustBeLiteral'}
    $versionPair=@($root.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'ModuleVersion'})
    $privatePair=@($root.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'PrivateData'})
    if($versionPair.Count -ne 1){throw 'ReleaseManifestPublicationMetadataRequired'}
    $edits=[Collections.Generic.List[object]]::new()
    if([string]$manifest.ModuleVersion -cne $base){
        $extent=$versionPair[0].Item2.Extent
        $edits.Add(@{Start=$extent.StartOffset;End=$extent.EndOffset;Value="'$base'"})
    }
    if(!$privatePair.Count){
        if($suffix){
            $position=$root.Extent.StartOffset+2
            $edits.Add(@{Start=$position;End=$position;Value="PrivateData=@{PSData=@{Prerelease='$suffix'}};"})
        }
    }else{
        $private=$privatePair[0].Item2.PipelineElements[0].Expression
        if($private -isnot [Management.Automation.Language.HashtableAst]){throw 'ReleaseManifestPublicationMetadataRequired'}
        $psDataPair=@($private.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'PSData'})
        if(!$psDataPair.Count){
            if($suffix){
                $position=$private.Extent.StartOffset+2
                $edits.Add(@{Start=$position;End=$position;Value="PSData=@{Prerelease='$suffix'};"})
            }
        }else{
            $psData=$psDataPair[0].Item2.PipelineElements[0].Expression
            if($psData -isnot [Management.Automation.Language.HashtableAst]){throw 'ReleaseManifestPublicationMetadataRequired'}
            $labelPair=@($psData.KeyValuePairs|Where-Object {$_.Item1.Value -ieq 'Prerelease'})
            if($labelPair.Count){
                if([string]$manifest.PrivateData.PSData.Prerelease -cne $suffix){
                    $extent=$labelPair[0].Item2.Extent
                    $edits.Add(@{Start=$extent.StartOffset;End=$extent.EndOffset;Value="'$suffix'"})
                }
            }elseif($suffix){
                $position=$psData.Extent.StartOffset+2
                $edits.Add(@{Start=$position;End=$position;Value="Prerelease='$suffix';"})
            }
        }
    }
    foreach($edit in $edits|Sort-Object Start -Descending){$Text=$Text.Substring(0,$edit.Start)+$edit.Value+$Text.Substring($edit.End)}
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}

function Assert-QuietReleaseTagSet {
    <#
    .SYNOPSIS
    Verifies local annotated release tags share one commit and match their declared batch; reads local refs only.
    .PARAMETER Tag
    Exact release tag names to deliver together.
    .PARAMETER GitCommand
    Operator's exact-argument quiet Git callback, returning Value, HasOutput and Lines.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Tag,[Parameter(Mandatory)][scriptblock]$GitCommand)
    $selected=@($Tag)
    if(!$selected.Count -or $selected.Count -gt 32 -or @($selected|Select-Object -Unique).Count -ne $selected.Count){throw 'ReleaseTagSetInvalid'}
    $revision=$null
    foreach($name in $selected){
        if($name -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]*/v[0-9][0-9A-Za-z.-]*\z'){throw ('ReleaseTagNameInvalid: '+$name)}
        $refs=@((& $GitCommand @('for-each-ref','--format=%(refname)%09%(objecttype)',('refs/tags/'+$name))).Lines|Where-Object {($_ -split "`t")[0] -ceq ('refs/tags/'+$name)})
        if(!$refs.Count){throw ('ReleaseTagMissingLocally: '+$name)}
        if(($refs[0] -split "`t")[-1] -cne 'tag'){throw ('ReleaseTagNotAnnotated: '+$name)}
        $commit=(& $GitCommand @('rev-parse','--verify',('refs/tags/'+$name+'^{commit}'))).Value
        if($null -eq $revision){$revision=$commit}elseif($commit -cne $revision){throw ('ReleaseTagRevisionMismatch: '+$name)}
        $annotation=(& $GitCommand @('for-each-ref','--format=%(contents)',('refs/tags/'+$name))).Lines -join "`n"
        $records=@([regex]::Matches($annotation,'(?m)^QuietCli-Release-Batch: (.+)$'))
        if($records.Count -gt 1){throw ('ReleaseTagBatchMismatch: '+$name)}
        if($records.Count){
            $batch=$records[0].Groups[1].Value|ConvertFrom-Json
            $members=@($batch.Tags|ForEach-Object {[string]$_}|Sort-Object -CaseSensitive)
            $expected=@($selected|Sort-Object -CaseSensitive)
            if($batch.Revision -cne $revision -or ($members -join "`n") -cne ($expected -join "`n")){throw ('ReleaseTagBatchMismatch: '+$name)}
        }elseif($selected.Count -ne 1){throw ('ReleaseTagBatchMismatch: '+$name)}
    }
    $revision
}

function Assert-QuietReleaseDelivery {
    <#
    .SYNOPSIS
    Fetches the remote delivery branch and requires the release commit on it and the selected tags absent remotely.
    .PARAMETER Tag
    Exact release tag names that will be pushed.
    .PARAMETER Revision
    Release commit the tags designate.
    .PARAMETER Remote
    Configured Git remote name.
    .PARAMETER DeliveryBranch
    Protected branch that must already contain Revision, develop by default.
    .PARAMETER GitCommand
    Operator's exact-argument quiet Git callback, returning Value, HasOutput and Lines.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Tag,[Parameter(Mandatory)][ValidatePattern('\A(?:[a-f0-9]{40}|[a-f0-9]{64})\z')][string]$Revision,
        [Parameter(Mandatory)][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote,
        [Parameter(Mandatory)][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._/-]*\z')][string]$DeliveryBranch,[Parameter(Mandatory)][scriptblock]$GitCommand)
    $remoteTags=@((& $GitCommand @('ls-remote','--tags','--refs',$Remote)).Lines|ForEach-Object {($_ -split "`t")[-1] -creplace '\Arefs/tags/',''})
    foreach($name in $Tag){if($name -cin $remoteTags){throw ('ReleaseTagAlreadyExists: '+$name)}}
    $null=& $GitCommand @('fetch','--no-tags','--quiet',$Remote,('refs/heads/'+$DeliveryBranch))
    $tip=(& $GitCommand @('rev-parse','--verify','FETCH_HEAD^{commit}')).Value
    if((& $GitCommand @('rev-list','--max-count=1',$Revision,('^'+$tip),'--')).HasOutput){throw ('ReleaseRevisionNotOnDeliveryBranch: '+$Revision+' is not contained in '+$Remote+'/'+$DeliveryBranch+'; merge its pull request first.')}
    $tip
}

function Push-QuietReleaseTags {
    <#
    .SYNOPSIS
    Atomically pushes existing local release tags once their commit is merged on the remote delivery branch.
    .PARAMETER Tag
    Exact release tag names, including every member of an annotated batch.
    .PARAMETER Remote
    Configured Git remote name.
    .PARAMETER DeliveryBranch
    Protected branch that must already contain the tagged commit.
    .PARAMETER GitCommand
    Operator's exact-argument quiet Git callback, returning Value, HasOutput and Lines.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param([Parameter(Mandatory)][string[]]$Tag,[ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._/-]*\z')][string]$DeliveryBranch='develop',[Parameter(Mandatory)][scriptblock]$GitCommand)
    $revision=Assert-QuietReleaseTagSet -Tag $Tag -GitCommand $GitCommand
    $result=[pscustomobject]@{Tags=@($Tag);Revision=$revision;Remote=$Remote;DeliveryBranch=$DeliveryBranch;DeliveryChecked=$false;Pushed=$false;TagPushState='NotRequested'}
    if(!$PSCmdlet.ShouldProcess(($Remote+' @ '+$revision),('Push release tags '+(@($Tag) -join ', ')+' after checking '+$Remote+'/'+$DeliveryBranch))){return $result}
    $null=Assert-QuietReleaseDelivery -Tag $Tag -Revision $revision -Remote $Remote -DeliveryBranch $DeliveryBranch -GitCommand $GitCommand
    $result.DeliveryChecked=$true
    $result.TagPushState='Pending'
    try{
        $null=& $GitCommand (@('push','--atomic',$Remote)+@($Tag|ForEach-Object {'refs/tags/'+$_+':refs/tags/'+$_}))
    }catch{
        $result.TagPushState='Unknown'
        Write-Warning 'Tag push failed or its outcome is unknown; inspect remote tags before any retry.'
        throw
    }
    $result.Pushed=$true
    $result.TagPushState='Confirmed'
    $result
}

function Get-QuietModuleReleaseSelection {
    <#
    .SYNOPSIS
    Selects per-package release versions and tags from already observed tag names; reads manifests only, without Git or network access.
    .PARAMETER WorkspaceRoot
    Source checkout whose business package manifests are discovered.
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
    Requires every selected version to already match its manifest.
    .PARAMETER KnownTags
    Local tag names and remote ls-remote tag records; every selected tag must be absent from them.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[string[]]$Module=@('Core'),[Parameter(Mandatory)][string]$Version,
        [Nullable[int]]$Preview,[switch]$PreviewSpecified,[switch]$NextPreview,[switch]$NoCommit,[string[]]$KnownTags=@())
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'GalleryRelease.psm1')) -DisableNameChecking
    $targets=@(Select-QuietGalleryReleaseTargets $WorkspaceRoot -Module $Module)
    if($Version -cnotmatch '\A((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))(?:-([A-Za-z][A-Za-z0-9-]*))?\z'){throw 'ReleaseVersionInvalid'}
    $base=$Matches[1];$hasSuffix=$Matches.ContainsKey(2)
    try{$null=[semver]$Version}catch{throw 'ReleaseVersionInvalid'}
    if(($NextPreview -or $PreviewSpecified) -and $hasSuffix){throw 'ReleasePreviewVersionConflict'}
    if($null -ne $Preview -and $Preview -lt 1){throw 'ReleasePreviewNumberInvalid'}
    if($NextPreview -and $PreviewSpecified -and $null -ne $Preview){throw 'ReleasePreviewSelectionConflict'}
    $known=@($KnownTags|ForEach-Object {($_ -split "`t")[-1] -creplace '\Arefs/tags/',''})
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
    $releases.ToArray()
}

function Invoke-QuietModuleRelease {
    <#
    .SYNOPSIS
    Plans selected releases: commits version edits on a work branch, or tags a merged commit and pushes only those tags.
    .DESCRIPTION
    No branch is ever pushed. When selected versions differ from HEAD, the edits are committed on the current work
    branch without tags; deliver that commit through a pull request. When versions already match HEAD (or NoCommit),
    annotated tags are created and, unless NoPush, pushed atomically only once HEAD is contained in the remote
    delivery branch.
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
    .PARAMETER DeliveryBranch
    Protected branch that receives release commits through pull requests and must contain tagged commits.
    .PARAMETER Message
    Optional release commit message.
    .PARAMETER GitCommand
    Operator's exact-argument quiet Git callback, returning Value, HasOutput and Lines.
    .PARAMETER CommitCommand
    Existing checked commit orchestration callback.
    #>
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Medium')]
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[string[]]$Module=@('Core'),[Parameter(Mandatory)][string]$Version,
        [Nullable[int]]$Preview,[switch]$PreviewSpecified,[switch]$NextPreview,[switch]$NoCommit,[switch]$NoPush,
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._/-]*\z')][string]$DeliveryBranch='develop',[string]$Message,
        [Parameter(Mandatory)][scriptblock]$GitCommand,[Parameter(Mandatory)][scriptblock]$CommitCommand)
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'GalleryRelease.psm1')) -DisableNameChecking
    $revision=(& $GitCommand @('rev-parse','--verify','HEAD^{commit}')).Value
    $branch=(& $GitCommand @('rev-parse','--abbrev-ref','HEAD')).Value
    $dirty=(& $GitCommand @('status','--porcelain=v1','--untracked-files=normal')).HasOutput
    if(!$WhatIfPreference -and $dirty){throw 'ReleaseRequiresCleanCheckout'}
    $local=@((& $GitCommand @('tag','--list')).Lines)
    $remoteTags=@()
    $remoteChecked=!$WhatIfPreference
    if($remoteChecked){$remoteTags=@((& $GitCommand @('ls-remote','--tags','--refs',$Remote)).Lines)}
    $selection=@{WorkspaceRoot=$WorkspaceRoot;Module=$Module;Version=$Version;Preview=$Preview;PreviewSpecified=$PreviewSpecified;NextPreview=$NextPreview;NoCommit=$NoCommit;KnownTags=(@($local)+@($remoteTags))}
    $releases=@(Get-QuietModuleReleaseSelection @selection)
    $changed=@($releases|Where-Object VersionChanged)
    $mode=if(!$NoCommit -and $changed.Count){'Commit'}else{'Tag'}
    if($mode -ceq 'Commit' -and ($branch -ceq 'HEAD' -or $branch -ceq $DeliveryBranch)){throw ('ReleaseCommitRequiresWorkBranch: create a fix/*, feature/* or release/* branch (Invoke-QuietRelease.ps1 creates one); '+$DeliveryBranch+' only receives pull requests.')}
    $result=[pscustomobject]@{Mode=$mode;Revision=$revision;Branch=$branch;Remote=$Remote;DeliveryBranch=$DeliveryBranch;RemoteChecked=$remoteChecked;Committed=$false;Created=@();DeliveryChecked=$false;Pushed=$false;TagPushState='NotRequested';Releases=@($releases|Select-Object Module,Component,Version,Preview,Tag,VersionChanged);Receipt=$null}
    $description=($result.Releases|ForEach-Object {$_.Tag}) -join ', '
    $action=if($mode -ceq 'Commit'){'Commit version edits for '+$description+' on '+$branch+'; tags follow the merge into '+$DeliveryBranch}else{'Tag '+$description+'; push='+(!$NoPush)}
    if(!$PSCmdlet.ShouldProcess(($WorkspaceRoot+' @ '+$revision),$action)){return $result}
    $reportDirectory=[IO.Path]::Combine($WorkspaceRoot,('artifacts/releases/'+[guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($reportDirectory)
    $result.Receipt=[IO.Path]::Combine($reportDirectory,'release.json')
    try{
        if($mode -ceq 'Commit'){
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
            Write-Warning ('Release versions committed on '+$branch+'. Merge its pull request into '+$DeliveryBranch+', then rerun with -NoCommit on the updated '+$DeliveryBranch+' to create and push the tags.')
            return $result
        }
        if(!$NoPush){
            $null=Assert-QuietReleaseDelivery -Tag @($releases.Tag) -Revision $revision -Remote $Remote -DeliveryBranch $DeliveryBranch -GitCommand $GitCommand
            $result.DeliveryChecked=$true
        }
        if((& $GitCommand @('status','--porcelain=v1','--untracked-files=normal')).HasOutput){throw 'ReleaseCheckoutChangedBeforeTagging'}
        $batch=@{SchemaVersion=1;Revision=$revision;Tags=@($releases.Tag)}|ConvertTo-Json -Compress
        foreach($release in $releases){
            $plan=Resolve-QuietGalleryReleaseTag -WorkspaceRoot $WorkspaceRoot -Tag $release.Tag
            $annotation=$plan.Module+' '+$plan.Version+" release`n`nQuietCli-Release-Batch: "+$batch
            $null=& $GitCommand @('-c','tag.gpgSign=false','tag','--annotate','--message',$annotation,'--',$release.Tag,$revision)
            $result.Created+=@($release.Tag)
        }
        if(!$NoPush){
            if((Assert-QuietReleaseTagSet -Tag $result.Created -GitCommand $GitCommand) -cne $revision){throw 'ReleaseTagRevisionMismatch'}
            $result.TagPushState='Pending'
            $null=& $GitCommand (@('push','--atomic',$Remote)+@($result.Created|ForEach-Object {'refs/tags/'+$_+':refs/tags/'+$_}))
            $result.Pushed=$true
            $result.TagPushState='Confirmed'
        }
        $result
    }catch{
        if($result.TagPushState -ceq 'Pending'){$result.TagPushState='Unknown'}
        $_.Exception.Data['ReleaseReceipt']=$result.Receipt
        Write-Warning ('Release stopped; retained local changes/tags and receipt: '+$result.Receipt)
        throw
    }finally{
        $json=$result|ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($result.Receipt,$json+"`n",[Text.UTF8Encoding]::new($false))
    }
}
Export-ModuleMember -Function Get-QuietNextPreviewNumber,Get-QuietReleaseManifestText,Get-QuietModuleReleaseSelection,Assert-QuietReleaseTagSet,Assert-QuietReleaseDelivery,Push-QuietReleaseTags,Invoke-QuietModuleRelease
