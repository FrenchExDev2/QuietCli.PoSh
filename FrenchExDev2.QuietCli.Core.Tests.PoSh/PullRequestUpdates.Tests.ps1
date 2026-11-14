function Test-QuietPullRequestUpdates {
    <#
    .SYNOPSIS
    Checks PR update previews, selected-remote routing, checkpoint identity and duplicate suppression offline.
    .PARAMETER WorkspaceRoot
    Checkout providing the real update library.
    .PARAMETER RunDirectory
    Owned report directory; native commands and GitHub mutations are replaced by a scoped adapter.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/PullRequestUpdates.psm1) -DisableNameChecking -ErrorAction Stop
    & (Get-Module PullRequestUpdates) {
    param($WorkspaceRoot,$RunDirectory)
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
    $fixture=@{Calls=0;Comments=0;Edits=0;Description=$null;Url='git@github.com:FrenchExDev2/QuietCli.PoSh.git';Branch='fix/fixture';Head=('a'*40);Local=('a'*40);Duplicate=$false;Body=$null;Missing=$false;Ambiguous=$false;Fail=$false}
    function Invoke-CiProcess {
        <#
        .SYNOPSIS
        Replaces native Git/GitHub commands with bounded synthetic administrative responses.
        .PARAMETER FilePath
        Executable under test.
        .PARAMETER ArgumentList
        Exact administrative arguments.
        .PARAMETER WorkingDirectory
        Owned repository fixture path.
        .PARAMETER TimeoutSeconds
        Expected bounded timeout.
        .PARAMETER State
        Output accumulator owned by the production helper.
        .PARAMETER OnOutput
        Production output callback.
        #>
        param($FilePath,$ArgumentList,$WorkingDirectory,$TimeoutSeconds,$State,$OnOutput)
        $fixture.Calls++
        $text=if($FilePath -eq 'git'){
            if($ArgumentList[0] -eq 'remote'){$fixture.Url}else{$fixture.Local}
        }elseif($ArgumentList[1] -eq 'list'){
            if($fixture.Missing){'[]'}elseif($fixture.Ambiguous){'[{"number":2},{"number":3}]'}else{@(@{number=2;headRefName=$fixture.Branch})|ConvertTo-Json -AsArray -Compress}
        }elseif($ArgumentList[1] -eq 'edit'){
            if($ArgumentList[4] -cne 'FrenchExDev2/QuietCli.PoSh'){throw 'PrDescriptionUsedWrongRepository'}
            $fixture.Description=[IO.File]::ReadAllText($ArgumentList[6],[Text.UTF8Encoding]::new($false,$true));$fixture.Edits++
            'https://github.com/FrenchExDev2/QuietCli.PoSh/pull/2'
        }elseif($ArgumentList[1] -eq 'comment'){
            if($ArgumentList[4] -cne 'FrenchExDev2/QuietCli.PoSh'){throw 'PrUpdateUsedWrongRepository'}
            $fixture.Body=[IO.File]::ReadAllText($ArgumentList[6],[Text.UTF8Encoding]::new($false,$true));$fixture.Comments++
            'https://github.com/FrenchExDev2/QuietCli.PoSh/pull/2#issuecomment-fixture'
        }elseif($ArgumentList[-1] -eq 'comments'){
            @{comments=@($(if($fixture.Duplicate){@{body=('<!-- quietcli:push-update:'+$fixture.Head+' -->')}}))}|ConvertTo-Json -Depth 5 -Compress
        }else{@{headRefOid=$fixture.Head;commits=@(@{oid=$fixture.Head;messageHeadline='Synthetic Unicode é漢 change'})}|ConvertTo-Json -Depth 5 -Compress}
        & $OnOutput ([pscustomobject]@{Stream='stdout';Text=$text}) $State
        [pscustomobject]@{Outcome=$(if($fixture.Fail){'Failure'}else{'Success'})}
    }
    Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -WhatIf
    Send-QuietPullRequestUpdate $WorkspaceRoot origin develop -Confirm:$false
    if($fixture.Calls){throw 'PrUpdatePreviewOrUnrelatedBranchInvokedNativeTool'}
    $source=(Get-Command Send-QuietPullRequestUpdate).ScriptBlock.ToString()
    $anchor="if(`$Branch -cnotmatch '^(feature|fix)/'){return}"
    if(!$source.Contains($anchor)){throw 'PrBranchMutationAnchorMissing'}
    $mutant=[scriptblock]::Create($source.Replace($anchor,''))
    try{& $mutant $WorkspaceRoot origin develop -Confirm:$false}catch{}
    if(!$fixture.Calls){throw 'PrBranchGuardMutationSurvived'}
    $fixture.Calls=0
    $seed=20261110;$random=[Random]::new($seed)
    foreach($index in 1..16){
        $fixture.Branch=$(if($index%2){'fix/'}else{'feature/'})+'fixture-'+$random.Next()
        Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Confirm:$false
        if(!$fixture.Body.Contains('Synthetic Unicode é漢 change') -or !$fixture.Body.Contains($fixture.Head) -or !$fixture.Body.Contains('does not assert success')){throw 'PrCommitSummaryPropertyFailed'}
    }
    $count=$fixture.Comments;$fixture.Duplicate=$true
    Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Confirm:$false
    if($fixture.Comments -ne $count){throw 'PrDuplicateCheckpointCommented'}
    $fixture.Duplicate=$false;$fixture.Missing=$true
    Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Confirm:$false
    if($fixture.Comments -ne $count){throw 'PrUpdateCreatedMissingPr'}
    $fixture.Missing=$false;$fixture.Ambiguous=$true
    $rejected=$false;try{Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Confirm:$false}catch{$rejected=$_.Exception.Message -eq 'PullRequestUpdateAmbiguous'}
    if(!$rejected){throw 'PrAmbiguousTargetAccepted'}
    $fixture.Ambiguous=$false;$fixture.Local='b'*40
    $rejected=$false;try{Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Confirm:$false}catch{$rejected=$_.Exception.Message -eq 'PullRequestCheckpointChanged'}
    if(!$rejected){throw 'PrCheckpointRaceAccepted'}
    $fixture.Local=$fixture.Head
    $before=$fixture.Calls
    Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Description 'Preview description' -WhatIf
    if($fixture.Calls -ne $before -or $fixture.Edits){throw 'PrDescriptionPreviewInvokedTool'}
    $fixture.Duplicate=$true
    Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Description "Reviewed é漢 description`r`nValidated scope." -Confirm:$false
    if($fixture.Edits -ne 1 -or $fixture.Description -cne "Reviewed é漢 description`nValidated scope.`n"){throw 'PrDescriptionUnicodeOrLineEndingsChanged'}
    $fixture.Duplicate=$false
    Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Body "Reviewed details`nValidation: focused checks only." -Confirm:$false
    if(!$fixture.Body.Contains("Reviewed details`nValidation: focused checks only.")){throw 'PrReviewedBodyChanged'}
    $count=$fixture.Comments
    foreach($url in @('https://gitlab.com/owner/repo.git','https://github.com.evil.invalid/owner/repo.git','file:///local/repository')){
        $fixture.Url=$url;Send-QuietPullRequestUpdate $WorkspaceRoot origin $fixture.Branch -Confirm:$false
    }
    if($fixture.Comments -ne $count){throw 'NonGitHubRemoteCommented'}
    $fixture.Fail=$true;$rejected=$false
    try{$null=Invoke-QuietPullRequestTool $WorkspaceRoot gh @('pr','list')}catch{$rejected=$_.Exception.Message -like 'PullRequestMetadataUnavailable:*'}
    if(!$rejected){throw 'FailedPrMetadataAccepted'}
    Write-WorkspaceJson (Join-Path $RunDirectory pr-update-campaign.json) @{Seed=$seed;Properties=16;KilledMutants=1;Preview='No native commands';RemoteMutations=0;CheckpointRace='Rejected';Duplicate='Skipped'}
    } $WorkspaceRoot $RunDirectory
}
