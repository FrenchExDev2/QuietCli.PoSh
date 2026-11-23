#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $root=Get-QuietTestWorkspaceRoot
    $scriptPath=[IO.Path]::Combine($root,'scripts','Publish-WorkspacePullRequest.ps1')
}

Describe 'Publish-WorkspacePullRequest' {
    It 'previews with no writes and no Git or GitHub checkout' {
        $empty=[IO.Path]::Combine($TestDrive,'uncreated')
        $result=Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-Message','Review changes','-Body','Résumé','-WorkspaceRoot',$empty,'-Mutation','-WhatIf') -TimeoutSeconds 30
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        $result.Output|Should -Match 'Commit, push, publish the pull request'
        Test-Path -LiteralPath $empty|Should -BeFalse
    }

    It 'forwards the text, title, footer and each explicit checkbox override' {
        $copy=[IO.Path]::Combine($TestDrive,'scripts','Publish-WorkspacePullRequest.ps1')
        $null=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'scripts','lib','Merge-PullRequest.psm1')) @'
function Invoke-QuietPublishPullRequest {
    [CmdletBinding(SupportsShouldProcess)]
    param($WorkspaceRoot,$Message,$Body,$Title,$Footer,$Options,$DiscoverySeconds)
    if($PSCmdlet.ShouldProcess($WorkspaceRoot)){
        $PSBoundParameters | ConvertTo-Json -Compress
    }
}
Export-ModuleMember Invoke-QuietPublishPullRequest
'@
        Copy-Item -LiteralPath $scriptPath -Destination $copy
        $result=Invoke-QuietTestScript -ScriptPath $copy -ArgumentList @('-Message','Commit message','-Body','Résumé','-Title','PR title','-Footer','Pièce jointe','-Mutation','-ReadyToRun','-Preview:$false','-Confirm:$false') -TimeoutSeconds 30
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        $actual=$result.Output|ConvertFrom-Json
        $actual.Message|Should -BeExactly 'Commit message'
        $actual.Body|Should -BeExactly 'Résumé'
        $actual.Title|Should -BeExactly 'PR title'
        $actual.Footer|Should -BeExactly 'Pièce jointe'
        $actual.Options.mutation|Should -BeTrue
        $actual.Options.readytorun|Should -BeTrue
        $actual.Options.preview|Should -BeFalse
        $actual.DiscoverySeconds|Should -Be 120
    }
}
