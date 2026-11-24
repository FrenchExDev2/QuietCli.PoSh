#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $root=Get-QuietTestWorkspaceRoot
    $scriptPath=[IO.Path]::Combine($root,'scripts','Publish-WorkspacePullRequest.ps1')
}

Describe 'Publish-WorkspacePullRequest' {
    It 'previews with no writes and no Git or GitHub checkout' {
        $empty=[IO.Path]::Combine($TestDrive,'uncreated')
        $result=Invoke-QuietTestScript -ScriptPath $scriptPath -ArgumentList @('-Message','Review changes','-Body','Résumé','-WorkspaceRoot',$empty,'-ScriptMutation','-WhatIf') -TimeoutSeconds 30
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
        $result=Invoke-QuietTestScript -ScriptPath $copy -ArgumentList @('-Message','Commit message','-Body','Résumé','-Title','PR title','-Footer','Pièce jointe','-ScriptMutation','-ReadyToRun','-Preview:$false','-Confirm:$false') -TimeoutSeconds 30
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        $actual=$result.Output|ConvertFrom-Json
        $actual.Message|Should -BeExactly 'Commit message'
        $actual.Body|Should -BeExactly 'Résumé'
        $actual.Title|Should -BeExactly 'PR title'
        $actual.Footer|Should -BeExactly 'Pièce jointe'
        $actual.Options.'script-mutation'|Should -BeTrue
        $actual.Options.readytorun|Should -BeTrue
        $actual.Options.preview|Should -BeFalse
        $actual.DiscoverySeconds|Should -Be 120
    }

    It 'maps several discovered companions to separate mutation and profiling options' {
        $copy=[IO.Path]::Combine($TestDrive,'discovered','Publish-WorkspacePullRequest.ps1')
        $lib=[IO.Path]::Combine([IO.Path]::GetDirectoryName($copy),'lib')
        $null=New-QuietTestFile ([IO.Path]::Combine($lib,'Merge-PullRequest.psm1')) @'
function Invoke-QuietPublishPullRequest {
    [CmdletBinding(SupportsShouldProcess)]
    param($WorkspaceRoot,$Message,$Body,$Title,$Footer,$Options,$DiscoverySeconds)
    if($PSCmdlet.ShouldProcess($WorkspaceRoot)){$Options|ConvertTo-Json -Compress}
}
'@
        $null=New-QuietTestFile ([IO.Path]::Combine($lib,'CiCompanions.psm1')) @'
function Read-QuietCiCompanions {
    @{Companions=[ordered]@{Git=@{Name='Git';Mutation=$true};Box=@{Name='Box';Mutation=$true}}}
}
function Get-QuietCompanions {
    param($Configuration,$Name,$Capability)
    foreach($requested in $Name){if($requested -notin $Configuration.Companions.Keys){throw 'unknown companion'}}
    $Configuration.Companions.Keys | Where-Object {$_ -in $Name}
}
'@
        Copy-Item -LiteralPath $scriptPath -Destination $copy
        $driver=New-QuietTestFile ([IO.Path]::Combine([IO.Path]::GetDirectoryName($copy),'Invoke-Fixture.ps1')) @'
& ([IO.Path]::Combine($PSScriptRoot,'Publish-WorkspacePullRequest.ps1')) -Message 'Commit' -Body 'Body' -RunProfile Git,Box -Mutation -Parallel:$false -ScriptMutationNoInputCache -Confirm:$false
'@
        $result=Invoke-QuietTestScript -ScriptPath $driver -TimeoutSeconds 30
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        $actual=$result.Output|ConvertFrom-Json
        $actual.'run-profile-mutation-git'|Should -BeTrue
        $actual.'run-profile-mutation-box'|Should -BeTrue
        $actual.'profiling-git'|Should -BeTrue
        $actual.'profiling-box'|Should -BeTrue
        $actual.'mutation-serial'|Should -BeTrue
        $actual.'script-mutation-no-input-cache'|Should -BeTrue
    }
}
