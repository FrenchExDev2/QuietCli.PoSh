#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $script:scripts=Get-QuietTestScriptsRoot
}

Describe 'Merge-PullRequest.ps1' {
    It 'previews in a directory without Git or GitHub access' {
        $result=Invoke-QuietTestScript ([IO.Path]::Combine($script:scripts,'Merge-PullRequest.ps1')) @('-PullRequest','7','-WorkspaceRoot',$TestDrive,'-NoBranchDelete','-WhatIf')
        $result.ExitCode | Should -Be 0 -Because $result.Error
        $result.Output | Should -Match 'workspace pull request #7'
        $result.Output | Should -Match 'Squash and merge after verifying the rebase'
        @(Get-ChildItem -LiteralPath $TestDrive -Force).Count | Should -Be 0
    }
}

Describe 'Push-Workspace.ps1 with ExpectedHead' {
    It 'pushes the exact commit to a local bare remote without rewriting branch tracking' {
        $root=[IO.Path]::Combine($TestDrive,'push')
        $remote=[IO.Path]::Combine($TestDrive,'upstream')
        [void][IO.Directory]::CreateDirectory($root)
        $git={param([string[]]$Arguments)
            $output=& git -C $root @Arguments 2>&1
            if($LASTEXITCODE){throw ($output -join [Environment]::NewLine)}
            ($output -join [Environment]::NewLine).Trim()
        }
        $null=& $git @('init','-q','-b','doc/work')
        try {
            $null=& $git @('init','-q','--bare',$remote)
            $null=& $git @('remote','add','origin',$remote)
            $null=& $git @('config','--local','branch.doc/work.remote','other')
            $null=& $git @('config','--local','branch.doc/work.merge','refs/heads/custom')
            $null=& $git @('-c','user.name=quiet-test','-c','user.email=quiet-test@invalid','-c','commit.gpgSign=false','commit','-q','--allow-empty','-m','test')
            $revision=& $git @('rev-parse','HEAD')
            $entry=[IO.Path]::Combine($script:scripts,'Push-Workspace.ps1')
            $arguments=@('-WorkspaceRoot',$root,'-Remote','origin','-Branch','doc/work','-Confirm:$false','-ExpectedHead')
            $rejected=Invoke-QuietTestScript $entry ($arguments+('0'*40))
            $rejected.ExitCode | Should -Not -Be 0
            $rejected.Error | Should -Match 'PushWorkspaceHeadChanged'
            (& $git @('ls-remote','--heads','origin','refs/heads/doc/work')) | Should -BeNullOrEmpty
            $pushed=Invoke-QuietTestScript $entry ($arguments+$revision)
            $pushed.ExitCode | Should -Be 0 -Because ($pushed.Output+$pushed.Error)
            ((& $git @('ls-remote','--heads','origin','refs/heads/doc/work')) -split '\s+')[0] | Should -BeExactly $revision
            (& $git @('config','--get','branch.doc/work.remote')) | Should -BeExactly 'other'
            (& $git @('config','--get','branch.doc/work.merge')) | Should -BeExactly 'refs/heads/custom'
        } finally {
            foreach($directory in $root,$remote){
                if(![IO.Directory]::Exists($directory)){continue}
                foreach($file in [IO.Directory]::EnumerateFiles($directory,'*',[IO.SearchOption]::AllDirectories)){
                    [IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal)
                }
            }
        }
    }
}

Describe 'Watch-GitHubRun.ps1 in the terminal' {
    BeforeAll {
        $script:fixtureScripts=[IO.Path]::Combine($TestDrive,'scripts')
        $script:watcher=[IO.Path]::Combine($script:fixtureScripts,'Watch-GitHubRun.ps1')
        [void][IO.Directory]::CreateDirectory($script:fixtureScripts)
        Copy-Item -LiteralPath ([IO.Path]::Combine($script:scripts,'Watch-GitHubRun.ps1')),([IO.Path]::Combine($script:scripts,'lib')) -Destination $script:fixtureScripts -Recurse
        $null=New-QuietTestFile ([IO.Path]::Combine($script:fixtureScripts,'Invoke-GitHubRunWorker.ps1')) @'
param([long]$RunId,[string]$Repository,[string]$WorkspaceRoot,[string]$RunDirectory)
$encoding=[Text.UTF8Encoding]::new($false)
if($env:QUIET_WATCH_FIXTURE_LIVE){
    $running=@{State='Running';Case='Run 102 fixture heartbeat';Runs=@(@{State='in_progress'},@{State='queued'},@{State='queued'})}
    [IO.File]::WriteAllText([IO.Path]::Combine($RunDirectory,'status.json'),($running | ConvertTo-Json -Depth 5 -Compress),$encoding)
    Start-Sleep -Seconds 11
}
$status = @{State=$env:QUIET_WATCH_FIXTURE_STATE;Project=$Repository;Task='CI fixture';RunId=$RunId}
$receipt = @{State=$status} | ConvertTo-Json -Compress
[IO.File]::WriteAllText([IO.Path]::Combine($RunDirectory,'summary.json'),$receipt,$encoding)
'@
    }

    It 'previews without creating report files' {
        $root=[IO.Path]::Combine($TestDrive,'preview')
        $result=Invoke-QuietTestScript $script:watcher @('-RunId','102','-Repository','example/QuietCli','-WorkspaceRoot',$root,'-InTerminal','-WhatIf')
        $result.ExitCode | Should -Be 0 -Because $result.Error
        Test-Path -LiteralPath $root | Should -BeFalse
    }

    It 'displays the <State> terminal receipt and returns exit code <ExitCode>' -ForEach @(
        @{State='Success';ExitCode=0}
        @{State='Failed';ExitCode=1}
    ) {
        $root=[IO.Path]::Combine($TestDrive,$State)
        $environment=@{QUIET_WATCH_FIXTURE_STATE=$State}
        if($State -eq 'Success'){$environment.QUIET_WATCH_FIXTURE_LIVE='1'}
        $result=Invoke-QuietTestScript $script:watcher @('-RunId','102','-Repository','example/QuietCli','-WorkspaceRoot',$root,'-InTerminal','-Confirm:$false') -Environment $environment -TimeoutSeconds 35
        $result.ExitCode | Should -Be $ExitCode -Because $result.Error
        $result.Output | Should -Match 'Watching GitHub run 102 in this terminal'
        $result.Output | Should -Match ('"State":"'+$State+'"')
        if($State -eq 'Success'){
            $result.Output | Should -Match 'Run 102 fixture heartbeat'
            $result.Output | Should -Match '\[jobs\] queued: 2'
        }
        $summary=Get-ChildItem -LiteralPath $root -Filter 'summary.json' -Recurse | Select-Object -First 1
        $summary | Should -Not -BeNullOrEmpty
        $receipt=Get-Content -LiteralPath $summary.FullName -Encoding utf8 -Raw | ConvertFrom-Json
        $receipt.State.RunId | Should -Be 102
        $receipt.State.State | Should -BeExactly $State
    }
}
