function Test-QuietReleaseTags {
    <#
    .SYNOPSIS
    Checks numeric preview selection, real owned Git tag/commit/push lifecycles and no-write previews.
    .PARAMETER WorkspaceRoot
    Source checkout providing the operator and pure release helpers.
    .PARAMETER RunDirectory
    Owned test directory outside the checkout.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/ReleaseTags.psm1) -Force
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/GalleryRelease.psm1) -Force
    $random=[Random]::new(611111)
    foreach($index in 1..128){
        $maximum=$random.Next(10,100000)
        $tags=@("FrenchExDev2.QuietCli.Git.PoSh/v2.3.4-preview$maximum",'FrenchExDev2.QuietCli.Git.PoSh/v2.3.4-preview9',"abc`trefs/tags/FrenchExDev2.QuietCli.Git.PoSh/v2.3.4-preview$($maximum-1)",'FrenchExDev2.QuietCli.Core.PoSh/v2.3.4-preview999999','FrenchExDev2.QuietCli.Git.PoSh/v2.3.5-preview999999','FrenchExDev2.QuietCli.Git.PoSh/v2.3.4-preview20261111T010000Z')
        if((Get-QuietNextPreviewNumber -Module FrenchExDev2.QuietCli.Git.PoSh -Version 2.3.4 -Tags $tags) -ne ($maximum+1)){throw 'NextPreviewNotNumericOrPackageScoped'}
    }
    $rejected=$false;try{$null=Get-QuietNextPreviewNumber -Module Pkg -Version 1.2.3 -Tags 'Pkg/v1.2.3-preview2147483647'}catch{$rejected=$true}
    if(!$rejected){throw 'PreviewCounterOverflowAccepted'}
    $fixture=Join-Path $RunDirectory release-tags
    $remote=Join-Path $RunDirectory release-tags-remote.git
    [void][IO.Directory]::CreateDirectory($fixture)
    [void][IO.Directory]::CreateDirectory($remote)
    $emptyTemplate=Join-Path $RunDirectory 'release-empty-template'
    [void][IO.Directory]::CreateDirectory($emptyTemplate)
    $observed=@{Commits=0;Pushes=0}
    function Invoke-ReleaseFixtureGit {
        <# .SYNOPSIS
        Executes exact Git arguments against an owned repository with bounded metadata.
        .PARAMETER Arguments
        Native arguments.
        .PARAMETER Directory
        Owned repository.
        #>
        param([string[]]$Arguments,[string]$Directory=$fixture)
        $r=quiet -AsObject -C release-fixture -WorkingDirectory $Directory -RecordDelimiter "`n" -Data @{Value='';HasOutput=$false;Lines=[Collections.Generic.List[string]]::new()} -Output {
            param($e,$n)
            if($e.Stream -ne 'stdout' -or !$e.Text.Trim()){return}
            $line=$e.Text.TrimEnd([char[]]"`r`n")
            if($n.Data.Lines.Count -ge 200 -or $line.Length -gt 4096){throw 'ReleaseFixtureMetadataOverflow'}
            if(!$n.Data.HasOutput){$n.Data.Value=$line}
            $n.Data.HasOutput=$true;$n.Data.Lines.Add($line)
        } -Complete {param($n)$n.Data} -FilePath git -ArgumentList $Arguments
        if($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count){throw ('ReleaseFixtureGitFailed: '+$Arguments[0])}
        $r.Data
    }
    $null=Invoke-ReleaseFixtureGit @('init','--bare','--quiet',("--template="+$emptyTemplate)) -Directory $remote
    $null=Invoke-ReleaseFixtureGit @('init','--quiet','--initial-branch=fixture-release',("--template="+$emptyTemplate))
    $null=Invoke-ReleaseFixtureGit @('config','core.hooksPath',$emptyTemplate)
    $null=Invoke-ReleaseFixtureGit @('config','core.hooksPath',$emptyTemplate) -Directory $remote
    $null=Invoke-ReleaseFixtureGit @('config','user.name','Release fixture')
    $null=Invoke-ReleaseFixtureGit @('config','user.email','release@example.invalid')
    $null=Invoke-ReleaseFixtureGit @('config','commit.gpgSign','false')
    $null=Invoke-ReleaseFixtureGit @('remote','add','origin',$remote)
    [IO.File]::WriteAllText((Join-Path $fixture '.gitignore'),"artifacts/`n",[Text.UTF8Encoding]::new($false))
    foreach($component in @('Core','Git','Vagrant','DataOnly')){
        $name="FrenchExDev2.QuietCli.$component.PoSh";$directory=Join-Path $fixture $name
        [void][IO.Directory]::CreateDirectory($directory)
        [IO.File]::WriteAllText((Join-Path $directory "$name.psm1"),"throw 'ReleaseExecutedBusinessModule'`n",[Text.UTF8Encoding]::new($false))
        $flag=if($component -ceq 'Vagrant'){'false'}else{'true'}
        $text="@{RootModule='$name.psm1';ModuleVersion='2.3.4';GUID='fb86bdbe-f964-461c-b144-a655e42df279';PrivateData=@{PSData=@{Prerelease='preview1'};QuietCli=@{Publishable=`$$flag}}}`n"
        [IO.File]::WriteAllText((Join-Path $directory "$name.psd1"),$text,[Text.UTF8Encoding]::new($false))
    }
    $null=Invoke-ReleaseFixtureGit @('add','--','.')
    $null=Invoke-ReleaseFixtureGit @('commit','--quiet','--no-verify','-m','Owned release fixture')
    if(@(Select-QuietGalleryReleaseTargets $fixture -Module All).Count -ne 3){throw 'ReleaseSelectionNotDataDriven'}
    $operator=Join-Path $WorkspaceRoot scripts/New-QuietPreviewTag.ps1
    $before=(Invoke-ReleaseFixtureGit @('rev-parse','HEAD')).Value
    $preview=& $operator -WorkspaceRoot $fixture -Module Core,Git -Version 2.3.4 -NextPreview -WhatIf
    if($preview.Created.Count -or $preview.Pushed -or $preview.RemoteChecked -or $preview.Receipt -or (Invoke-ReleaseFixtureGit @('rev-parse','HEAD')).Value -cne $before -or (Invoke-ReleaseFixtureGit @('status','--porcelain')).HasOutput){throw 'ReleaseWhatIfProducedEffects'}
    $nullable=& $operator -WorkspaceRoot $fixture -Module Core,Git -Version 2.3.4 -Preview $null -WhatIf
    if(($nullable.Releases.Version -join ',') -cne ($preview.Releases.Version -join ',') -or $nullable.Created.Count){throw 'NullablePreviewDiffersFromNextPreview'}
    $local=& $operator -WorkspaceRoot $fixture -Module Core -Version 2.3.4 -Preview 1 -NoCommit -NoPush -Confirm:$false
    if($local.Created.Count -ne 1 -or $local.Committed -or $local.Pushed -or !$local.RemoteChecked){throw 'ReleaseNoCommitNoPushContractChanged'}
    $rejected=$false;try{$null=& $operator -WorkspaceRoot $fixture -Module Core -Version 2.3.4-preview1 -NoCommit -NoPush -Confirm:$false}catch{$rejected=$_.Exception.Message -like 'ReleaseTagAlreadyExists:*'}
    if(!$rejected){throw 'ExistingLocalReleaseTagAccepted'}
    foreach($tag in @('FrenchExDev2.QuietCli.Core.PoSh/v2.3.4-preview2','FrenchExDev2.QuietCli.Git.PoSh/v2.3.4-preview5')){
        $null=Invoke-ReleaseFixtureGit @('tag',$tag)
        $null=Invoke-ReleaseFixtureGit @('push','origin',('refs/tags/'+$tag))
        $null=Invoke-ReleaseFixtureGit @('tag','--delete',$tag)
    }
    $rejected=$false;try{$null=& $operator -WorkspaceRoot $fixture -Module Core -Version 2.3.4-preview2 -NoPush -Confirm:$false}catch{$rejected=$_.Exception.Message -like 'ReleaseTagAlreadyExists:*'}
    if(!$rejected -or (Invoke-ReleaseFixtureGit @('rev-parse','HEAD')).Value -cne $before){throw 'ExistingRemoteReleaseTagAccepted'}
    $git={param($arguments) Invoke-ReleaseFixtureGit -Arguments $arguments}
    $commit={
        param($root,$message,$paths)
        $observed.Commits++
        $null=Invoke-ReleaseFixtureGit (@('add','--')+$paths)
        $null=Invoke-ReleaseFixtureGit @('commit','--quiet','--no-verify','-m',$message)
    }
    $push={param($root,$remoteName,$branch) $observed.Pushes++;$null=Invoke-ReleaseFixtureGit @('push',$remoteName,("HEAD:refs/heads/"+$branch))}
    $next=Invoke-QuietModuleRelease -WorkspaceRoot $fixture -Module Core,Git -Version 2.3.4 -NextPreview -NoPush -GitCommand $git -CommitCommand $commit -PushCommand $push -Confirm:$false
    if(!$next.Committed -or $next.Created.Count -ne 2 -or $next.Pushed -or $observed.Commits -ne 1 -or $observed.Pushes -or $next.Releases[0].Version -cne '2.3.4-preview3' -or $next.Releases[1].Version -cne '2.3.4-preview6'){throw 'IndependentNextPreviewCommitFailed'}
    foreach($tag in $next.Created){if((Invoke-ReleaseFixtureGit @('cat-file','-t',('refs/tags/'+$tag))).Value -cne 'tag'){throw 'ReleaseTagNotAnnotated'}}
    $published=Invoke-QuietModuleRelease -WorkspaceRoot $fixture -Module Core -Version 2.3.4 -Preview 4 -PreviewSpecified -GitCommand $git -CommitCommand $commit -PushCommand $push -Confirm:$false
    if(!$published.Pushed -or !$published.BranchPushed -or $observed.Pushes -ne 1 -or $observed.Commits -ne 2){throw 'OwnedReleasePushFailed'}
    $remoteValue=(Invoke-ReleaseFixtureGit @('ls-remote','origin',('refs/tags/'+$published.Created[0]+'^{}'))).Value
    if(($remoteValue -split "`t")[0] -cne $published.Revision){throw 'RemoteReleaseCommitMismatch'}
    $rejected=$false;try{$null=& $operator -WorkspaceRoot $fixture -Module Git -Version 2.3.4-preview99 -NoCommit -NoPush -Confirm:$false}catch{$rejected=$_.Exception.Message -ceq 'ReleaseNoCommitRequiresCommittedVersions'}
    if(!$rejected){throw 'NoCommitTaggedUncommittedVersion'}
    $rejected=$false;try{$null=& $operator -WorkspaceRoot $fixture -Module Vagrant -Version 2.3.4 -NextPreview -NoPush -Confirm:$false}catch{$rejected=$_.Exception.Message -like 'GalleryReleaseModuleNotPublishable:*'}
    if(!$rejected){throw 'DisabledCompanionReleaseAccepted'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'release-tags-campaign.json') @{Seed=611111;PreviewProperties=128;OwnedCommits=$observed.Commits;OwnedBranchPushes=$observed.Pushes;LocalCollisionRejected=$true;RemoteCollisionRejected=$true;WhatIfNoEffects=$true;DynamicTargets=3;ExternalPublication=$false}
}
