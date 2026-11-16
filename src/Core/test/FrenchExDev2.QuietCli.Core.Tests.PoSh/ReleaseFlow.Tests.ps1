function Test-QuietReleaseFlow {
    <#
    .SYNOPSIS
    Checks the release facade end to end against an owned repository, a private bare remote and a scripted GitHub double, including stops.
    .PARAMETER WorkspaceRoot
    Source checkout providing the release flow library.
    .PARAMETER RunDirectory
    Owned test directory outside the checkout.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $library=[IO.Path]::Combine($WorkspaceRoot,'scripts/lib/ReleaseFlow.psm1')
    Import-Module $library -Force -DisableNameChecking -ErrorAction Stop
    $root=[IO.Path]::Combine($RunDirectory,'release-flow')
    $world=[hashtable]::Synchronized(@{Fixture=[IO.Path]::Combine($root,'work');Remote=[IO.Path]::Combine($root,'remote.git');Template=[IO.Path]::Combine($root,'empty-template')
        Repository='fixture/repo';Next=1;PullRequests=[hashtable]::Synchronized(@{});Calls=[Collections.ArrayList]::Synchronized([Collections.ArrayList]::new());Pushes=[Collections.ArrayList]::Synchronized([Collections.ArrayList]::new())
        Check='SUCCESS';PendingViews=0;CloseOnView=$false;ForeignHead=$null;HangMerge=$false;MergeSent=$false;Merges=0;Views=0;Commits=0;LastReceipt=$null;Started=$false;ChildError=$null})
    foreach($directory in @($world.Fixture,$world.Remote,$world.Template)){[void][IO.Directory]::CreateDirectory($directory)}

    function Invoke-ReleaseFlowFixtureGit {
        <#
        .SYNOPSIS
        Executes exact Git arguments against an owned fixture repository with bounded metadata.
        .PARAMETER World
        Synchronized fixture state.
        .PARAMETER Arguments
        Native Git arguments.
        .PARAMETER Directory
        Owned repository; the working fixture by default.
        #>
        param([hashtable]$World,[string[]]$Arguments,[string]$Directory)
        if(!$Directory){$Directory=$World.Fixture}
        $r=quiet -AsObject -C release-flow-fixture -WorkingDirectory $Directory -RecordDelimiter "`n" -Data @{Value='';HasOutput=$false;Lines=[Collections.Generic.List[string]]::new()} -Output {
            param($e,$n)
            if($e.Stream -ne 'stdout' -or !$e.Text.Trim()){return}
            $line=$e.Text.TrimEnd([char[]]"`r`n")
            if($n.Data.Lines.Count -ge 2000 -or $line.Length -gt 4096){throw 'ReleaseFlowFixtureMetadataOverflow'}
            if(!$n.Data.HasOutput){$n.Data.Value=$line}
            $n.Data.HasOutput=$true;$n.Data.Lines.Add($line)
        } -Complete {param($n)$n.Data} -FilePath git -ArgumentList $Arguments
        if($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis -or $r.Error.Count){throw ('ReleaseFlowFixtureGitFailed: '+($Arguments -join ' '))}
        $r.Data
    }

    function Complete-ReleaseFlowFakeMerge {
        <#
        .SYNOPSIS
        Merges one fake pull request with a real merge commit created in the bare remote, as GitHub would.
        .PARAMETER World
        Synchronized fixture state.
        .PARAMETER Number
        Fake pull request number.
        #>
        param([hashtable]$World,[int]$Number)
        $pr=$World.PullRequests[[string]$Number]
        $base=(Invoke-ReleaseFlowFixtureGit -World $World -Directory $World.Remote -Arguments @('rev-parse','--verify','refs/heads/develop')).Value
        # The fixture merges immediately, so the release head's tree is the merge result.
        if((Invoke-ReleaseFlowFixtureGit -World $World -Directory $World.Remote -Arguments @('rev-parse','--verify',($pr.HeadOid+'^1'))).Value -cne $base){throw 'FakeGitHubMergeRequiresUnmovedBase'}
        $merge=(Invoke-ReleaseFlowFixtureGit -World $World -Directory $World.Remote -Arguments @('commit-tree','-p',$base,'-p',$pr.HeadOid,'-m',('Merge pull request #'+$Number),($pr.HeadOid+'^{tree}'))).Value
        $null=Invoke-ReleaseFlowFixtureGit -World $World -Directory $World.Remote -Arguments @('update-ref','refs/heads/develop',$merge,$base)
        $pr.State='MERGED';$pr.MergeCommit=$merge
        $merge
    }

    function Invoke-ReleaseFlowFakeGitHub {
        <#
        .SYNOPSIS
        Scripted GitHub CLI double for pr list, create, view and merge, enforcing the required check like branch protection.
        .PARAMETER World
        Synchronized fixture state, shared with stopped runspaces.
        .PARAMETER Arguments
        Exact gh arguments produced by the release flow.
        #>
        param([hashtable]$World,[string[]]$Arguments)
        [void]$World.Calls.Add(($Arguments -join ' '))
        if($Arguments -ccontains '--admin' -or $Arguments -ccontains '--auto' -or $Arguments -ccontains '--squash' -or $Arguments -ccontains '--rebase'){throw 'FakeGitHubUnsafeMergeRequested'}
        $index=[array]::IndexOf($Arguments,'--repo')
        if($Arguments[0] -cne 'pr' -or $index -lt 0 -or $Arguments[$index+1] -cne $World.Repository){throw 'FakeGitHubWrongRepository'}
        $value={param($name) $position=[array]::IndexOf($Arguments,$name);if($position -lt 0){throw ('FakeGitHubMissingArgument: '+$name)};$Arguments[$position+1]}
        switch -CaseSensitive ($Arguments[1]){
            'list'{
                $head=& $value '--head'
                ConvertTo-Json -AsArray -Compress -InputObject @($World.PullRequests.Values|Where-Object {$_.Head -ceq $head}|ForEach-Object {[ordered]@{number=$_.Number;state=$_.State;headRefName=$_.Head;url=$_.Url}})
            }
            'create'{
                $head=& $value '--head'
                if((& $value '--base') -cne 'develop'){throw 'FakeGitHubWrongBase'}
                $bodyPath=& $value '--body-file'
                $oid=(Invoke-ReleaseFlowFixtureGit -World $World -Directory $World.Remote -Arguments @('rev-parse','--verify',('refs/heads/'+$head))).Value
                $number=[int]$World.Next;$World.Next=$number+1
                $World.LastReceipt=[IO.Path]::Combine([IO.Path]::GetDirectoryName($bodyPath),'release-flow.json')
                $World.PullRequests[[string]$number]=@{Number=$number;Head=$head;HeadOid=$oid;State='OPEN';MergeCommit=$null;Views=0;Title=(& $value '--title');Body=[IO.File]::ReadAllText($bodyPath,[Text.UTF8Encoding]::new($false,$true));Url=('https://github.com/fixture/repo/pull/'+$number)}
                $World.PullRequests[[string]$number].Url
            }
            'view'{
                $pr=$World.PullRequests[$Arguments[2]]
                $pr.Views++;$World.Views=[int]$World.Views+1
                if($World.CloseOnView -and $pr.State -ceq 'OPEN'){$pr.State='CLOSED'}
                if($World.ForeignHead){$pr.HeadOid=$World.ForeignHead}
                $status='COMPLETED';$conclusion=[string]$World.Check
                if($World.Check -ceq 'PENDING' -or $pr.Views -le $World.PendingViews){$status='IN_PROGRESS';$conclusion=''}
                $rollup=@([ordered]@{__typename='CheckRun';name='Optional fixture check';status='COMPLETED';conclusion='FAILURE'},[ordered]@{__typename='CheckRun';name='QuietCli required CI';status=$status;conclusion=$conclusion})
                [ordered]@{state=$pr.State;headRefOid=$pr.HeadOid;mergeCommit=$(if($pr.MergeCommit){[ordered]@{oid=$pr.MergeCommit}}else{$null});statusCheckRollup=$rollup;url=$pr.Url}|ConvertTo-Json -Depth 5 -Compress
            }
            'merge'{
                $pr=$World.PullRequests[$Arguments[2]]
                if($Arguments -cnotcontains '--merge'){throw 'FakeGitHubMergeCommitNotRequested'}
                if((& $value '--match-head-commit') -cne $pr.HeadOid){throw 'FakeGitHubHeadMismatch'}
                if($pr.State -cne 'OPEN' -or $World.Check -cne 'SUCCESS' -or $pr.Views -le $World.PendingViews){throw 'FakeGitHubProtectionRefusedMerge'}
                $World.Merges=[int]$World.Merges+1
                $null=Complete-ReleaseFlowFakeMerge -World $World -Number $pr.Number
                if($World.HangMerge){
                    # GitHub accepted the merge but the response never arrives: only a stop ends this call.
                    $World.MergeSent=$true
                    for($slice=0;$slice -lt 240;$slice++){[Threading.Tasks.Task]::Delay(250).GetAwaiter().GetResult()}
                    throw 'FakeGitHubMergeHangExpired'
                }
                ''
            }
            default{throw 'FakeGitHubUnexpectedCommand'}
        }
    }

    $fixtureGit={param([string[]]$Arguments,[string]$Directory) Invoke-ReleaseFlowFixtureGit -World $world -Arguments $Arguments -Directory $Directory}
    $null=& $fixtureGit @('init','--bare','--quiet',('--template='+$world.Template)) $world.Remote
    $null=& $fixtureGit @('init','--quiet','--initial-branch=fix/original',('--template='+$world.Template))
    foreach($directory in @($world.Fixture,$world.Remote)){
        foreach($setting in @(@('core.hooksPath',$world.Template),@('user.name','Release flow fixture'),@('user.email','release-flow@example.invalid'),@('commit.gpgSign','false'),@('tag.gpgSign','false'))){$null=& $fixtureGit (@('config')+$setting) $directory}
    }
    $null=& $fixtureGit @('remote','add','origin',$world.Remote)
    [IO.File]::WriteAllText([IO.Path]::Combine($world.Fixture,'.gitignore'),"artifacts/`n",[Text.UTF8Encoding]::new($false))
    foreach($component in @('Core','Git')){
        $name="FrenchExDev2.QuietCli.$component.PoSh";$directory=[IO.Path]::Combine($world.Fixture,$name)
        [void][IO.Directory]::CreateDirectory($directory)
        [IO.File]::WriteAllText([IO.Path]::Combine($directory,"$name.psm1"),"throw 'ReleaseFlowExecutedBusinessModule'`n",[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText([IO.Path]::Combine($directory,"$name.psd1"),"@{RootModule='$name.psm1';ModuleVersion='2.3.4';GUID='fb86bdbe-f964-461c-b144-a655e42df279';PrivateData=@{PSData=@{Prerelease='preview1'};QuietCli=@{Publishable=`$true}}}`n",[Text.UTF8Encoding]::new($false))
    }
    $null=& $fixtureGit @('add','--','.')
    $null=& $fixtureGit @('commit','--quiet','--no-verify','-m','Owned release flow fixture')
    $original=(& $fixtureGit @('rev-parse','HEAD')).Value
    $null=& $fixtureGit @('push','--quiet','origin',($original+':refs/heads/develop'))
    foreach($tag in @('Core.PoSh/v2.3.4-preview1','Core.PoSh/v2.3.4-preview2','Git.PoSh/v2.3.4-preview1','Git.PoSh/v2.3.4-preview5')){$null=& $fixtureGit @('tag',('FrenchExDev2.QuietCli.'+$tag),$original) $world.Remote}

    $git={param($arguments) Invoke-ReleaseFlowFixtureGit -World $world -Arguments $arguments}
    $commit={param($root,$message,$paths) $world.Commits=[int]$world.Commits+1;$null=Invoke-ReleaseFlowFixtureGit -World $world -Arguments (@('add','--')+$paths);$null=Invoke-ReleaseFlowFixtureGit -World $world -Arguments @('commit','--quiet','--no-verify','-m',$message)}
    $push={param($root,$remote,$branch) if($branch -cnotmatch '\Arelease/'){throw 'FixturePushOutsideReleaseFamily'};[void]$world.Pushes.Add($branch);$null=Invoke-ReleaseFlowFixtureGit -World $world -Arguments @('push','--quiet',$remote,('refs/heads/'+$branch+':refs/heads/'+$branch))}
    $gh={param($arguments) Invoke-ReleaseFlowFakeGitHub -World $world -Arguments $arguments}
    $flow={param([hashtable]$Options) Invoke-QuietReleaseFlow -WorkspaceRoot $world.Fixture -GitCommand $git -CommitCommand $commit -PushBranchCommand $push -GitHubCommand $gh -Confirm:$false @Options 6>$null}
    $start=@{Module=@('Core','Git');Version='2.3.4';NextPreview=$true;Repository='fixture/repo';PollSeconds=0;TimeoutMinutes=1}
    $with={param([hashtable]$Extra) $options=$start.Clone();foreach($key in $Extra.Keys){$options[$key]=$Extra[$key]};$options}
    $expectFailure={
        param([hashtable]$Options,[string]$Pattern,[string]$Label)
        $failure=$null
        try{$null=& $flow $Options}catch{$failure=$_}
        if(!$failure -or $failure.Exception.Message -notlike $Pattern){throw ($Label+': '+$(if($failure){$failure.Exception.Message}else{'accepted'}))}
        [string]$failure.Exception.Data['ReleaseFlowReceipt']
    }
    $assertRestored={
        param([string]$Label)
        if((& $fixtureGit @('rev-parse','--abbrev-ref','HEAD')).Value -cne 'fix/original' -or (& $fixtureGit @('rev-parse','HEAD')).Value -cne $original -or (& $fixtureGit @('status','--porcelain')).HasOutput){throw ('ReleaseFlowOriginalBranchNotRestored: '+$Label)}
    }
    $remoteDevelop={(& $fixtureGit @('rev-parse','--verify','refs/heads/develop') $world.Remote).Value}
    $peeled={param([string]$Tag) ((& $fixtureGit @('ls-remote','origin',('refs/tags/'+$Tag+'^{}'))).Value -split "`t")[0]}
    $assertTagged={
        param([object]$Result,[string[]]$Expected,[string]$Label)
        if(!$Result.Completed -or (@($Result.Tags) -join ',') -cne ($Expected -join ',') -or $Result.MergeCommit -cne (& $remoteDevelop)){throw ('ReleaseFlowTagsMissing: '+$Label)}
        foreach($tag in $Expected){
            if((& $peeled $tag) -cne $Result.MergeCommit -or (& $fixtureGit @('cat-file','-t',('refs/tags/'+$tag))).Value -cne 'tag'){throw ('ReleaseFlowTagNotOnMergeCommit: '+$Label+' '+$tag)}
        }
        & $assertRestored $Label
    }
    $tags={param([int]$Core,[int]$GitPreview) @(('FrenchExDev2.QuietCli.Core.PoSh/v2.3.4-preview'+$Core),('FrenchExDev2.QuietCli.Git.PoSh/v2.3.4-preview'+$GitPreview))}

    # Pure decisions: seeded property against an independent oracle.
    $seed=20261115;$random=[Random]::new($seed);$properties=0
    $release='c'*40;$required='QuietCli required CI'
    foreach($index in 1..512){
        $prState=@('OPEN','OPEN','MERGED','CLOSED')[$random.Next(4)]
        $head=if($random.Next(5)){$release}else{'d'*40}
        $oid=@($null,('e'*40),'not-a-commit')[$random.Next(3)]
        $merge=[bool]$random.Next(2)
        $entries=@(foreach($entry in 1..$random.Next(4)){
            $name=if($random.Next(3)){$required}else{'Optional check'}
            if($random.Next(2)){[pscustomobject]@{__typename='CheckRun';name=$name;status=@('COMPLETED','COMPLETED','IN_PROGRESS','QUEUED')[$random.Next(4)];conclusion=@('SUCCESS','SUCCESS','FAILURE','CANCELLED','SKIPPED','')[$random.Next(6)]}}
            else{[pscustomobject]@{__typename='StatusContext';context=$name;state=@('SUCCESS','SUCCESS','PENDING','EXPECTED','FAILURE','ERROR')[$random.Next(6)]}}
        })
        $view=[pscustomobject]@{state=$prState;headRefOid=$head;mergeCommit=$(if($oid){[pscustomobject]@{oid=$oid}}else{$null});statusCheckRollup=$entries}
        $relevant=@($entries|Where-Object {($_.PSObject.Properties['name'] -and $_.name -ceq $required) -or ($_.PSObject.Properties['context'] -and $_.context -ceq $required)})
        $failing=@($relevant|Where-Object {if($_.__typename -ceq 'StatusContext'){$_.state -cnotin @('SUCCESS','PENDING','EXPECTED')}else{$_.status -ceq 'COMPLETED' -and $_.conclusion -cne 'SUCCESS'}})
        $waiting=@($relevant|Where-Object {if($_.__typename -ceq 'StatusContext'){$_.state -cin @('PENDING','EXPECTED')}else{$_.status -cne 'COMPLETED'}})
        $check=if(!$relevant.Count){'Pending'}elseif($failing.Count){'Failure'}elseif($waiting.Count){'Pending'}else{'Success'}
        $expected=if($prState -ceq 'CLOSED' -or $head -cne $release){'Fail'}elseif($prState -ceq 'MERGED'){if($oid -ceq ('e'*40)){'Tag'}else{'Wait'}}elseif($check -ceq 'Failure'){'Fail'}elseif($check -ceq 'Success' -and $merge){'Merge'}else{'Wait'}
        $decision=Get-QuietReleasePullRequestDecision -View $view -CommitRevision $release -RequiredCheck $required -Merge:$merge
        if($decision.Action -cne $expected){throw ('ReleaseFlowDecisionPropertyFailed: seed '+$seed+' case '+$index+' expected '+$expected+' got '+$decision.Action)}
        if($decision.Action -ceq 'Merge' -and ($prState -cne 'OPEN' -or $head -cne $release -or $check -cne 'Success' -or !$merge)){throw 'ReleaseFlowUnsafeMergeDecision'}
        $properties++
    }
    $mutantLibrary=[IO.Path]::Combine($root,'mutants/lib')
    Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib')) $mutantLibrary -Recurse
    $source=[IO.File]::ReadAllText($library,[Text.UTF8Encoding]::new($false,$true))
    $newMutant={
        param([string]$Name,[string]$Anchor,[string]$Replacement,[switch]$Regex)
        if($Regex){if(![regex]::IsMatch($source,$Anchor)){throw ('ReleaseFlowMutantAnchorInvalid: '+$Name)};$text=[regex]::Replace($source,$Anchor,$Replacement)}
        else{if(!$source.Contains($Anchor)){throw ('ReleaseFlowMutantAnchorInvalid: '+$Name)};$text=$source.Replace($Anchor,$Replacement)}
        $path=[IO.Path]::Combine($mutantLibrary,$Name+'.psm1')
        [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
        $path
    }
    $pendingView=[pscustomobject]@{state='OPEN';headRefOid=$release;mergeCommit=$null;statusCheckRollup=@([pscustomobject]@{__typename='CheckRun';name=$required;status='IN_PROGRESS';conclusion=''})}
    $foreignView=[pscustomobject]@{state='OPEN';headRefOid=('d'*40);mergeCommit=$null;statusCheckRollup=@([pscustomobject]@{__typename='CheckRun';name=$required;status='COMPLETED';conclusion='SUCCESS'})}
    $killed=0
    foreach($mutant in @(
        @{Name='ReleaseFlowGreenGuardMutant';Anchor="if(`$check -ceq 'Success' -and `$Merge)";Replacement='if($Merge)';View=$pendingView},
        @{Name='ReleaseFlowHeadGuardMutant';Anchor='if([string]$View.headRefOid -cne $CommitRevision)';Replacement='if($false)';View=$foreignView}
    )){
        if((Get-QuietReleasePullRequestDecision -View $mutant.View -CommitRevision $release -RequiredCheck $required -Merge).Action -ceq 'Merge'){throw ('ReleaseFlowCounterexampleMerged: '+$mutant.Name)}
        $module=Import-Module (& $newMutant $mutant.Name $mutant.Anchor $mutant.Replacement) -PassThru -DisableNameChecking -Prefix $mutant.Name
        try{$action=& $module {param($view,$revision,$check) (Get-QuietReleasePullRequestDecision -View $view -CommitRevision $revision -RequiredCheck $check -Merge).Action} $mutant.View $release $required}
        finally{Remove-Module $module -Force}
        if($action -cne 'Merge'){throw ('ReleaseFlowMutantInvalid: '+$mutant.Name)}
        $killed++
    }

    # WhatIf: provisional local plan only.
    $preview=Invoke-QuietReleaseFlow -WorkspaceRoot $world.Fixture @start -Merge -GitCommand $git -CommitCommand $commit -PushBranchCommand $push -GitHubCommand $gh -WhatIf 6>$null
    if($preview.Receipt -or !$preview.Provisional -or $preview.Branch -cnotmatch '\Arelease/core-git-2\.3\.4-[0-9]{8}-[0-9]{6}-[0-9a-f]{6}\z' -or $world.Calls.Count -or $world.Pushes.Count -or $world.Commits -or
        @((& $fixtureGit @('for-each-ref','--format=%(refname)','refs/heads')).Lines).Count -ne 1 -or (& $fixtureGit @('status','--porcelain')).HasOutput -or [IO.Directory]::Exists([IO.Path]::Combine($world.Fixture,'artifacts'))){throw 'ReleaseFlowWhatIfProducedEffects'}
    & $assertRestored 'WhatIf'

    # Nominal: pending then green check, facade merge, tags on the merge commit, original branch restored.
    $world.PendingViews=1
    $base=& $remoteDevelop
    $nominal=& $flow ((& $with @{Merge=$true}))
    & $assertTagged $nominal (& $tags 3 6) 'Nominal'
    foreach($name in Get-QuietReleaseFlowPhaseNames){if($nominal.Phases[$name] -cne 'Confirmed'){throw ('ReleaseFlowPhaseNotConfirmed: '+$name)}}
    $parents=@(((& $fixtureGit @('rev-list','--parents','--max-count=1',$nominal.MergeCommit) $world.Remote).Value -split ' '))
    if($parents.Count -ne 3 -or $parents[1] -cne $base -or $parents[2] -cne $nominal.CommitRevision -or $world.Merges -ne 1 -or $world.Commits -ne 1){throw 'ReleaseFlowNotMergedWithMergeCommit'}
    if(@($world.Pushes).Count -ne 1 -or $world.Pushes[0] -cne $nominal.Branch -or @((& $fixtureGit @('ls-remote','--heads','origin')).Lines).Count -ne 2){throw 'ReleaseFlowPushedAnotherBranch'}
    if(@($world.Calls|Where-Object {$_ -clike 'pr merge *'}) -cne ('pr merge 1 --repo fixture/repo --merge --match-head-commit '+$nominal.CommitRevision)){throw 'ReleaseFlowMergeNotPinnedToHead'}
    $body=$world.PullRequests['1'].Body
    foreach($tag in & $tags 3 6){if(!$body.Contains($tag)){throw 'ReleaseFlowPullRequestBodyIncomplete'}}
    $receipt=Read-QuietReleaseFlowState -Path $world.LastReceipt
    if(!$receipt.Completed -or $receipt.Interrupted -or $receipt.Failure){throw 'ReleaseFlowCompletedReceiptInvalid'}
    $null=& $expectFailure @{Resume=$world.LastReceipt} 'ReleaseResumeAlreadyCompleted:*' 'ReleaseFlowCompletedReceiptResumed'

    # Red required check: no merge, failure recorded, branch restored.
    $world.PendingViews=0;$world.Check='FAILURE';$develop=& $remoteDevelop
    $failedReceipt=& $expectFailure ((& $with @{Merge=$true})) 'ReleasePullRequestChecksFailed:*' 'ReleaseFlowRedCheckAccepted'
    $failed=Read-QuietReleaseFlowState -Path $failedReceipt
    if($world.Merges -ne 1 -or (& $remoteDevelop) -cne $develop -or $failed.Interrupted -or $failed.Phases.Merge -cne 'NotStarted' -or $failed.Phase -cne 'Merge' -or $failed.Failure -cnotlike 'ReleasePullRequestChecksFailed*'){throw 'ReleaseFlowRedCheckReceiptInvalid'}
    & $assertRestored 'RedCheck'

    # Inconsistent receipts are refused before any effect.
    $tampered=[IO.Path]::Combine($root,'tampered-release-flow.json')
    foreach($case in @(
        @{Pattern='ReleaseResumeReceiptInvalid';Edit={param($s) $s.Branch='develop'}},
        @{Pattern='ReleaseResumeReceiptInvalid: Tag';Edit={param($s) $s.Phases.Tag='Done'}},
        @{Pattern='ReleaseResumeWorkspaceMismatch';Edit={param($s) $s.WorkspaceRoot=[IO.Path]::Combine($root,'elsewhere')}},
        @{Pattern='ReleaseResumeStateConflict: Push';Edit={param($s) $s.Phases.Push='Unknown';$s.CommitRevision='0'*40}}
    )){
        $copy=Read-QuietReleaseFlowState -Path $failedReceipt
        & $case.Edit $copy
        [IO.File]::WriteAllText($tampered,($copy|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        $calls=$world.Calls.Count
        $null=& $expectFailure @{Resume=$tampered} $case.Pattern ('ReleaseFlowInconsistentReceiptAccepted: '+$case.Pattern)
        if($world.Calls.Count -ne $calls){throw 'ReleaseFlowInconsistentReceiptReachedGitHub'}
    }
    & $assertRestored 'Tampered'

    # Head replaced or pull request closed: refused without merge.
    $world.Check='SUCCESS';$world.ForeignHead='f'*40
    $null=& $expectFailure ((& $with @{Merge=$true})) 'ReleasePullRequestHeadChanged:*' 'ReleaseFlowForeignHeadAccepted'
    $world.ForeignHead=$null;$world.CloseOnView=$true
    $null=& $expectFailure ((& $with @{Merge=$true})) 'ReleasePullRequestClosed:*' 'ReleaseFlowClosedPullRequestAccepted'
    $world.CloseOnView=$false
    if($world.Merges -ne 1){throw 'ReleaseFlowRefusedPullRequestMerged'}
    & $assertRestored 'Refused'

    # Without Merge: one observation, timeout, manual merge, then Resume tags the manual merge commit.
    $manualReceipt=& $expectFailure ((& $with @{TimeoutMinutes=0})) 'ReleasePullRequestTimeout: AwaitingManualMerge*' 'ReleaseFlowWaitedWithoutTimeout'
    $manual=Read-QuietReleaseFlowState -Path $manualReceipt
    if($manual.Phases.Merge -cne 'NotStarted' -or $manual.MergeRequested -or $world.Merges -ne 1){throw 'ReleaseFlowMergedWithoutAuthorization'}
    & $assertRestored 'ManualTimeout'
    $null=Complete-ReleaseFlowFakeMerge -World $world -Number $manual.PullRequest.Number
    $resumed=& $flow @{Resume=$manualReceipt;PollSeconds=0;TimeoutMinutes=1}
    & $assertTagged $resumed (& $tags 4 7) 'ManualResume'
    if($world.Merges -ne 1){throw 'ReleaseFlowResumeMergedAgain'}

    # A tag created by someone else after the release commit is refused before tagging.
    $divergedReceipt=& $expectFailure ((& $with @{TimeoutMinutes=0})) 'ReleasePullRequestTimeout:*' 'ReleaseFlowDivergenceSetup'
    $diverged=Read-QuietReleaseFlowState -Path $divergedReceipt
    $foreign=(& $tags 5 8)[0]
    $null=& $fixtureGit @('tag',$foreign,(& $remoteDevelop)) $world.Remote
    $null=Complete-ReleaseFlowFakeMerge -World $world -Number $diverged.PullRequest.Number
    $null=& $expectFailure @{Resume=$divergedReceipt;PollSeconds=0;TimeoutMinutes=1} 'ReleaseVersionsDivergedSinceCommit:*' 'ReleaseFlowDivergenceAccepted'
    $diverged=Read-QuietReleaseFlowState -Path $divergedReceipt
    if($diverged.Phases.Tag -cne 'NotStarted' -or (& $peeled (& $tags 5 8)[1]) -or (& $fixtureGit @('tag','--list',(& $tags 5 8)[1])).HasOutput){throw 'ReleaseFlowDivergedTagsCreated'}
    & $assertRestored 'Divergence'

    # Versions already merged on develop: no pull request, the observed develop tip is tagged.
    $calls=$world.Calls.Count;$pushes=$world.Pushes.Count
    $direct=& $flow @{Module=@('Git');Version='2.3.4';Preview=8;PreviewSpecified=$true;Repository='fixture/repo';PollSeconds=0;TimeoutMinutes=1}
    & $assertTagged $direct @((& $tags 0 8)[1]) 'AlreadyMerged'
    if($world.Calls.Count -ne $calls -or $world.Pushes.Count -ne $pushes -or $direct.Phases.PullRequest -cne 'Skipped' -or $direct.Phases.Merge -cne 'Skipped'){throw 'ReleaseFlowAlreadyMergedOpenedPullRequest'}

    # Stops (the Ctrl+C path) in a dedicated runspace: PipelineStoppedException skips catch, finally records the receipt.
    $quietCommand=Get-Command quiet -ErrorAction Stop
    $quietModule=if($quietCommand.Module){$quietCommand.Module}else{$quietCommand.ResolvedCommand.Module}
    $coreManifest=[IO.Path]::Combine($quietModule.ModuleBase,$quietModule.Name+'.psd1')
    $definitions=@{}
    foreach($name in @('Invoke-ReleaseFlowFixtureGit','Complete-ReleaseFlowFakeMerge','Invoke-ReleaseFlowFakeGitHub')){$definitions[$name]=(Get-Item -LiteralPath ('function:'+$name)).ScriptBlock.ToString()}
    $callbacks=@{GitCommand=$git.ToString();CommitCommand=$commit.ToString();PushBranchCommand=$push.ToString();GitHubCommand=$gh.ToString()}
    $child='param($World,$Definitions,$Modules,$Callbacks,$Options)
        $ErrorActionPreference=''Stop''
        foreach($module in $Modules){Import-Module $module -DisableNameChecking -ErrorAction Stop}
        foreach($name in $Definitions.Keys){Set-Item -LiteralPath (''function:global:''+$name) -Value ([scriptblock]::Create($Definitions[$name]))}
        $bound=@{};foreach($name in $Callbacks.Keys){$bound[$name]=[scriptblock]::Create($Callbacks[$name])}
        $world=$World;$World.Started=$true
        try{$null=Invoke-QuietReleaseFlow @Options @bound -Confirm:$false 6>$null}catch{$World.ChildError=$_.Exception.Message}'
    $stopChild={
        param([string]$Library,[hashtable]$Options,[scriptblock]$Ready)
        $world.Started=$false;$world.ChildError=$null;$world.Views=0;$world.MergeSent=$false;$world.LastReceipt=$null
        $shell=[powershell]::Create()
        try{
            $null=$shell.AddScript($child).AddArgument($world).AddArgument($definitions).AddArgument(@($coreManifest,$Library)).AddArgument($callbacks).AddArgument(([hashtable]$Options.Clone()+@{WorkspaceRoot=$world.Fixture}))
            $async=$shell.BeginInvoke()
            $clock=[Diagnostics.Stopwatch]::StartNew()
            while(!(& $Ready) -and !$async.IsCompleted -and $clock.Elapsed.TotalSeconds -lt 120){[Threading.Tasks.Task]::Delay(50).GetAwaiter().GetResult()}
            if(!(& $Ready)){throw ('ReleaseFlowStopPointNotReached: '+$world.ChildError+' '+(@($shell.Streams.Error|ForEach-Object {$_.ToString()}) -join '; '))}
            [Threading.Tasks.Task]::Delay(300).GetAwaiter().GetResult()
            $latency=[Diagnostics.Stopwatch]::StartNew()
            $shell.Stop()
            $latency.Stop()
            if($shell.InvocationStateInfo.State -ne [Management.Automation.PSInvocationState]::Stopped -or $world.ChildError){throw ('ReleaseFlowChildNotStopped: '+$shell.InvocationStateInfo.State+' '+$world.ChildError)}
            [pscustomobject]@{Milliseconds=$latency.ElapsedMilliseconds;Receipt=[string]$world.LastReceipt}
        }finally{$shell.Dispose()}
    }
    $polling=(& $with @{Merge=$true;PollSeconds=10;TimeoutMinutes=5})
    $world.Check='PENDING'
    $stopped=& $stopChild $library $polling {$world.Views -ge 1}
    $interrupted=Read-QuietReleaseFlowState -Path $stopped.Receipt
    if($stopped.Milliseconds -ge 5000 -or !$interrupted.Interrupted -or $interrupted.Failure -or $interrupted.Phase -cne 'Merge' -or $interrupted.Phases.Merge -cne 'NotStarted' -or $interrupted.MergeRequested -or $world.Merges -ne 1){throw ('ReleaseFlowPollingStopReceiptInvalid: '+$stopped.Milliseconds+' ms')}
    & $assertRestored 'PollingStop'
    $world.Check='SUCCESS'
    $afterStop=& $flow @{Resume=$stopped.Receipt;PollSeconds=0;TimeoutMinutes=1}
    & $assertTagged $afterStop (& $tags 6 9) 'PollingStopResume'
    if($world.Merges -ne 2){throw 'ReleaseFlowPollingStopResumeNotMerged'}

    # Stop while GitHub has accepted the merge but not answered: Unknown, then a hard-kill receipt (Pending, checkout left on the release branch).
    $world.HangMerge=$true
    $hung=& $stopChild $library ((& $with @{Merge=$true})) {$world.MergeSent}
    $world.HangMerge=$false
    $uncertain=Read-QuietReleaseFlowState -Path $hung.Receipt
    if(!$uncertain.Interrupted -or $uncertain.Phases.Merge -cne 'Unknown' -or !$uncertain.MergeRequested -or $world.Merges -ne 3){throw 'ReleaseFlowMergeStopReceiptInvalid'}
    & $assertRestored 'MergeStop'
    $uncertain.Phases.Merge='Pending';$uncertain.Interrupted=$false
    [IO.File]::WriteAllText($hung.Receipt,($uncertain|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $null=& $fixtureGit @('switch','--quiet',$uncertain.Branch)
    $afterKill=& $flow @{Resume=$hung.Receipt;PollSeconds=0;TimeoutMinutes=1}
    & $assertTagged $afterKill (& $tags 7 10) 'HardKillResume'
    if($world.Merges -ne 3){throw 'ReleaseFlowUncertainMergeRepeated'}

    # Stop mutants: no receipt write in finally leaves a non-interrupted receipt; one long wait delays the stop.
    $finallyMutant=& $newMutant 'ReleaseFlowFinallyMutant' ([regex]::Escape('if(!$state.Failure){$state.Interrupted=$true}')+'\r?\n[ \t]*Write-QuietReleaseFlowState \$state') 'if(!$state.Failure){$state.Interrupted=$true}' -Regex
    $world.Check='PENDING'
    $mutantStop=& $stopChild $finallyMutant ((& $with @{Merge=$true;PollSeconds=2;TimeoutMinutes=5})) {$world.Views -ge 1}
    if((Read-QuietReleaseFlowState -Path $mutantStop.Receipt).Interrupted){throw 'ReleaseFlowFinallyMutantInvalid'}
    $killed++
    & $assertRestored 'FinallyMutant'
    $waitMutant=& $newMutant 'ReleaseFlowWaitMutant' 'for($slice=0;$slice -lt $Seconds;$slice++){[Threading.Tasks.Task]::Delay(1000).GetAwaiter().GetResult()}' '[Threading.Tasks.Task]::Delay($Seconds*1000).GetAwaiter().GetResult()'
    $slowStop=& $stopChild $waitMutant $polling {$world.Views -ge 1}
    if($slowStop.Milliseconds -lt 5000){throw ('ReleaseFlowWaitMutantInvalid: '+$slowStop.Milliseconds+' ms')}
    $killed++
    & $assertRestored 'WaitMutant'
    $world.Check='SUCCESS'

    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'release-flow-campaign.json')) @{Seed=$seed;DecisionProperties=$properties;KilledMutants=$killed;FacadeMerges=$world.Merges;BranchPushes=$world.Pushes.Count;PollingStopMilliseconds=$stopped.Milliseconds;WaitMutantStopMilliseconds=$slowStop.Milliseconds;Interruptions=4;ExternalPublication=$false;NetworkRequests=0}
}
