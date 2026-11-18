#requires -Version 7.6
# Runs the real entry point in a child pwsh against a fixture clone of a bare origin. The merged pull requests come
# from a saved gh pr list JSON file (-PullRequestsPath), so no test talks to GitHub.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name Remove-QuietMergedBranches
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Remove-QuietMergedBranches.ps1')
    $identity=@('-c','user.name=quiet-test','-c','user.email=quiet-test@invalid','-c','commit.gpgsign=false','-c','core.autocrlf=false')
    $git={param([string]$Repository,[string[]]$Arguments)
        $output=& git -C $Repository @identity @Arguments 2>&1
        if($LASTEXITCODE){throw ('git '+($Arguments -join ' ')+': '+($output -join "`n"))}
        ($output -join "`n").Trim()
    }
    $commit={param([string]$Repository,[string]$Path)
        $null=New-QuietTestFile ([IO.Path]::Combine($Repository,$Path)) ($Path+"`n")
        $null=& $git $Repository @('add','--',$Path)
        $null=& $git $Repository @('commit','-q','-m',('write '+$Path))
        & $git $Repository @('rev-parse','HEAD')
    }
    # A commit on top of the given one that no ref points to: the head GitHub merged, absent from every local branch.
    $orphan={param([string]$Repository,[string]$Parent,[string]$Message)
        & $git $Repository @('commit-tree','-p',$Parent,'-m',$Message,($Parent+'^{tree}'))
    }
    $pr={param([long]$Number,[string]$Head,[string]$Oid,[string]$Base='develop',[AllowNull()][string]$MergedAt='2026-11-18T10:00:00Z',[bool]$Fork=$false)
        [ordered]@{number=$Number;headRefName=$Head;headRefOid=$Oid;baseRefName=$Base;mergedAt=$MergedAt;isCrossRepository=$Fork}
    }
    # One fixture per test: every rule of the policy has a branch, and the work clone is on a merged branch.
    $newFixture={param([string]$Label)
        $root=[IO.Path]::Combine($TestDrive,$Label)
        $fixture=@{Root=$root;Origin=[IO.Path]::Combine($root,'origin.git');Work=[IO.Path]::Combine($root,'work');Prs=[IO.Path]::Combine($root,'prs.json')}
        [void][IO.Directory]::CreateDirectory($root)
        $null=& $git $root @('init','-q','--bare','-b','develop',$fixture.Origin)
        $null=& $git $root @('init','-q','-b','develop',$fixture.Work)
        foreach($setting in @(@('user.name','quiet-test'),@('user.email','quiet-test@invalid'),@('commit.gpgsign','false'),@('core.autocrlf','false'))){
            $null=& $git $fixture.Work (@('config')+$setting)
        }
        $base=& $commit $fixture.Work 'README.md'
        $null=& $git $fixture.Work @('remote','add','origin',$fixture.Origin)
        $null=& $git $fixture.Work @('push','-q','-u','origin','develop')
        $tips=@{}
        foreach($name in 'feature/merged','fix/behind','feature/ahead','fix/unknown-head','chore/no-pr','feature/fork','fix/unmerged','main','feature/current','feature/elsewhere'){
            $null=& $git $fixture.Work @('switch','-q','-c',$name,'develop')
            $tips[$name]=& $commit $fixture.Work (($name -replace '/','-')+'.txt')
        }
        $null=& $git $fixture.Work @('branch','chore/in-base','develop')
        $tips['chore/in-base']=$base
        $null=& $git $fixture.Work @('config','branch.feature/merged.remote','origin')
        $null=& $git $fixture.Work @('config','branch.feature/merged.merge','refs/heads/feature/merged')
        $null=& $git $fixture.Work @('switch','-q','feature/current')
        $null=& $git $fixture.Work @('worktree','add','-q',[IO.Path]::Combine($root,'elsewhere'),'feature/elsewhere')
        $aheadParent=& $git $fixture.Work @('rev-parse','feature/ahead~1')
        $prs=@(
            & $pr 1 'feature/merged' $tips['feature/merged']
            & $pr 2 'fix/behind' (& $orphan $fixture.Work $tips['fix/behind'] 'review fix pushed from GitHub')
            # The pull request was merged before the last local commit, which only exists here.
            & $pr 3 'feature/ahead' (& $orphan $fixture.Work $aheadParent 'merged head without the local commit')
            & $pr 4 'fix/unknown-head' ('e'*40)
            & $pr 5 'feature/fork' $tips['feature/fork'] -Fork $true
            & $pr 6 'fix/unmerged' $tips['fix/unmerged'] -MergedAt $null
            & $pr 7 'main' $tips['main']
            & $pr 8 'feature/current' $tips['feature/current']
            & $pr 9 'feature/elsewhere' $tips['feature/elsewhere']
            & $pr 10 'chore/no-pr' $tips['chore/no-pr'] -Base 'main'
        )
        $null=New-QuietTestFile $fixture.Prs (ConvertTo-Json -InputObject $prs -Depth 3)
        $fixture.Tips=$tips
        $fixture
    }
    $run={param($Fixture,[string[]]$Arguments)
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$Fixture.Work,'-PullRequestsPath',$Fixture.Prs)+$Arguments) -TimeoutSeconds 300
        $result.TimedOut|Should -BeFalse
        $text=($result.Output+"`n"+$result.Error) -replace '\x1B\[[0-?]*[ -/]*[@-~]','' -replace '\s+',' '
        $result|Add-Member -NotePropertyName Text -NotePropertyValue $text -PassThru
    }
    $branches={param($Fixture)@((& $git $Fixture.Work @('for-each-ref','--format=%(refname:short)','refs/heads/')).Split("`n")|Sort-Object)}
    $all=@('chore/in-base','chore/no-pr','develop','feature/ahead','feature/current','feature/elsewhere','feature/fork','feature/merged','fix/behind','fix/unknown-head','fix/unmerged','main')
}

Describe 'Remove-QuietMergedBranches.ps1' {
    It 'deletes exactly the branches a merged pull request contains, and their config' {
        $fixture=& $newFixture 'delete'
        $result=& $run $fixture @()
        $result.ExitCode|Should -Be 0 -Because $result.Text
        & $branches $fixture|Should -BeExactly @($all|Where-Object {$_ -notin 'feature/merged','fix/behind'}|Sort-Object)
        $result.Text|Should -Match ([regex]::Escape('Deleted feature/merged (was '+$fixture.Tips['feature/merged'].Substring(0,12)+', PR #1); restore with git branch feature/merged '+$fixture.Tips['feature/merged']))
        $result.Text|Should -Match 'Deleted fix/behind \(was [0-9a-f]{12}, PR #2\)'
        $null=& git -C $fixture.Work config --get-regexp '^branch\.feature/merged\.'
        $LASTEXITCODE|Should -Be 1 -Because 'the upstream settings of a deleted branch go with it'
        & $git $fixture.Work @('config','--get','branch.develop.remote')|Should -BeExactly 'origin' -Because 'other branch sections are kept'
        & $git $fixture.Work @('branch','--show-current')|Should -BeExactly 'feature/current'
        & $git $fixture.Work @('ls-remote','--heads','origin')|Should -Match 'refs/heads/develop' -Because 'the remote is never touched'
    }

    It 'also deletes a branch already in origin/develop with IncludeContainedInBase' {
        $fixture=& $newFixture 'contained'
        $result=& $run $fixture @('-IncludeContainedInBase')
        $result.ExitCode|Should -Be 0 -Because $result.Text
        & $branches $fixture|Should -BeExactly @($all|Where-Object {$_ -notin 'feature/merged','fix/behind','chore/in-base'}|Sort-Object)
        $result.Text|Should -Match 'Deleted chore/in-base \(was [0-9a-f]{12}, in refs/remotes/origin/develop\)'
    }

    It 'gives the reason of each decision and deletes nothing with PlanOnly' {
        $fixture=& $newFixture 'plan'
        $plan=Invoke-QuietScriptRemoveQuietMergedBranches -WorkspaceRoot $fixture.Work -PullRequestsPath $fixture.Prs -PlanOnly
        $reasons=@{}
        foreach($branch in $plan.Branches){$reasons[$branch.Branch]=$branch.Action+'/'+$branch.Reason+'/'+$branch.State}
        $reasons['feature/merged']|Should -BeExactly 'Delete/MergedPullRequest/Planned'
        $reasons['fix/behind']|Should -BeExactly 'Delete/MergedPullRequest/Planned'
        $reasons['feature/ahead']|Should -BeExactly 'Keep/AheadOfPullRequest/Kept'
        $reasons['fix/unknown-head']|Should -BeExactly 'Keep/PullRequestHeadUnknown/Kept'
        $reasons['feature/fork']|Should -BeExactly 'Keep/NoMergedPullRequest/Kept'
        $reasons['fix/unmerged']|Should -BeExactly 'Keep/NoMergedPullRequest/Kept'
        $reasons['chore/no-pr']|Should -BeExactly 'Keep/NoMergedPullRequest/Kept' -Because 'its pull request was merged into main, not develop'
        $reasons['chore/in-base']|Should -BeExactly 'Keep/ContainedInBaseOnly/Kept'
        $reasons['main']|Should -BeExactly 'Keep/Protected/Kept'
        $reasons['develop']|Should -BeExactly 'Keep/Protected/Kept'
        $reasons['feature/current']|Should -BeExactly 'Keep/CheckedOut/Kept'
        $reasons['feature/elsewhere']|Should -BeExactly 'Keep/CheckedOut/Kept' -Because 'a branch checked out in another worktree must survive'
        $plan.Planned|Should -BeExactly @('feature/merged','fix/behind')
        $plan.Deleted.Count|Should -Be 0
        $plan.MergedPullRequests|Should -Be 7
        & $branches $fixture|Should -BeExactly $all
    }

    It 'previews with WhatIf without reading the checkout or the pull requests' {
        $fixture=& $newFixture 'whatif'
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-WorkspaceRoot',$fixture.Work,'-PullRequestsPath',[IO.Path]::Combine($fixture.Root,'missing.json'),'-WhatIf') -TimeoutSeconds 300
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        ($result.Output -replace '\s+',' ')|Should -Match ([regex]::Escape('Delete local branches merged into develop'))
        & $branches $fixture|Should -BeExactly $all
    }

    It 'refuses <Case> and deletes nothing' -ForEach @(
        @{Case='a work branch as base';Expected='WorkBranchBaseIsWorkBranch';Build={param($f)@('-WorkspaceRoot',$f.Work,'-PullRequestsPath',$f.Prs,'-BaseBranch','feature/x','-WhatIf')}}
        @{Case='a missing pull request file';Expected='MergedBranchPullRequestsMissing';Build={param($f)@('-WorkspaceRoot',$f.Work,'-PullRequestsPath',[IO.Path]::Combine($f.Root,'missing.json'))}}
        @{Case='a malformed pull request file';Expected='MergedBranchPullRequestsInvalid';Build={param($f)@('-WorkspaceRoot',$f.Work,'-PullRequestsPath',[IO.Path]::Combine($f.Root,'bad.json'))}}
        # Without a saved file the remote must name a github.com repository; this origin is a local bare repository.
        @{Case='a remote that is not on github.com';Expected='MergedBranchRemoteNotGitHub: origin';Build={param($f)@('-WorkspaceRoot',$f.Work)}}
        @{Case='a directory inside the checkout';Expected='MergedBranchCheckoutMismatch';Build={param($f)@('-WorkspaceRoot',[IO.Path]::Combine($f.Work,'sub'),'-PullRequestsPath',$f.Prs)}}
        @{Case='a missing origin/develop with IncludeContainedInBase';Expected='MergedBranchBaseMissing: refs/remotes/upstream/develop';Build={param($f)@('-WorkspaceRoot',$f.Work,'-PullRequestsPath',$f.Prs,'-Remote','upstream','-IncludeContainedInBase')}}
    ) {
        $fixture=& $newFixture ('refuse-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $null=New-QuietTestFile ([IO.Path]::Combine($fixture.Root,'bad.json')) '{"number":1}'
        $null=New-QuietTestFile ([IO.Path]::Combine($fixture.Work,'sub','keep.txt')) "keep`n"
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (& $Build $fixture) -TimeoutSeconds 300
        $text=($result.Output+"`n"+$result.Error) -replace '\x1B\[[0-?]*[ -/]*[@-~]','' -replace '\s+',' '
        $result.ExitCode|Should -Not -Be 0 -Because $text
        $text|Should -Match ([regex]::Escape($Expected))
        & $branches $fixture|Should -BeExactly $all
    }
}
