#requires -Version 7.6
# Runs the real entry point in a child pwsh against fixture repositories: a bare origin, a seed clone that moves
# develop forward, and the work clone the script operates on.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name WorkBranch
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Start-QuietWorkBranch.ps1')
    $seed=Get-QuietTestSeed
    $identity=@('-c','user.name=quiet-test','-c','user.email=quiet-test@invalid','-c','commit.gpgsign=false','-c','core.autocrlf=false')
    $git={param([string]$Repository,[string[]]$Arguments,[switch]$AllowFailure)
        $output=& git -C $Repository @identity @Arguments 2>&1
        if($LASTEXITCODE -and !$AllowFailure){throw ('git '+($Arguments -join ' ')+': '+($output -join "`n"))}
        ($output -join "`n").Trim()
    }
    $write={param([string]$Repository,[string]$Path,[string]$Text)$null=New-QuietTestFile ([IO.Path]::Combine($Repository,$Path)) $Text}
    $read={param([string]$Repository,[string]$Path)[IO.File]::ReadAllText([IO.Path]::Combine($Repository,$Path))}
    $commit={param([string]$Repository,[string]$Path,[string]$Text)
        & $write $Repository $Path $Text
        $null=& $git $Repository @('add','--',$Path)
        $null=& $git $Repository @('commit','-q','-m',('write '+$Path))
    }
    $newFixture={param([string]$Label)
        $root=[IO.Path]::Combine($TestDrive,$Label)
        $fixture=@{Origin=[IO.Path]::Combine($root,'origin.git');Seed=[IO.Path]::Combine($root,'seed');Work=[IO.Path]::Combine($root,'work')}
        [void][IO.Directory]::CreateDirectory($root)
        $null=& $git $root @('init','-q','--bare','-b','develop',$fixture.Origin)
        $null=& $git $root @('init','-q','-b','develop',$fixture.Seed)
        & $commit $fixture.Seed 'README.md' "base`n"
        $null=& $git $fixture.Seed @('remote','add','origin',$fixture.Origin)
        $null=& $git $fixture.Seed @('push','-q','origin','develop')
        $null=& $git $root @('clone','-q','--branch','develop',$fixture.Origin,$fixture.Work)
        # The child script shelves with git stash, which needs an identity of its own.
        foreach($setting in @(@('user.name','quiet-test'),@('user.email','quiet-test@invalid'),@('commit.gpgsign','false'),@('core.autocrlf','false'))){
            $null=& $git $fixture.Work (@('config')+$setting)
        }
        $fixture
    }
    $advance={param($Fixture,[string]$Path)
        & $commit $Fixture.Seed $Path "upstream`n"
        $null=& $git $Fixture.Seed @('push','-q','origin','develop')
        & $git $Fixture.Seed @('rev-parse','HEAD')
    }
    $start={param($Fixture,[string[]]$Arguments)
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList (@('-WorkspaceRoot',$Fixture.Work)+$Arguments) -TimeoutSeconds 300
        $run.TimedOut|Should -BeFalse
        $run|Add-Member -NotePropertyName Text -NotePropertyValue ($run.Output+"`n"+$run.Error) -PassThru
    }
    $snapshot={param($Fixture)
        [pscustomobject]@{
            Branch=& $git $Fixture.Work @('branch','--show-current')
            Head=& $git $Fixture.Work @('rev-parse','HEAD')
            Status=& $git $Fixture.Work @('status','--porcelain=v1','--untracked-files=all')
            Readme=& $read $Fixture.Work 'README.md'
            Stashes=& $git $Fixture.Work @('stash','list')
            Branches=& $git $Fixture.Work @('branch','--list','--format=%(refname:short)')
        }
    }
}

Describe 'Start-QuietWorkBranch.ps1' {
    It 'starts the new branch from the pulled remote develop, not from the current work branch, and carries pending work over' {
        $fixture=& $newFixture 'carry'
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        & $commit $fixture.Work 'old.txt' "old`n"
        & $write $fixture.Work 'README.md' "edited`n"
        & $write $fixture.Work 'staged.txt' "staged`n"
        $null=& $git $fixture.Work @('add','--','staged.txt')
        & $write $fixture.Work 'notes/untracked.txt' "untracked`n"
        $tip=& $advance $fixture 'upstream.txt'

        $run=& $start $fixture @('-Kind','feature','-Name','demo')

        $run.ExitCode|Should -Be 0 -Because $run.Text
        & $git $fixture.Work @('branch','--show-current')|Should -BeExactly 'feature/demo'
        & $git $fixture.Work @('rev-parse','HEAD')|Should -BeExactly $tip
        & $git $fixture.Work @('rev-parse','develop')|Should -BeExactly $tip -Because 'develop is fast-forwarded, never rewritten'
        & $git $fixture.Work @('ls-tree','--name-only','HEAD')|Should -Not -Match 'old\.txt' -Because 'the commit of the previous work branch must not leak into the new one'
        & $git $fixture.Work @('config','--get','branch.feature/demo.merge') -AllowFailure|Should -BeNullOrEmpty -Because 'a work branch never tracks develop'
        & $read $fixture.Work 'README.md'|Should -BeExactly "edited`n"
        & $git $fixture.Work @('diff','--cached','--name-only')|Should -BeExactly 'staged.txt' -Because 'the index is restored with --index'
        & $read $fixture.Work 'notes/untracked.txt'|Should -BeExactly "untracked`n"
        @((& $git $fixture.Work @('stash','list')).Split("`n")).Count|Should -Be 1 -Because 'the shelf is retained'
        & $git $fixture.Work @('rev-parse','fix/old')|Should -Not -BeExactly $tip
        $run.Text|Should -Match 'Shelf retained: [0-9a-f]{40}'
    }

    It 'accepts the whole branch name and does not shelve a clean checkout' {
        $fixture=& $newFixture 'clean'
        $run=& $start $fixture @('-Branch','chore/tidy')
        $run.ExitCode|Should -Be 0 -Because $run.Text
        & $git $fixture.Work @('branch','--show-current')|Should -BeExactly 'chore/tidy'
        & $git $fixture.Work @('stash','list')|Should -BeNullOrEmpty
        $run.Text|Should -Not -Match 'Shelf retained'
    }

    It 'refuses <Case> and leaves the checkout untouched' -ForEach @(
        @{Case='an unknown kind';Arguments=@('-Branch','hotfix/x');Expected='WorkBranchKindInvalid'}
        @{Case='an invalid name';Arguments=@('-Kind','feature','-Name','a..b');Expected='WorkBranchNameInvalid'}
        @{Case='a work branch as base';Arguments=@('-Kind','feature','-Name','x','-BaseBranch','fix/old');Expected='WorkBranchBaseIsWorkBranch'}
        @{Case='a branch that exists locally';Arguments=@('-Kind','feature','-Name','x');Expected='WorkBranchAlreadyExists: feature/x';Prepare='Local'}
        @{Case='a branch that exists on the remote';Arguments=@('-Kind','feature','-Name','x');Expected='WorkBranchAlreadyExistsOnRemote: origin/feature/x';Prepare='Remote'}
        @{Case='a missing local base';Arguments=@('-Kind','feature','-Name','x','-BaseBranch','main');Expected='WorkBranchLocalBaseMissing: main'}
        @{Case='a detached checkout';Arguments=@('-Kind','feature','-Name','x');Expected='WorkBranchInitialStateInvalid: Detached';Prepare='Detached'}
    ) {
        $fixture=& $newFixture ('refuse-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        switch($Prepare){
            'Local'{$null=& $git $fixture.Work @('branch','feature/x','develop')}
            'Remote'{$null=& $git $fixture.Seed @('push','-q','origin','develop:refs/heads/feature/x')}
            'Detached'{$null=& $git $fixture.Work @('switch','-q','--detach','develop')}
        }
        & $write $fixture.Work 'README.md' "pending`n"
        & $write $fixture.Work 'new.txt' "new`n"
        $before=& $snapshot $fixture

        $run=& $start $fixture $Arguments

        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match ([regex]::Escape($Expected))
        $after=& $snapshot $fixture
        foreach($property in 'Branch','Head','Status','Readme','Stashes','Branches'){$after.$property|Should -BeExactly $before.$property -Because ($property+' must not change')}
    }

    It 'refuses a checkout with a merge in progress' {
        $fixture=& $newFixture 'merge'
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        & $commit $fixture.Work 'README.md' "fix side`n"
        $null=& $git $fixture.Work @('switch','-q','develop')
        $null=& $git $fixture.Work @('switch','-q','-c','fix/other')
        & $commit $fixture.Work 'README.md' "other side`n"
        $null=& $git $fixture.Work @('merge','fix/old') -AllowFailure
        $before=& $snapshot $fixture

        $run=& $start $fixture @('-Kind','feature','-Name','x')

        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match 'WorkBranchInitialStateInvalid: Conflicted, Operation:Merge\b'
        (& $snapshot $fixture).Status|Should -BeExactly $before.Status
        & $git $fixture.Work @('branch','--list','feature/x')|Should -BeNullOrEmpty
    }

    It 'previews with WhatIf without shelving, pulling or creating anything' {
        $fixture=& $newFixture 'whatif'
        & $write $fixture.Work 'README.md' "pending`n"
        $null=& $advance $fixture 'upstream.txt'
        $before=& $snapshot $fixture

        $run=& $start $fixture @('-Kind','feature','-Name','x','-WhatIf')

        $run.ExitCode|Should -Be 0 -Because $run.Text
        # The WhatIf prefix is localized; the operation text is ours.
        $run.Text|Should -Match ([regex]::Escape('Shelve pending work, pull origin/develop and create feature/x'))
        $after=& $snapshot $fixture
        foreach($property in 'Branch','Head','Status','Readme','Stashes','Branches'){$after.$property|Should -BeExactly $before.$property}
    }

    It 'validates the name under WhatIf' {
        $fixture=& $newFixture 'whatif-invalid'
        $run=& $start $fixture @('-Kind','feature','-Name','x.lock','-WhatIf')
        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match 'WorkBranchNameInvalid'
    }

    It 'puts the pending work back on the original branch when develop cannot be fast-forwarded' {
        $fixture=& $newFixture 'diverged'
        & $commit $fixture.Work 'local.txt' "local only`n"
        $null=& $advance $fixture 'upstream.txt'
        $null=& $git $fixture.Work @('switch','-q','-c','fix/old')
        & $write $fixture.Work 'README.md' "pending`n"
        & $write $fixture.Work 'new.txt' "new`n"
        $before=& $snapshot $fixture

        $run=& $start $fixture @('-Kind','feature','-Name','x')

        $run.ExitCode|Should -Not -Be 0
        $run.Text|Should -Match 'WorkBranchGitFailed: pull'
        $run.Text|Should -Match 'pending work restored on fix/old; shelf [0-9a-f]{40} retained'
        $after=& $snapshot $fixture
        $after.Branch|Should -BeExactly 'fix/old'
        $after.Status|Should -BeExactly $before.Status
        $after.Readme|Should -BeExactly "pending`n"
        & $git $fixture.Work @('branch','--list','feature/x')|Should -BeNullOrEmpty
    }

    It 'only accepts names that git also accepts' {
        $alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/'
        $null=Invoke-QuietProperty -Name 'work-branch-git-ref' -Seed $seed -Count 150 -Generator {param($random)
            (Get-QuietRandomItem $random (Get-QuietWorkBranchKinds))+'/'+(New-QuietRandomString $random -Alphabet $alphabet -MinLength 1 -MaxLength 12)
        } -Property {param($case)
            try{$null=Resolve-QuietWorkBranchName -Branch $case}catch{return $true}
            $null=& git check-ref-format --branch $case 2>&1
            $LASTEXITCODE -eq 0
        }
    }
}
