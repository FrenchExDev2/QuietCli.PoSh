#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $root=Get-QuietTestWorkspaceRoot
    $scriptPath=[IO.Path]::Combine($root,'scripts','New-PullRequest.ps1')
    $body=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'body.md')) 'Résumé'
    $footer=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'footer.md')) 'Pièce jointe'
}

Describe 'New-PullRequest' {
    It 'previews the complete body locally' {
        $result=Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-BodyFile',$body,'-FooterFile',$footer,'-CiOption','preview','-PreviewBody') -TimeoutSeconds 30
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        $result.Output|Should -Match '(?ms)Résumé.*Additional CI validation.*^- \[x\] \*\*Core\*\* — \[PowerShell Preview\].*<!-- ci:preview -->.*Pièce jointe'
    }

    It 'does not resolve a remote or write the source files in WhatIf' {
        $result=Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-Title','Example','-BodyFile',$body,'-WorkspaceRoot',$TestDrive,'-WhatIf') -TimeoutSeconds 30
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        [IO.File]::ReadAllText($body,[Text.Encoding]::UTF8)|Should -BeExactly 'Résumé'
    }

    It 'creates a PR from the composed body or preserves the existing PR' {
        $fixture=[IO.Path]::Combine($TestDrive,'fixture')
        foreach($directory in 'scripts/lib','.github'){
            [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($fixture,$directory))
        }
        foreach($path in 'scripts/New-PullRequest.ps1','scripts/lib/PullRequestChecklist.psm1','scripts/lib/MergedBranches.psm1','.github/pull_request_template.md'){
            Copy-Item -LiteralPath ([IO.Path]::Combine($root,$path)) -Destination ([IO.Path]::Combine($fixture,$path))
        }
        $null=New-QuietTestFile ([IO.Path]::Combine($fixture,'scripts/lib/PullRequestUpdates.psm1')) @'
function Invoke-QuietPullRequestTool {
    param($WorkspaceRoot,$FilePath,$ArgumentList)
    switch ("$FilePath $($ArgumentList[0])") {
        'git remote' {'https://github.com/example/QuietCli.git'}
        'git branch' {'chore/work'}
        'git check-ref-format' {return}
        'git ls-remote' {('a'*40)+[char]9+'refs/heads/chore/work'}
        'gh pr' {
            if($ArgumentList[1] -ceq 'list'){
                if($env:FIXTURE_EXISTING -ceq 'yes'){
                    '[{"url":"https://github.com/example/QuietCli/pull/8","headRefName":"chore/work","baseRefName":"develop","isCrossRepository":false}]'
                }else{'[]'}
            }else{
                [IO.File]::Copy($ArgumentList[-1],$env:FIXTURE_PR_BODY)
                'https://github.com/example/QuietCli/pull/7'
            }
        }
        default {throw 'Unexpected tool'}
    }
}
Export-ModuleMember Invoke-QuietPullRequestTool
'@
        $path=[IO.Path]::Combine($fixture,'scripts','New-PullRequest.ps1')
        $captured=[IO.Path]::Combine($fixture,'captured.md')
        $arguments=@('-Title','Example','-BodyFile',$body,'-FooterFile',$footer,'-CiOption','preview','-Confirm:$false')
        $created=Invoke-QuietTestScript -ScriptPath $path -ArgumentList $arguments -Environment @{FIXTURE_EXISTING='no';FIXTURE_PR_BODY=$captured} -TimeoutSeconds 30
        $created.ExitCode | Should -Be 0 -Because ($created.Output+$created.Error)
        $created.Output | Should -Match '/pull/7'
        [IO.File]::ReadAllText($captured,[Text.Encoding]::UTF8) | Should -Match '(?ms)Résumé.*^- \[x\] \*\*Core\*\* — \[PowerShell Preview\].*<!-- ci:preview -->.*Pièce jointe'
        [IO.File]::Delete($captured)
        $existing=Invoke-QuietTestScript -ScriptPath $path -ArgumentList $arguments -Environment @{FIXTURE_EXISTING='yes';FIXTURE_PR_BODY=$captured} -TimeoutSeconds 30
        $existing.ExitCode | Should -Be 0 -Because ($existing.Output+$existing.Error)
        $existing.Output | Should -Match '/pull/8'
        Test-Path -LiteralPath $captured | Should -BeFalse
    }
}
