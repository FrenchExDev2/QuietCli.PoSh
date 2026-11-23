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
        $script:afterPush=@{}
        $script:view=@{
            number=7;url="https://github.com/$script:repository/pull/7";headRefName=$script:branch;headRefOid=$script:head
            baseRefName='develop';isCrossRepository=$false;isDraft=$false;state='OPEN';mergeCommit=@{oid='c'*40}
            statusCheckRollup=@(@{__typename='CheckRun';name='QuietCli required CI';status='COMPLETED';conclusion='SUCCESS'
                detailsUrl="https://github.com/$script:repository/actions/runs/102/job/77"})
        }
        $script:runs=@(@{id=102;event='pull_request';head_branch=$script:branch;head_sha=$script:head;pull_requests=@()})
        $script:trace=[Collections.Generic.List[string]]::new()
        $script:mergeArguments=@()
        Mock Assert-QuietPullRequestCiEvidence -ModuleName 'Merge-PullRequest' {}
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
                foreach($field in $script:afterPush.Keys){$script:view[$field]=$script:afterPush[$field]}
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
        $transcript=[IO.Path]::Combine($TestDrive,'pull-request-preview.txt')
        $null=Start-Transcript -LiteralPath $transcript
        try {
            Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -WhatIf
            Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -NoRebase -NoBranchDelete -WhatIf
            Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -WhatIf
        } finally {$null=Stop-Transcript}
        $preview=[IO.File]::ReadAllText($transcript,[Text.Encoding]::UTF8)
        $preview | Should -Match 'Merge with --rebase and delete the source branch.*workspace pull request #7 via origin'
        $preview | Should -Match 'Merge with --merge and preserve the branch.*workspace pull request #7 via origin'
        $preview | Should -Match 'Push and watch the existing pull request'
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 0 -Exactly
        Should -Invoke Invoke-QuietPullRequestScript -ModuleName 'Merge-PullRequest' -Times 0 -Exactly
    }

    It 'rebases the pinned head and verifiably removes both source refs by default' {
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable mergeErrors
        @($warnings).Count | Should -Be 0
        @($mergeErrors).Count | Should -Be 0
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
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'git' -and ($ArgumentList -join ' ') -ceq 'branch --show-current'
        }
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'git' -and ($ArgumentList -join ' ') -ceq 'status --porcelain=v1 --untracked-files=normal'
        }
        Should -Invoke Assert-QuietPullRequestCiEvidence -ModuleName 'Merge-PullRequest' -Exactly -Times 1 -ParameterFilter {
            $Number -eq 7 -and $ExpectedHead -ceq ('a'*40) -and $CheckRollup.Count -eq 1 -and
            $CheckRollup[0].detailsUrl -ceq 'https://github.com/example/QuietCli/actions/runs/102/job/77'
        }
    }

    It 'uses a merge commit and preserves the source branch when requested' {
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -NoRebase -NoBranchDelete -Confirm:$false
        ($script:mergeArguments -join ' ') | Should -BeExactly "pr merge 7 --repo $script:repository --merge --match-head-commit $script:head"
        $result.Method | Should -BeExactly merge
        $result.BranchDeleted | Should -BeNullOrEmpty
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'gh' -and ($ArgumentList -join ' ') -ceq 'api repos/example/QuietCli --jq {delete_branch_on_merge}'
        }
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
        $result=Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false -WarningAction SilentlyContinue -WarningVariable warnings
        $result.State | Should -BeExactly Merged
        $result.BranchDeleted | Should -BeFalse
        @($warnings).Count | Should -Be 1
        $warnings[0].Message | Should -BeExactly 'Pull request #7 merged, but the source branch still exists.'
    }

    It 'refuses to cross from the selected fetch repository to another push repository' {
        $script:pushRepository='example/another'
        {Invoke-QuietMergePullRequest -WorkspaceRoot $TestDrive -PullRequest 7 -Confirm:$false} | Should -Throw '*PullRequestRemoteMismatch*'
        $script:trace.Count | Should -Be 0
    }

    It 'pushes the exact revision and watches its linked run, without merging by default' {
        $script:view.headRefOid=$script:oldHead
        $result=@(Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 0 -Confirm:$false -ErrorVariable watchErrors)
        @($watchErrors).Count | Should -Be 0
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
        Should -Invoke Invoke-QuietPullRequestScript -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Watch-GitHubRun.ps1' -and $Arguments.RunId -eq 102 -and $Arguments.Confirm -eq $false
        }
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Times 1 -Exactly -ParameterFilter {
            $FilePath -ceq 'git' -and ($ArgumentList -join ' ') -ceq 'branch --show-current'
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
        if($Field -ceq 'id' -and $Value -eq 0){$script:runs[0].pull_requests=@(7)}
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -DiscoverySeconds 0 -Confirm:$false} | Should -Throw '*PullRequestRunUnavailable*'
        $script:trace.Count | Should -Be 1
    }

    It 'rejects a check URL containing the workflow URL inside a redirect' {
        $script:view.statusCheckRollup[0].detailsUrl='https://example.invalid/?redirect=https://github.com/example/QuietCli/actions/runs/102/job/77'
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 0 -Confirm:$false} |
            Should -Throw '*PullRequestRunUnavailable*'
    }

    It 'stops before sleeping when the discovery deadline is reached exactly' {
        $script:runs=@()
        $script:instant=[datetime]::new(2026,1,1,0,0,0,[DateTimeKind]::Utc)
        $script:clockReads=0
        Mock Get-Date -ModuleName 'Merge-PullRequest' {
            $script:clockReads++
            if($script:clockReads -eq 1){$script:instant}else{$script:instant.AddSeconds(5)}
        }

        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 5 -Confirm:$false} |
            Should -Throw '*PullRequestRunUnavailable*'
        Should -Invoke Wait-QuietReleaseInterval -ModuleName 'Merge-PullRequest' -Exactly -Times 0
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Exactly -Times 1 -ParameterFilter {
            $FilePath -ceq 'gh' -and $ArgumentList -contains 'event=pull_request'
        }
    }

    It 'stops at the poll budget even if the clock has not advanced' {
        $script:runs=@()
        Mock Get-Date -ModuleName 'Merge-PullRequest' {[datetime]::new(2026,1,1,0,0,0,[DateTimeKind]::Utc)}
        Mock Wait-QuietReleaseInterval -ModuleName 'Merge-PullRequest' {}

        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 5 -Confirm:$false} |
            Should -Throw '*PullRequestRunUnavailable*'
        Should -Invoke Wait-QuietReleaseInterval -ModuleName 'Merge-PullRequest' -Exactly -Times 1 -ParameterFilter {$Seconds -eq 5}
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Exactly -Times 2 -ParameterFilter {
            $FilePath -ceq 'gh' -and $ArgumentList -contains 'event=pull_request'
        }
    }

    It 'waits once for a missing run and rereads the PR only after a candidate is available' {
        $script:readyRuns=$script:runs
        $script:runs=@()
        Mock Wait-QuietReleaseInterval -ModuleName 'Merge-PullRequest' {$script:runs=$script:readyRuns}
        $result=@(Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 60 -Confirm:$false)
        $result[-1].RunId | Should -Be 102
        $script:viewReads | Should -Be 3
        Should -Invoke Wait-QuietReleaseInterval -ModuleName 'Merge-PullRequest' -Exactly -Times 1 -ParameterFilter {$Seconds -eq 5}
    }

    It 'blocks unsafe PR state <Field> before push' -ForEach @(
        @{Field='state';Value='CLOSED'},@{Field='headRefName';Value='feature/other'},@{Field='isDraft';Value=$true}
    ) {
        $script:view[$Field]=$Value
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -MergePullRequest -DiscoverySeconds 0 -Confirm:$false} |
            Should -Throw '*CommitWorkspacePullRequestChanged*'
        $script:trace.Count | Should -Be 0
    }

    It 'blocks unsafe PR state <Field> after push' -ForEach @(
        @{Field='state';Value='CLOSED'},@{Field='headRefName';Value='feature/other'},@{Field='headRefOid';Value='b'*40}
    ) {
        $script:afterPush[$Field]=$Value
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 0 -Confirm:$false} |
            Should -Throw '*PullRequestCheckpointChanged*'
        $script:trace.Count | Should -Be 1
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -Exactly -Times 0 -ParameterFilter {
            $FilePath -ceq 'gh' -and $ArgumentList -contains 'event=pull_request'
        }
    }

    It 'stops before calling the watcher if its run identifier is invalid' {
        Mock Find-QuietPullRequestRun -ModuleName 'Merge-PullRequest' {0}
        {Invoke-QuietCommitPullRequest -WorkspaceRoot $TestDrive -Revision $script:head -DiscoverySeconds 0 -Confirm:$false} |
            Should -Throw '*PullRequestRunIdentityInvalid*'
        $script:trace.Count | Should -Be 1
    }

    It 'uses the checkout owning the module when no merge workspace is given' {
        $expectedRoot=Split-Path -Parent (Get-QuietTestScriptsRoot)
        Invoke-QuietMergePullRequest -PullRequest 7 -Confirm:$false | Out-Null
        Should -Invoke Invoke-QuietPullRequestTool -ModuleName 'Merge-PullRequest' -ParameterFilter {
            $WorkspaceRoot -ceq $expectedRoot -and $FilePath -ceq 'gh' -and $ArgumentList[1] -ceq 'merge'
        } -Exactly -Times 1
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
