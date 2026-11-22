#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name 'Merge-PullRequest'
}

Describe 'Workspace pull request delivery' {
    BeforeEach {
        $script:head='a'*40
        $script:oldHead='b'*40
        $script:branch='feature/work'
        $script:repository='example/QuietCli'
        $script:localRef="refs/heads/$script:branch $script:head"
        $script:remoteRef=''
        $script:pushRepository=$script:repository
        $script:listedPrs='[{"number":7}]'
        $script:pushChangesHead=$true
        $script:viewReads=0
        $script:changeOnView=0
        $script:mergeError=$false
        $script:removeLocal=$true
        $script:dirty=''
        $script:autoDelete=$false
        $script:mergeAccepted=$true
        $script:watchState='Success'
        $script:watchRun=102
        $script:view=@{
            number=7;url="https://github.com/$script:repository/pull/7";headRefName=$script:branch;headRefOid=$script:head
            baseRefName='develop';isCrossRepository=$false;isDraft=$false;state='OPEN';mergeCommit=@{oid='c'*40}
            statusCheckRollup=@(@{__typename='CheckRun';name='QuietCli required CI';status='COMPLETED';conclusion='SUCCESS'
                detailsUrl="https://github.com/$script:repository/actions/runs/102/job/77"})
        }
        $script:runs=@(@{id=102;event='pull_request';head_branch=$script:branch;head_sha=$script:head;pull_requests=@()})
        $script:trace=[Collections.Generic.List[string]]::new()
        $script:mergeArguments=@()
        Mock Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' {
            param($WorkspaceRoot,$FilePath,$ArgumentList)
            $Arguments=$ArgumentList
            switch ("$FilePath $($Arguments[0])") {
                'git remote' {
                    $repo=if($Arguments -contains '--push'){$script:pushRepository}else{$script:repository}
                    return "https://github.com/$repo.git"
                }
                'git branch' { return $script:branch }
                'git status' { return $script:dirty }
                'git for-each-ref' { return $script:localRef }
                'git ls-remote' { return $script:remoteRef }
                'gh api' {
                    if($Arguments -contains '--method'){return ConvertTo-Json -InputObject $script:runs -Depth 5 -Compress}
                    return ConvertTo-Json @{delete_branch_on_merge=$script:autoDelete} -Compress
                }
                'gh pr' {
                    switch($Arguments[1]){
                        'view' {
                            $script:viewReads++
                            if($script:viewReads -eq $script:changeOnView){$script:view.headRefOid=$script:oldHead}
                            return ConvertTo-Json $script:view -Depth 5 -Compress
                        }
                        'list' { return $script:listedPrs }
                        'merge' {
                            $script:trace.Add('merge')
                            $script:mergeArguments=$Arguments
                            if($script:mergeAccepted){$script:view.state='MERGED'}
                            if($script:removeLocal -and $Arguments -contains '--delete-branch'){$script:localRef=''}
                            if($script:mergeError){throw 'FixtureMergeAdapterError'}
                            return
                        }
                    }
                }
            }
            throw "Unexpected test adapter invocation: $FilePath $Arguments"
        }
        Mock Invoke-QuietPullRequestScript -ModuleName 'Merge-PullRequest' {
            param($Name,$Arguments)
            if($Name -ceq 'Push-Workspace.ps1'){
                $script:trace.Add("push:$($Arguments.Branch):$($Arguments.ExpectedHead)")
                if($script:pushChangesHead){$script:view.headRefOid=$Arguments.ExpectedHead}
                return
            }
            if($Name -cne 'Watch-GitHubRun.ps1'){throw "Unexpected entry point: $Name"}
            $script:trace.Add("watch:$($Arguments.Repository):$($Arguments.RunId)")
            'Monitor: fixture'
            [pscustomobject]@{State=$script:watchState;RunId=$script:watchRun}
        }
        Mock Wait-QuietReleaseInterval -ModuleName 'Merge-PullRequest' {throw 'UnexpectedRunDiscoveryWait'}
    }

    It 'previews both entry points without touching Git, GitHub or the watcher' {
        Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -WhatIf
        Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -WhatIf
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 0 -Exactly
        Should -Invoke Invoke-QuietPullRequestScript -ModuleName 'Merge-PullRequest' -Times 0 -Exactly
    }

    It 'rebases the pinned head and verifiably removes both source refs by default' {
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false
        ($script:mergeArguments -join ' ') | Should -BeExactly "pr merge 7 --repo $script:repository --rebase --match-head-commit $script:head --delete-branch"
        $result.State | Should -BeExactly Merged
        $result.PullRequest | Should -Be 7
        $result.Url | Should -BeExactly $script:view.url
        $result.MergeCommit | Should -BeExactly ('c'*40)
        $result.BranchDeleted | Should -BeTrue
        $result.Head | Should -BeExactly $script:head
        $result.Method | Should -BeExactly rebase
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'git' -and ($ArgumentList -join ' ') -ceq 'ls-remote --heads origin refs/heads/feature/work'
        }
    }

    It 'uses a merge commit and preserves the source branch when requested' {
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -NoRebase -NoBranchDelete -Confirm:$false
        ($script:mergeArguments -join ' ') | Should -BeExactly "pr merge 7 --repo $script:repository --merge --match-head-commit $script:head"
        $result.Method | Should -BeExactly merge
        $result.BranchDeleted | Should -BeNullOrEmpty
    }

    It 'rejects a PR whose <Field> is invalid' -ForEach @(
        @{Field='isDraft';Value=$true;ErrorId='*PullRequestNotReady*'}
        @{Field='state';Value='CLOSED';ErrorId='*PullRequestNotReady*'}
        @{Field='baseRefName';Value='main';ErrorId='*PullRequestTargetInvalid*'}
        @{Field='isCrossRepository';Value=$true;ErrorId='*PullRequestTargetInvalid*'}
        @{Field='statusCheckRollup';Value=@();ErrorId='*PullRequestRequiredCiNotGreen*'}
    ) {
        $script:view[$Field]=$Value
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw $ErrorId
        $script:trace.Count | Should -Be 0
    }

    It 'rejects failed and pending required checks' -ForEach @(
        @{Status='COMPLETED';Conclusion='FAILURE'}
        @{Status='IN_PROGRESS';Conclusion='SUCCESS'}
    ) {
        $script:view.statusCheckRollup[0].status=$Status
        $script:view.statusCheckRollup[0].conclusion=$Conclusion
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw '*PullRequestRequiredCiNotGreen*'
        $script:trace.Count | Should -Be 0
    }

    It 'rejects different head SHAs through the exact matching guard' {
        $random=[Random]::new((Get-QuietTestSeed))
        foreach($case in 1..8){
            $other=(New-QuietRandomSha256 $random).ToLowerInvariant().Substring(0,40)
            {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -ExpectedHead $other -Confirm:$false} | Should -Throw '*PullRequestCheckpointChanged*'
        }
        $script:trace.Count | Should -Be 0
    }

    It 'accepts the explicitly pinned head and uses the supplied remote' {
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Remote project -ExpectedHead $script:head -Confirm:$false
        $result.State | Should -BeExactly Merged
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'git' -and ($ArgumentList -join ' ') -ceq 'remote get-url --push project'
        }
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'git' -and ($ArgumentList -join ' ') -ceq 'ls-remote --heads project refs/heads/feature/work'
        }
    }

    It 'protects changed and dirty local source work' {
        $script:localRef="refs/heads/$script:branch $script:oldHead"
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw '*PullRequestLocalBranchChanged*'
        $script:localRef="refs/heads/$script:branch $script:head"
        $script:dirty='?? unfinished'
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw '*PullRequestLocalBranchDirty*'
        $script:trace.Count | Should -Be 0
    }

    It 'rejects branch preservation when GitHub will automatically delete it' {
        $script:autoDelete=$true
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -NoBranchDelete -Confirm:$false} | Should -Throw '*PullRequestBranchPreservationUnavailable*'
        $script:trace.Count | Should -Be 0
    }

    It 'does not report a queued or unconfirmed merge as merged' {
        $script:mergeAccepted=$false
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw '*PullRequestMergeNotConfirmed*'
    }

    It 'preserves the original adapter failure if the merge did not happen' {
        $script:mergeAccepted=$false
        $script:mergeError=$true
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw '*FixtureMergeAdapterError*'
    }

    It 'confirms a reported merge even if the CLI failed afterward' {
        $script:mergeError=$true
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
        $result.State | Should -BeExactly Merged
        $warnings[0].Message | Should -Match '^Pull request #7 merged, but gh reported an error: FixtureMergeAdapterError'
    }

    It 'reports confirmed merge with a remaining <Location> branch' -ForEach @(
        @{Location='local'}
        @{Location='remote'}
    ) {
        if($Location -eq 'local'){$script:removeLocal=$false}
        else{$script:remoteRef="$script:head refs/heads/$script:branch"}
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false -WarningAction SilentlyContinue
        $result.State | Should -BeExactly Merged
        $result.BranchDeleted | Should -BeFalse
    }

    It 'refuses to cross from the selected fetch repository to another push repository' {
        $script:pushRepository='example/another'
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw '*PullRequestRemoteMismatch*'
        $script:trace.Count | Should -Be 0
    }

    It 'pushes the exact revision and watches its linked run, without merging by default' {
        $script:view.headRefOid=$script:oldHead
        $result=@(Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 0 -Confirm:$false)
        ($script:trace -join '|') | Should -BeExactly "push:$script:branch`:$script:head|watch:$script:repository`:102"
        $result.Count | Should -Be 2
        $result[-1].State | Should -BeExactly Success
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'gh' -and ($ArgumentList -join ' ') -ceq 'pr list --repo example/QuietCli --head feature/work --state open --limit 2 --json number'
        }
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $expected='api --method GET repos/example/QuietCli/actions/workflows/companions-ci.yml/runs -f event=pull_request -f head_sha='+('a'*40)+' -f per_page=20 --jq .workflow_runs | map({id,head_sha,head_branch,event,pull_requests: [.pull_requests[].number]})'
            $FilePath -ceq 'gh' -and ($ArgumentList -join ' ') -ceq $expected
        }
        Should -Invoke Invoke-QuietPullRequestScript -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Push-Workspace.ps1' -and $Arguments.WorkspaceRoot -eq $TestDrive -and $Arguments.Remote -ceq 'origin' -and $Arguments.Confirm -eq $false
        }
    }

    It 'merges after the explicitly associated run succeeds with both overrides forwarded' {
        $script:runs[0].pull_requests=@(7)
        $script:view.statusCheckRollup[0].detailsUrl=$null
        $result=@(Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -NoRebase -NoBranchDelete -DiscoverySeconds 0 -Confirm:$false)
        $result[-1].State | Should -BeExactly Merged
        $result[-1].Method | Should -BeExactly merge
        $script:mergeArguments | Should -Not -Contain '--delete-branch'
        ($script:trace -join '|') | Should -BeExactly "push:$script:branch`:$script:head|watch:$script:repository`:102|merge"
    }

    It 'ignores other runs and lookalike check URLs' -ForEach @(
        @{Field='head_sha';Value='b'*40}
        @{Field='head_branch';Value='feature/other'}
        @{Field='event';Value='push'}
        @{Field='pull_requests';Value=@(8)}
        @{Field='id';Value=10}
        @{Field='id';Value=0}
    ) {
        $script:runs[0][$Field]=$Value
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -DiscoverySeconds 0 -Confirm:$false} | Should -Throw '*PullRequestRunUnavailable*'
        $script:trace.Count | Should -Be 1
    }

    It 'selects the newest matching run from several candidates' {
        $script:runs+=@{id=104;event='pull_request';head_branch=$script:branch;head_sha=$script:head;pull_requests=@(7)}
        $script:watchRun=104
        $result=@(Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 0 -Confirm:$false)
        $result[-1].RunId | Should -Be 104
    }

    It 'blocks a watch when no unique open pull request exists' -ForEach @(
        @{PullRequests='[]'}
        @{PullRequests='[{"number":7},{"number":8}]'}
    ) {
        $script:listedPrs=$PullRequests
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 0 -Confirm:$false} | Should -Throw '*CommitWorkspacePullRequestUnavailable*'
        $script:trace.Count | Should -Be 0
    }

    It 'stops after push if the remote PR reports a different head' {
        $script:view.headRefOid=$script:oldHead
        $script:pushChangesHead=$false
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -DiscoverySeconds 0 -Confirm:$false} | Should -Throw '*PullRequestCheckpointChanged*'
        $script:trace.Count | Should -Be 1
    }

    It 'stops when another update changes the head during run discovery' {
        $script:changeOnView=3
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -DiscoverySeconds 0 -Confirm:$false} | Should -Throw '*PullRequestCheckpointChanged*'
        $script:trace.Count | Should -Be 1
    }

    It 'rechecks the exact reviewed head after a successful watcher' {
        $script:changeOnView=4
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -DiscoverySeconds 0 -Confirm:$false} | Should -Throw '*PullRequestCheckpointChanged*'
        $script:trace.Count | Should -Be 2
    }

    It 'does not merge when the watcher returns <State> for run <Run>' -ForEach @(
        @{State='Failed';Run=102}
        @{State='Cancelled';Run=102}
        @{State='Success';Run=99}
    ) {
        $script:watchState=$State
        $script:watchRun=$Run
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -DiscoverySeconds 0 -Confirm:$false} | Should -Throw '*PullRequestWatchDidNotSucceed*'
        $script:trace | Should -Not -Contain 'merge'
    }
}
