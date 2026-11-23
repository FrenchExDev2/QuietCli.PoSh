#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name 'Merge-PullRequest'
}

Describe 'Invoke-QuietPublishPullRequest' {
    BeforeEach {
        $workspace=[IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))
        $null=New-QuietTestFile ([IO.Path]::Combine($workspace,'.github','pull_request_template.md')) @'
## Additional CI validation
<!-- quietcli-ci:begin -->
- [ ] Mutation <!-- ci:mutation -->
- [ ] ReadyToRun <!-- ci:readytorun -->
- [ ] Preview <!-- ci:preview -->
<!-- quietcli-ci:end -->
'@
        $script:trace=[Collections.Generic.List[string]]::new()
        $script:work='chore/scripts-ci'
        $script:checkout=$script:work
        $script:old='a'*40
        $script:head='b'*40
        $script:develop='c'*40
        $script:local=$script:old
        $script:remote=$script:old
        $script:existing=$false
        $script:body=''
        $script:newUrl=$null
        $script:listed='[{"number":12}]'
        $script:publishedChanges=@{}
        $script:existingChanges=@{}
        $script:workingPath=''
        $script:runState='Success'
        $script:dirty=''
        $script:writePlan=$true
        $script:planHead=$null
        $script:afterCommit=@{}
        $script:afterPush=@{}
        $script:afterWatch=@{}
        $script:failStep=''
        $script:watchId=42
        $script:ready=$true
        $script:pr='https://github.com/example/quiet/pull/12'
        $run=@{WorkspaceRoot=$workspace;Message="Deliver changes`n`nDetails";Body='Résumé';Footer='Validation locale';DiscoverySeconds=0;Confirm=$false}
        Mock Invoke-QuietPullRequestTool -ModuleName Merge-PullRequest {
            param($WorkspaceRoot,$FilePath,$ArgumentList)
            switch ("$FilePath $($ArgumentList[0])") {
                'git remote' {'https://github.com/example/quiet.git'}
                'git branch' {
                    ($ArgumentList -join ' ')|Should -BeExactly 'branch --show-current'
                    $script:checkout
                }
                'git status' {
                    ($ArgumentList -join ' ')|Should -BeExactly 'status --porcelain=v1 --untracked-files=normal'
                    $script:dirty
                }
                'git rev-parse' {
                    $ArgumentList[1]|Should -BeExactly '--verify'
                    if($ArgumentList[-1] -ceq 'refs/heads/develop'){$script:develop}
                    else{
                        $ArgumentList[-1]|Should -BeExactly 'HEAD'
                        if($script:checkout -ceq 'develop'){$script:develop}else{$script:local}
                    }
                }
                'git switch' {
                    ($ArgumentList -join ' ')|Should -BeExactly 'switch --no-guess --no-overwrite-ignore develop'
                    $script:checkout=$ArgumentList[-1]
                    $script:trace.Add('switch')
                }
                'git pull' {
                    if($script:failStep -ceq 'pull'){throw 'FixturePullFailure'}
                    $script:trace.Add('pull')
                }
                'gh api' {
                    $script:trace.Add('discover')
                    ConvertTo-Json -InputObject @(@{id=42;head_sha=$script:head;head_branch=$script:work;event='pull_request';pull_requests=@(12)}) -Compress
                }
                'gh pr' {
                    switch($ArgumentList[1]){
                        'list' {
                            ($ArgumentList -join ' ')|Should -BeExactly 'pr list --repo example/quiet --head chore/scripts-ci --base develop --state open --limit 2 --json number'
                            if($script:existing){$script:listed}else{'[]'}
                        }
                        'view' {
                            $conclusion=if($script:ready){'SUCCESS'}else{'FAILURE'}
                            $view=@{number=12;url=$script:pr;body=$script:body;headRefOid=$script:remote;headRefName=$script:work;baseRefName='develop'
                              state='OPEN';isCrossRepository=$false;isDraft=$false;statusCheckRollup=@(@{__typename='CheckRun';name='QuietCli required CI';status='COMPLETED';conclusion=$conclusion})}
                            $changes=if($script:remote -ceq $script:old){$script:existingChanges}else{$script:publishedChanges}
                            foreach($field in $changes.Keys){$view[$field]=$changes[$field]}
                            $view | ConvertTo-Json -Depth 5 -Compress
                        }
                        'edit' {
                            ($ArgumentList[0..5] -join ' ')|Should -BeExactly 'pr edit 12 --repo example/quiet --body-file'
                            if($script:failStep -ceq 'edit'){throw 'FixtureEditFailure'}
                            $script:trace.Add('edit')
                            $script:workingPath=$ArgumentList[-1]
                            $script:body=[IO.File]::ReadAllText($script:workingPath,[Text.Encoding]::UTF8)
                        }
                        default {throw 'Unexpected GitHub PR operation'}
                    }
                }
                default {throw ("Unexpected tool operation: "+($ArgumentList -join ' '))}
            }
        }
        Mock Invoke-QuietPullRequestScript -ModuleName Merge-PullRequest {
            param($Name,$Arguments)
            switch($Name){
                'Commit-Workspace.ps1' {
                    $Arguments.Message|Should -BeExactly "Deliver changes`n`nDetails"
                    $Arguments.Confirm|Should -BeFalse
                    $script:trace.Add('commit')
                    $script:local=$script:head
                    if($script:writePlan){
                        $planHead=if($script:planHead){$script:planHead}else{$script:head}
                        $null=New-QuietTestFile ([IO.Path]::Combine($Arguments.WorkspaceRoot,'artifacts','plan.md')) "Base: $script:old; candidate: $planHead."
                    }
                    foreach($key in $script:afterCommit.Keys){Set-Variable -Scope Script -Name $key -Value $script:afterCommit[$key]}
                }
                'Push-Workspace.ps1' {
                    $Arguments.Confirm|Should -BeFalse
                    $Arguments.Remote|Should -BeExactly 'origin'
                    $Arguments.Branch|Should -BeExactly $script:work
                    if($script:failStep -ceq 'push'){throw 'FixturePushFailure'}
                    $script:trace.Add('push')
                    $script:remote=$Arguments.ExpectedHead
                    foreach($key in $script:afterPush.Keys){Set-Variable -Scope Script -Name $key -Value $script:afterPush[$key]}
                }
                'New-PullRequest.ps1' {
                    $Arguments.Confirm|Should -BeFalse
                    $script:trace.Add('create')
                    $script:workingPath=$Arguments.BodyFile
                    [IO.File]::ReadAllBytes($script:workingPath)[0]|Should -Not -Be 0xEF
                    $script:body=[IO.File]::ReadAllText($script:workingPath,[Text.Encoding]::UTF8)
                    if($script:newUrl){$script:newUrl}else{$script:pr}
                }
                'Watch-GitHubRun.ps1' {
                    $Arguments.Confirm|Should -BeFalse
                    $Arguments.Repository|Should -BeExactly 'example/quiet'
                    $Arguments.RunId|Should -Be 42
                    $script:trace.Add('watch')
                    foreach($key in $script:afterWatch.Keys){Set-Variable -Scope Script -Name $key -Value $script:afterWatch[$key]}
                    [pscustomobject]@{State=$script:runState;RunId=$script:watchId}
                }
                default {throw 'Unexpected entry point'}
            }
        }
        Mock Assert-QuietPullRequestCiEvidence -ModuleName Merge-PullRequest {
            param($WorkspaceRoot,$Repository,$Number,$ExpectedHead,$CheckRollup)
            $CheckRollup[0].name|Should -BeExactly 'QuietCli required CI'
            $ExpectedHead|Should -BeExactly $script:head
            $Number|Should -Be 12
            $script:trace.Add('receipt')
        }
        Mock Write-Host -ModuleName Merge-PullRequest {}
    }

    It 'creates the PR with the explicit selections, monitors the pinned SHA and pulls develop' {
        $result=Invoke-QuietPublishPullRequest @run -Options @{mutation=$true;readytorun=$true}
        $script:trace.ToArray()|Should -BeExactly @('commit','push','create','switch','discover','watch','receipt','pull')
        $script:body|Should -BeExactly (@('Résumé','','## Additional CI validation','<!-- quietcli-ci:begin -->','- [x] Mutation <!-- ci:mutation -->','- [x] ReadyToRun <!-- ci:readytorun -->','- [ ] Preview <!-- ci:preview -->','<!-- quietcli-ci:end -->','','Validation locale','') -join "`n")
        Test-Path -LiteralPath $script:workingPath|Should -BeFalse
        $result.State|Should -BeExactly 'Success'
        $result.Url|Should -BeExactly $script:pr
        $result.Revision|Should -BeExactly $script:head
        $result.Develop|Should -BeExactly $script:develop
        $result.RunId|Should -Be 42
        $result.PullRequest|Should -Be 12
        $result.RunUrl|Should -BeExactly 'https://github.com/example/quiet/actions/runs/42'
        $result.Plan|Should -BeExactly ([IO.Path]::Combine($workspace,'artifacts','plan.md'))
        Should -Invoke Write-Host -ModuleName Merge-PullRequest -Exactly -Times 1 -ParameterFilter {$Object -ceq "Pull request $script:pr at $script:head"}
        Should -Invoke Write-Host -ModuleName Merge-PullRequest -Exactly -Times 1 -ParameterFilter {$Object -ceq 'Watching https://github.com/example/quiet/actions/runs/42'}
        Should -Invoke Invoke-QuietPullRequestScript -ModuleName Merge-PullRequest -Exactly -Times 1 -ParameterFilter {
            $Name -ceq 'New-PullRequest.ps1' -and $Arguments.Title -ceq 'Deliver changes' -and $Arguments.Head -ceq 'chore/scripts-ci'
        }
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName Merge-PullRequest -Exactly -Times 1 -ParameterFilter {
            $FilePath -ceq 'git' -and ($ArgumentList -join ' ') -ceq 'pull --ff-only --no-rebase --no-tags origin develop'
        }
    }

    It 'edits an existing description before push and preserves only the requested boxes' {
        $script:existing=$true
        $run.Body=@'
Details
<!-- quietcli-ci:begin -->
- [x] Mutation <!-- ci:mutation -->
- [ ] ReadyToRun <!-- ci:readytorun -->
- [x] Preview <!-- ci:preview -->
<!-- quietcli-ci:end -->
'@
        $null=Invoke-QuietPublishPullRequest @run -Options @{mutation=$false}
        $script:trace.ToArray()|Should -BeExactly @('commit','edit','push','switch','discover','watch','receipt','pull')
        $script:body|Should -Match '(?m)^- \[ \] Mutation '
        $script:body|Should -Match '(?m)^- \[x\] Preview '
    }

    It 'stops at <Phase> for human action and never pulls develop' -ForEach @(
        @{Phase='commit';MissingPlan=$true;Watch='Success';Required=$true;ExpectedBranch='chore/scripts-ci';Reason='WorkspacePullRequestPlanUnavailable'}
        @{Phase='watch CI';MissingPlan=$false;Watch='Failure';Required=$true;ExpectedBranch='develop';Reason='PullRequestWatchDidNotSucceed'}
        @{Phase='verify CI';MissingPlan=$false;Watch='Success';Required=$false;ExpectedBranch='develop';Reason='WorkspacePullRequestRequiredCiNotVerified'}
    ) {
        $script:writePlan=!$MissingPlan
        $script:runState=$Watch
        $script:ready=$Required
        {Invoke-QuietPublishPullRequest @run} | Should -Throw "*WorkspacePullRequestHumanActionRequired during $Phase*$Reason*"
        $script:checkout|Should -BeExactly $ExpectedBranch
        $script:trace|Should -Not -Contain 'pull'
        if($MissingPlan){$script:trace|Should -Not -Contain 'push'}
    }

    It 'rejects <Field> on the published PR before switching to develop' -ForEach @(
        @{Field='state';Value='CLOSED'}
        @{Field='isDraft';Value=$true}
        @{Field='headRefName';Value='chore/other'}
        @{Field='headRefOid';Value=('a'*40)}
        @{Field='body';Value='A concurrent edit'}
    ) {
        $script:publishedChanges[$Field]=$Value
        {Invoke-QuietPublishPullRequest @run} | Should -Throw '*during verify pull request*WorkspacePullRequestPublicationChanged*'
        $script:trace.ToArray()|Should -BeExactly @('commit','push','create')
    }

    It 'rejects <Field> on the existing PR before committing' -ForEach @(
        @{Field='state';Value='CLOSED'}
        @{Field='isDraft';Value=$true}
        @{Field='headRefName';Value='chore/other'}
    ) {
        $script:existing=$true
        $script:existingChanges[$Field]=$Value
        {Invoke-QuietPublishPullRequest @run} | Should -Throw '*during preflight*WorkspacePullRequestNotReady*'
        $script:trace.Count|Should -Be 0
    }

    It 'refuses ambiguous PRs, unknown options and a description past the API limit before committing' {
        {Invoke-QuietPublishPullRequest @run -Options @{misspelled=$true}} | Should -Throw '*PullRequestCiChecklistUnknownOption*'
        {Invoke-QuietPublishPullRequest @run -Options @{misspelled=$false}} | Should -Throw '*PullRequestCiChecklistUnknownOption*'
        $original=$run.Body
        $run.Body='x'*60001
        {Invoke-QuietPublishPullRequest @run} | Should -Throw '*PullRequestDescriptionInvalid*'
        $run.Body=$original
        $script:existing=$true
        $script:listed='[{"number":12},{"number":13}]'
        {Invoke-QuietPublishPullRequest @run} | Should -Throw '*WorkspacePullRequestAmbiguous*'
        $script:trace.Count|Should -Be 0
    }

    It 'normalizes CRLF and bare CR while preserving the supplied Markdown text' {
        $run.Body="First`r`nSecond`rThird"
        $null=Invoke-QuietPublishPullRequest @run -Options @{preview=$true}
        $script:body.StartsWith("First`nSecond`nThird`n`n",[StringComparison]::Ordinal)|Should -BeTrue
        $script:body|Should -Match '(?m)^- \[x\] Preview '
    }

    It 'accepts the exact description limit' {
        $null=Invoke-QuietPublishPullRequest @run
        $length=$run.Body.Length+(60000-$script:body.Length)
        $script:checkout=$script:work
        $script:local=$script:old
        $script:remote=$script:old
        $run.Body='x'*$length
        $null=Invoke-QuietPublishPullRequest @run
        $script:body.Length|Should -Be 60000
    }

    It 'rejects an invalid UTF-8 template before contacting Git' {
        $path=[IO.Path]::Combine($workspace,'.github','pull_request_template.md')
        $bytes=[byte[]](@(0xC3,0x28)+[IO.File]::ReadAllBytes($path))
        [IO.File]::WriteAllBytes($path,$bytes)
        {Invoke-QuietPublishPullRequest @run}|Should -Throw '*during preflight*'
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName Merge-PullRequest -Exactly -Times 0
    }

    It 'rejects malformed creation URL <Url> and cleans up its Markdown file' -ForEach @(
        @{Url='https://github.com/example/other/pull/12'}
        @{Url='redirected to https://github.com/example/quiet/pull/12'}
    ) {
        $script:newUrl=$Url
        {Invoke-QuietPublishPullRequest @run -Title 'Explicit title'} | Should -Throw '*during create pull request*WorkspacePullRequestCreationNotVerified*'
        $script:trace.ToArray()|Should -BeExactly @('commit','push','create')
        Test-Path -LiteralPath $script:workingPath|Should -BeFalse
        Should -Invoke Invoke-QuietPullRequestScript -ModuleName Merge-PullRequest -Exactly -Times 1 -ParameterFilter {
            $Name -ceq 'New-PullRequest.ps1' -and $Arguments.Title -ceq 'Explicit title'
        }
    }

    It 'requires a real new commit with a clean source checkout' -ForEach @(
        @{Key='local';Value='invalid'}
        @{Key='local';Value=('a'*40)}
        @{Key='checkout';Value='chore/other'}
        @{Key='dirty';Value='?? new.txt'}
    ) {
        $script:afterCommit[$Key]=$Value
        {Invoke-QuietPublishPullRequest @run}|Should -Throw '*during commit*WorkspacePullRequestCommitNotVerified*'
        $script:trace.ToArray()|Should -BeExactly @('commit')
    }

    It 'refuses a stale plan and includes the branch and revision in the error' {
        $script:planHead=$script:old
        {Invoke-QuietPublishPullRequest @run}|Should -Throw "*during commit ($script:work $script:head). WorkspacePullRequestPlanUnavailable"
        $script:trace.ToArray()|Should -BeExactly @('commit')
    }

    It 'stops before <Phase> if the local checkout changes while remote work is in progress' -ForEach @(
        @{Phase='switch to develop';Key='checkout';Value='chore/other'}
        @{Phase='switch to develop';Key='dirty';Value='?? new.txt'}
        @{Phase='pull develop';Key='checkout';Value='chore/other'}
        @{Phase='pull develop';Key='dirty';Value='?? new.txt'}
    ) {
        $changes=if($Phase -ceq 'switch to develop'){$script:afterPush}else{$script:afterWatch}
        $changes[$Key]=$Value
        {Invoke-QuietPublishPullRequest @run}|Should -Throw "*during $Phase*WorkspacePullRequestCheckoutChanged*"
        $script:trace|Should -Not -Contain 'pull'
        if($Phase -ceq 'switch to develop'){$script:trace|Should -Not -Contain 'switch'}
    }

    It 'reports failure at <Phase> with its original cause' -ForEach @(
        @{Phase='update pull request';Failure='edit';Reason='FixtureEditFailure'}
        @{Phase='push';Failure='push';Reason='FixturePushFailure'}
        @{Phase='pull develop';Failure='pull';Reason='FixturePullFailure'}
    ) {
        $script:failStep=$Failure
        $script:existing=$true
        {Invoke-QuietPublishPullRequest @run}|Should -Throw "*during $Phase*$Reason*"
        $script:trace|Should -Not -Contain 'pull'
    }

    It 'rejects a zero run identifier before watching' {
        Mock Find-QuietPullRequestRun -ModuleName Merge-PullRequest {0}
        {Invoke-QuietPublishPullRequest @run}|Should -Throw '*during watch CI*PullRequestRunIdentityInvalid*'
        $script:trace|Should -Not -Contain 'watch'
    }

    It 'rejects a successful watcher for a different run and reports the published references' {
        $script:watchId=43
        {Invoke-QuietPublishPullRequest @run}|Should -Throw "*($script:work $script:head $script:pr https://github.com/example/quiet/actions/runs/42). PullRequestWatchDidNotSucceed"
        $script:trace|Should -Not -Contain 'pull'
    }

    It 'has a no-effect preview even with a malformed checkout path' {
        $transcript=[IO.Path]::Combine($workspace,'preview.txt')
        $null=Start-Transcript -LiteralPath $transcript
        try {Invoke-QuietPublishPullRequest @run -WhatIf} finally {$null=Stop-Transcript}
        [IO.File]::ReadAllText($transcript,[Text.Encoding]::UTF8)|Should -Match 'Publish and monitor the work branch'
        Should -Invoke Invoke-QuietPullRequestScript -ModuleName Merge-PullRequest -Exactly -Times 0
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName Merge-PullRequest -Exactly -Times 0
    }
}
