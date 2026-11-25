#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $commitModule = Import-QuietTestLibrary -Name 'Commit-Workspace'
}

Describe 'Test-QuietCommitWorkflowChanges' {
    It 'scopes status to scripts and workflows, including both sides of a rename' {
        Mock Invoke-CiProcess -ModuleName 'Commit-Workspace' {
            $FilePath | Should -BeExactly 'git'
            $ArgumentList | Should -Be @('--no-optional-locks','status','--porcelain=v1',
                '--untracked-files=all','--no-renames','--','scripts/','.github/workflows/')
            & $OnOutput @{Stream='stdout';Text=' D scripts/Get-OldName.ps1'} $State
            @{Outcome='Success'}
        }
        (& $commitModule { param($root) Test-QuietCommitWorkflowChanges -WorkspaceRoot $root } $TestDrive) | Should -BeTrue
        Should -Invoke Invoke-CiProcess -ModuleName 'Commit-Workspace' -Exactly 1 -ParameterFilter {
            $WorkingDirectory -ceq $TestDrive
        }
    }

    It 'ignores stderr and empty records when status reports no relevant changes' {
        Mock Invoke-CiProcess -ModuleName 'Commit-Workspace' {
            & $OnOutput @{Stream='stderr';Text='warning'} $State
            & $OnOutput @{Stream='stdout';Text=''} $State
            @{Outcome='Success'}
        }
        (& $commitModule { param($root) Test-QuietCommitWorkflowChanges -WorkspaceRoot $root } $TestDrive) | Should -BeFalse
    }

    It 'rejects a failed status query even if it already emitted a pending path' {
        Mock Invoke-CiProcess -ModuleName 'Commit-Workspace' {
            & $OnOutput @{Stream='stdout';Text='?? scripts/Get-Pending.ps1'} $State
            @{Outcome='Failed'}
        }
        { & $commitModule { param($root) Test-QuietCommitWorkflowChanges -WorkspaceRoot $root } $TestDrive } |
            Should -Throw '*CommitWorkspaceWorkflowChangesUnavailable*'
    }
}
